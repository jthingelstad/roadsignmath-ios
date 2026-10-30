import Foundation

/// Turns the lines Vision read on a sign into the numbers a player can use.
///
/// The rules, in the order they claim text (a rule never sees text an earlier
/// one claimed):
///
/// 1. Time ranges split in two: `6AM-10AM` and `6-10 PM` give 6 and 10.
/// 2. Clock times split in two: `7:30` gives 7 and 30.
/// 3. Fractions: `1/2`, `½`, `1½`. A slash is a fraction only with
///    a small denominator (2, 3, 4, 8, 16) above the numerator; otherwise
///    each side is its own number (`35/94` gives 35 and 94).
/// 4. Lists: `LOTS 1,3,5` gives 1, 3 and 5.
/// 5. Thousands with commas: `12,000` is 12000.
/// 6. Decimals: `2.5`. `27.28` is a decimal too, though on one archive sign
///    it was a list Vision misread; "Check the numbers" is where that's fixed.
/// 7. Everything else, a word at a time: digits alone read as they are
///    (`EXIT 8`, `1 MILE`, `HOV 2+`); one letter joined on is left off
///    ("Read as 7" for `7B`); more letters are dropped (`82nd`, `55MPH`).
///
/// A hyphen is never a minus sign: on a sign it joins (`I-94`, `6AM-10AM`).
/// The rules are pure and know nothing of Vision, so they test anywhere.
public struct NumberExtractor: Sendable {
  public enum Rules: String, Sendable, Hashable, Codable, CaseIterable {
    /// The sign rules above.
    case signRules
    /// Every run of digits as a number, nothing more. The spike's baseline.
    case digitsOnly
  }

  public var rules: Rules

  public init(rules: Rules = .signRules) {
    self.rules = rules
  }

  /// The numbers on all the lines, line by line in reading order.
  public func numbers(in lines: [RecognizedLine]) -> [ReadNumber] {
    lines.flatMap { numbers(in: $0) }
  }

  /// The numbers on one line, left to right.
  public func numbers(in line: RecognizedLine) -> [ReadNumber] {
    let found: [Found]
    switch rules {
    case .signRules: found = Self.signRules(line.text)
    case .digitsOnly: found = Self.digitsOnly(line.text)
    }
    return found.sorted { $0.range.lowerBound < $1.range.lowerBound }.map { item in
      ReadNumber(
        value: item.value,
        text: item.text,
        sourceText: Self.substring(line.text, item.sourceRange),
        reason: item.reason,
        box: Self.box(for: item.range, in: line),
        confidence: line.confidence)
    }
  }

  /// The numbers in a piece of text, each boxed as the whole image. For tests
  /// and for text typed in.
  public func numbers(inText text: String) -> [ReadNumber] {
    numbers(in: RecognizedLine(text: text, box: .fullImage))
  }

  // MARK: - Rules

  /// A number found in a line. `range` is where the number's own characters
  /// are (for its box); `sourceRange` is the text it was read from.
  struct Found {
    var value: Decimal
    var text: String
    var range: Range<Int>
    var sourceRange: Range<Int>
    var reason: ReadingReason
  }

  static let ampm = #"(?:[AaPp]\.?\s?[Mm]\.?)"#

  static func signRules(_ text: String) -> [Found] {
    var scan = Scan(text)

    // 1. Time ranges: "6AM-10AM", "6-10AM", "7 AM TO 9 AM", "6:30-9 PM".
    scan.claim(
      #"(?<!\d)(\d{1,2})(?::(\d{2}))?\s*"# + ampm + #"?\s*(?:-|–|—|TO|to|To)\s*(\d{1,2})(?::(\d{2}))?\s*"#
        + ampm + #"(?![A-Za-z])"#
    ) { match in
      [1, 2, 3, 4].compactMap { match.group($0) }.map { group in
        Found(
          value: Decimal(Int(group.text)!), text: plainInteger(group.text), range: group.range,
          sourceRange: match.range, reason: .timesSplit)
      }
    }

    // 2. Clock times: "7:30", "10:00 PM".
    scan.claim(#"(?<!\d)(\d{1,2}):(\d{2})(?!\d)(?:\s*"# + ampm + #"(?![A-Za-z]))?"#) { match in
      [1, 2].compactMap { match.group($0) }.map { group in
        Found(
          value: Decimal(Int(group.text)!), text: plainInteger(group.text), range: group.range,
          sourceRange: match.range, reason: .timesSplit)
      }
    }

    // 3. Fractions: unicode fractions ("½", "1½"), then a/b. "1 1/2" stays
    // two numbers, 1 and 1/2: a space can as well be two numbers side by side
    // ("EXIT 12 1/2 MILE").
    scan.claim(#"(\d*)([½⅓⅔¼¾⅛⅜⅝⅞])"#) { match in
      guard let glyph = match.group(2), let fraction = vulgarFractions[glyph.text] else { return nil }
      let whole = match.group(1).map { Decimal(Int($0.text)!) } ?? 0
      let wholeText = match.group(1).map { plainInteger($0.text) } ?? ""
      return [
        Found(
          value: whole + fraction, text: wholeText + glyph.text, range: match.range,
          sourceRange: match.range, reason: .readFromPhoto)
      ]
    }
    scan.claim(#"(?<![\d/])(\d{1,2})\s*[/⁄]\s*(\d{1,2})(?![\d/])"#) { match in
      guard let numerator = match.group(1), let denominator = match.group(2),
        let fraction = fractionValue(numerator.text, denominator.text)
      else { return nil }
      return [
        Found(
          value: fraction, text: "\(numerator.text)/\(denominator.text)", range: match.range,
          sourceRange: match.range, reason: .readFromPhoto)
      ]
    }

    // 4. Lists: "LOTS 1,3,5" (and "1,3.5", as Vision may read it) are each
    // their own number. Thousands and a single decimal are left for the next
    // rules.
    scan.claim(#"(?<![\d.,])\d+(?:[.,]\d+)+(?!\d)"#) { match in
      let text = match.text
      if text.range(of: #"^\d{1,3}(?:,\d{3})+$"#, options: .regularExpression) != nil
        || text.range(of: #"^\d+\.\d+$"#, options: .regularExpression) != nil
      {
        return nil
      }
      return digitRuns(in: text).map { run in
        let digits = substring(text, run)
        let range = (match.range.lowerBound + run.lowerBound)..<(match.range.lowerBound + run.upperBound)
        return Found(
          value: Decimal(string: digits, locale: posix)!, text: plainInteger(digits), range: range,
          sourceRange: range, reason: .readFromPhoto)
      }
    }

    // 5. Thousands: "12,000".
    scan.claim(#"(?<![\d,])\d{1,3}(?:,\d{3})+(?![\d,])"#) { match in
      let digits = match.text.replacingOccurrences(of: ",", with: "")
      return [
        Found(
          value: Decimal(string: digits, locale: posix)!, text: match.text, range: match.range,
          sourceRange: match.range, reason: .readFromPhoto)
      ]
    }

    // 6. Decimals: "2.5". A trailing or leading dot is punctuation.
    scan.claim(#"(?<![\d.])\d+\.\d+(?![\d.])"#) { match in
      [
        Found(
          value: Decimal(string: match.text, locale: posix)!, text: match.text, range: match.range,
          sourceRange: match.range, reason: .readFromPhoto)
      ]
    }

    // 7. Words with digits in them.
    scan.claim(#"[A-Za-z0-9]*[0-9][A-Za-z0-9]*"#) { match in
      let word = match.text
      let letters = word.filter { $0.isLetter }
      let runs = digitRuns(in: word)
      let reason: ReadingReason
      if letters.isEmpty {
        reason = .readFromPhoto
      } else if runs.count == 1, letters.count == 1 {
        reason = .readAs
      } else {
        reason = .lettersDropped
      }
      return runs.map { run in
        let digits = substring(word, run)
        let range = (match.range.lowerBound + run.lowerBound)..<(match.range.lowerBound + run.upperBound)
        return Found(
          value: Decimal(string: digits, locale: posix)!, text: plainInteger(digits), range: range,
          sourceRange: match.range, reason: reason)
      }
    }

    return scan.found
  }

  static func digitsOnly(_ text: String) -> [Found] {
    var scan = Scan(text)
    scan.claim(#"[0-9]+"#) { match in
      [
        Found(
          value: Decimal(string: match.text, locale: posix)!, text: plainInteger(match.text),
          range: match.range, sourceRange: match.range, reason: .readFromPhoto)
      ]
    }
    return scan.found
  }

  // MARK: - Helpers

  static let posix = Locale(identifier: "en_US_POSIX")

  static let vulgarFractions: [String: Decimal] = [
    "½": Decimal(1) / 2, "⅓": Decimal(1) / 3, "⅔": Decimal(2) / 3, "¼": Decimal(1) / 4,
    "¾": Decimal(3) / 4, "⅛": Decimal(1) / 8, "⅜": Decimal(3) / 8, "⅝": Decimal(5) / 8,
    "⅞": Decimal(7) / 8,
  ]

  /// A fraction's value, if `numerator/denominator` reads as one on a sign.
  static func fractionValue(_ numerator: String, _ denominator: String) -> Decimal? {
    guard let top = Int(numerator), let bottom = Int(denominator),
      [2, 3, 4, 8, 16].contains(bottom), top > 0, top < bottom
    else { return nil }
    return Decimal(top) / Decimal(bottom)
  }

  /// "007" as "7", "00" as "0".
  static func plainInteger(_ digits: String) -> String {
    let trimmed = digits.drop { $0 == "0" }
    return trimmed.isEmpty ? "0" : String(trimmed)
  }

  /// The runs of digits in a word, as character ranges.
  static func digitRuns(in word: String) -> [Range<Int>] {
    var runs: [Range<Int>] = []
    var start: Int?
    for (index, character) in word.enumerated() {
      if character.isASCII && character.isNumber {
        if start == nil { start = index }
      } else if let begin = start {
        runs.append(begin..<index)
        start = nil
      }
    }
    if let begin = start { runs.append(begin..<word.count) }
    return runs
  }

  static func substring(_ text: String, _ range: Range<Int>) -> String {
    let start = text.index(text.startIndex, offsetBy: range.lowerBound)
    let end = text.index(start, offsetBy: range.count)
    return String(text[start..<end])
  }

  /// The box of the characters in `range`: the words it covers, or the part
  /// of a word it is, or, with no words known, its share of the line.
  static func box(for range: Range<Int>, in line: RecognizedLine) -> NormalizedBox {
    let overlapping = line.words.filter { $0.range.overlaps(range) }
    if overlapping.isEmpty {
      let length = max(line.text.count, 1)
      return line.box.horizontalSlice(
        from: Double(range.lowerBound) / Double(length), to: Double(range.upperBound) / Double(length))
    }
    if overlapping.count == 1, let word = overlapping.first {
      let length = max(word.range.count, 1)
      let start = max(range.lowerBound, word.range.lowerBound) - word.range.lowerBound
      let end = min(range.upperBound, word.range.upperBound) - word.range.lowerBound
      return word.box.horizontalSlice(from: Double(start) / Double(length), to: Double(end) / Double(length))
    }
    return overlapping.dropFirst().reduce(overlapping[0].box) { $0.union($1.box) }
  }
}

/// Runs the rules over a line in turn. Text a rule claims is blanked out (the
/// same number of characters, so offsets hold) before the next rule looks.
struct Scan {
  struct Group {
    var text: String
    var range: Range<Int>
  }

  struct Match {
    var text: String
    var range: Range<Int>
    var groups: [Group?]

    /// Capture group `index` (from 1), if it matched.
    func group(_ index: Int) -> Group? {
      index < groups.count ? groups[index] : nil
    }
  }

  private var masked: NSString
  private(set) var found: [NumberExtractor.Found] = []

  /// Letters from other scripts Vision sometimes gives for a digit on an
  /// English sign (a Cyrillic Ze for 3). Each is one UTF-16 unit, like the
  /// digit, so offsets hold.
  static let lookalikeDigits: [Character: Character] = ["З": "3", "з": "3"]

  init(_ text: String) {
    masked = String(text.map { Self.lookalikeDigits[$0] ?? $0 }) as NSString
    characterOffsets = Self.characterOffsets(of: text)
  }

  /// UTF-16 offset to `Character` offset, so ranges line up with Vision's
  /// words and with `String` indexing.
  private let characterOffsets: [Int: Int]

  private static func characterOffsets(of text: String) -> [Int: Int] {
    var offsets: [Int: Int] = [:]
    var utf16 = 0
    for (index, character) in text.enumerated() {
      offsets[utf16] = index
      utf16 += character.utf16.count
    }
    offsets[utf16] = text.count
    return offsets
  }

  private func characters(_ range: NSRange) -> Range<Int>? {
    guard range.location != NSNotFound,
      let lower = characterOffsets[range.location],
      let upper = characterOffsets[range.location + range.length]
    else { return nil }
    return lower..<upper
  }

  /// Finds `pattern` in the text not yet claimed. Each match `handle` turns
  /// into numbers is claimed; a match it returns nil for is left for later
  /// rules.
  mutating func claim(_ pattern: String, _ handle: (Match) -> [NumberExtractor.Found]?) {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      assertionFailure("Bad pattern: \(pattern)")
      return
    }
    let text = masked as String
    let results = regex.matches(in: text, range: NSRange(location: 0, length: masked.length))
    var claimed: [NSRange] = []
    for result in results {
      guard let range = characters(result.range) else { continue }
      var groups: [Group?] = [nil]
      if result.numberOfRanges > 1 {
        for index in 1..<result.numberOfRanges {
          let groupRange = result.range(at: index)
          if groupRange.location == NSNotFound || groupRange.length == 0 {
            groups.append(nil)
          } else if let characterRange = characters(groupRange) {
            groups.append(Group(text: masked.substring(with: groupRange), range: characterRange))
          } else {
            groups.append(nil)
          }
        }
      }
      let match = Match(text: masked.substring(with: result.range), range: range, groups: groups)
      if let numbers = handle(match) {
        found.append(contentsOf: numbers)
        claimed.append(result.range)
      }
    }
    if !claimed.isEmpty {
      let mutable = NSMutableString(string: masked)
      for range in claimed {
        // Blank each UTF-16 unit; a blanked emoji or fraction glyph becomes
        // spaces, which no rule matches.
        mutable.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
      }
      masked = mutable
    }
  }
}
