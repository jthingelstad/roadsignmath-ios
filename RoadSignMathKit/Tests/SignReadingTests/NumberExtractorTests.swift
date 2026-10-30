import Foundation
import Testing

@testable import SignReading

private func read(_ text: String, rules: NumberExtractor.Rules = .signRules) -> [ReadNumber] {
  NumberExtractor(rules: rules).numbers(inText: text)
}

private func values(_ text: String, rules: NumberExtractor.Rules = .signRules) -> [Decimal] {
  read(text, rules: rules).map(\.value)
}

private func decimal(_ text: String) -> Decimal {
  Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
}

@Suite struct DesignExampleTests {
  /// Every example on the design's "Check the numbers" screen, with the
  /// label it shows.
  @Test(arguments: [
    ("82nd St", "82", "82nd", "Letters dropped"),
    ("90th St", "90", "90th", "Letters dropped"),
    ("EXIT 7B", "7", "7B", "Read as 7"),
    ("HOV 2+", "2", "2", "Read from the photo"),
    ("1 MILE", "1", "1", "Read from the photo"),
    ("EXIT 8", "8", "8", "Read from the photo"),
  ])
  func readsOneNumber(text: String, number: String, source: String, why: String) throws {
    let numbers = read(text)
    try #require(numbers.count == 1)
    #expect(numbers[0].value == decimal(number))
    #expect(numbers[0].text == number)
    #expect(numbers[0].sourceText == source)
    #expect(numbers[0].why == why)
  }

  @Test func splitsATimeRange() {
    let numbers = read("6AM-10AM")
    #expect(numbers.map(\.value) == [6, 10])
    #expect(numbers.map(\.text) == ["6", "10"])
    #expect(numbers.allSatisfy { $0.why == "Times split in two" })
    #expect(numbers.allSatisfy { $0.sourceText == "6AM-10AM" })
  }

  @Test func readsTheExpressLaneSign() {
    // The lines Vision read on the 2025 I-35W express lane photo.
    let lines = [
      "EXPRESS LANE", "OR HOV 2+ ONLY", "6AM-10AM", "MON-FRI", "EXIT 8", "82nd St", "1 MILE", "EXIT 7B", "90th St",
    ]
    let numbers = NumberExtractor().numbers(in: lines.map { RecognizedLine(text: $0, box: .fullImage) })
    #expect(numbers.map(\.value) == [2, 6, 10, 8, 82, 1, 7, 90])
  }
}

@Suite struct NumberRuleTests {
  @Test(arguments: [
    ("6-10 PM", [6, 10]),
    ("7 AM TO 9 AM", [7, 9]),
    ("3PM-7PM", [3, 7]),
    ("6:30-9 PM", [6, 30, 9]),
    ("7:30", [7, 30]),
    ("10:00 PM", [10, 0]),
  ] as [(String, [Decimal])])
  func splitsTimes(text: String, expected: [Decimal]) {
    let numbers = read(text)
    #expect(numbers.map(\.value) == expected)
    #expect(numbers.allSatisfy { $0.reason == .timesSplit })
  }

  @Test func aLoneHourDropsItsLetters() {
    let numbers = read("OPEN 6AM")
    #expect(numbers.map(\.value) == [6])
    #expect(numbers.first?.why == "Letters dropped")
  }

  @Test(arguments: [
    ("1/2 MILE", "0.5", "1/2"),
    ("3/4 MI", "0.75", "3/4"),
    ("½ MILE", "0.5", "½"),
    ("1½ MILES", "1.5", "1½"),
    ("2.5 MILES", "2.5", "2.5"),
    ("12,000 LBS", "12000", "12,000"),
  ])
  func readsFractionsDecimalsAndThousands(text: String, value: String, shown: String) throws {
    let numbers = read(text)
    try #require(numbers.count == 1)
    #expect(numbers[0].value == decimal(value))
    #expect(numbers[0].text == shown)
    #expect(numbers[0].why == "Read from the photo")
  }

  @Test func aMixedNumberWithASpaceStaysTwoNumbers() {
    // "EXIT 12 1/2 MILE" is exit 12, half a mile: a space can't tell.
    #expect(values("1 1/2 MILE") == [1, decimal("0.5")])
  }

  @Test(arguments: [
    ("I-35/94", [35, 94]),
    ("10/30", [10, 30]),
    ("5/3", [5, 3]),
  ] as [(String, [Decimal])])
  func aSlashThatIsNotAFractionSplits(text: String, expected: [Decimal]) {
    #expect(values(text) == expected)
  }

  @Test(arguments: [
    ("LOTS 1,3,5", [1, 3, 5]),
    ("1,3.5", [1, 3, 5]),
    ("1.3.5", [1, 3, 5]),
    ("12,000", [12000]),
    ("1,234,567", [1_234_567]),
    ("27.28", [27.28]),
  ] as [(String, [Decimal])])
  func listsSplitButThousandsAndDecimalsDont(text: String, expected: [Decimal]) {
    #expect(values(text) == expected)
  }

  @Test func routeShieldsAndSuffixes() {
    #expect(read("I-94").map(\.why) == ["Read from the photo"])
    #expect(values("I-94") == [94])
    #expect(read("35W").first?.why == "Read as 35")
    #expect(read("55MPH").first?.why == "Letters dropped")
    #expect(values("US 52 / MN 55") == [52, 55])
    #expect(values("I35W80") == [35, 80])
    #expect(read("I35W80").allSatisfy { $0.reason == .lettersDropped })
  }

  @Test func aHyphenIsNeverAMinus() {
    #expect(values("I-94") == [94])
    #expect(values("MON-FRI") == [])
    #expect(values("EXIT 11-12") == [11, 12])
  }

  @Test func punctuationAroundNumbers() {
    #expect(values("TROY 24.") == [24])
    #expect(values("$3.49") == [decimal("3.49")])
    #expect(values("(9)") == [9])
    #expect(values("Fair Play 6 →") == [6])
  }

  @Test func leadingZerosAreDropped() {
    #expect(read("ROUTE 007").first?.text == "7")
    #expect(read("ROUTE 007").first?.value == 7)
  }

  @Test func aCyrillicZeIsAThree() {
    // Vision read the 3 on the 2023 Genesis sign as "З".
    let numbers = read("З")
    #expect(numbers.map(\.value) == [3])
    #expect(numbers.first?.sourceText == "З")
  }

  @Test(arguments: [
    ("７:３０", [7, 30]),
    ("６AM-１０AM", [6, 10]),
    ("EXIT ٣", [3]),
    ("𝟕 MILES TO EXIT 8", [7, 8]),
  ] as [(String, [Decimal])])
  func digitsFromOtherScriptsReadAsDigits(text: String, expected: [Decimal]) {
    #expect(values(text) == expected)
    #expect(values(text, rules: .digitsOnly) == expected)
  }

  @Test func aDigitWithAMarkIsNotADigitAndNothingCrashes() {
    // One Character, "７" plus a combining accent: no rule reads it.
    #expect(values("７\u{0301}:30") == [30])
    #expect(values("1\u{0301}/2 MILE") == [2])
  }

  @Test func theSourceKeepsTheOriginalCharacters() {
    #expect(read("EXIT ٣").first?.sourceText == "٣")
    #expect(read("𝟕 MILES TO EXIT 8").last?.sourceText == "8")
  }

  @Test func noDigitsNoNumbers() {
    #expect(read("E Greenbush").isEmpty)
    #expect(read("").isEmpty)
  }

  @Test func textAfterAnEmojiKeepsItsPlace() {
    let numbers = read("🚗 EXIT 7B")
    #expect(numbers.map(\.value) == [7])
    #expect(numbers.first?.sourceText == "7B")
  }
}

@Suite struct DigitsOnlyTests {
  @Test func readsEveryRunOfDigits() {
    #expect(values("1/2 MILE", rules: .digitsOnly) == [1, 2])
    #expect(values("6AM-10AM", rules: .digitsOnly) == [6, 10])
    #expect(values("12,000", rules: .digitsOnly) == [12, 0])
    #expect(read("82nd St", rules: .digitsOnly).first?.why == "Read from the photo")
  }
}

@Suite struct NumberBoxTests {
  let line = RecognizedLine(
    text: "EXIT 7B",
    box: NormalizedBox(x: 0.1, y: 0.2, width: 0.4, height: 0.1),
    words: [
      RecognizedWord(range: 0..<4, box: NormalizedBox(x: 0.1, y: 0.2, width: 0.2, height: 0.1)),
      RecognizedWord(range: 5..<7, box: NormalizedBox(x: 0.4, y: 0.2, width: 0.1, height: 0.1)),
    ])

  @Test func aNumberInPartOfAWordGetsItsShare() throws {
    let number = try #require(NumberExtractor().numbers(in: line).first)
    #expect(abs(number.box.x - 0.4) < 1e-9)
    #expect(abs(number.box.width - 0.05) < 1e-9)
    #expect(number.box.y == 0.2)
  }

  @Test func aNumberAcrossWordsGetsTheirUnion() throws {
    let spread = RecognizedLine(
      text: "6 - 10 PM", box: .fullImage,
      words: [
        RecognizedWord(range: 0..<1, box: NormalizedBox(x: 0.1, y: 0.1, width: 0.1, height: 0.1)),
        RecognizedWord(range: 2..<3, box: NormalizedBox(x: 0.25, y: 0.1, width: 0.05, height: 0.1)),
        RecognizedWord(range: 4..<6, box: NormalizedBox(x: 0.35, y: 0.1, width: 0.1, height: 0.1)),
        RecognizedWord(range: 7..<9, box: NormalizedBox(x: 0.5, y: 0.1, width: 0.1, height: 0.1)),
      ])
    let numbers = NumberExtractor().numbers(in: spread)
    #expect(numbers.map(\.value) == [6, 10])
    #expect(numbers[0].box == NormalizedBox(x: 0.1, y: 0.1, width: 0.1, height: 0.1))
    #expect(numbers[1].box == NormalizedBox(x: 0.35, y: 0.1, width: 0.1, height: 0.1))
  }

  @Test func withoutWordsTheLineIsShared() throws {
    let plain = RecognizedLine(text: "AB 12", box: NormalizedBox(x: 0, y: 0, width: 1, height: 0.2))
    let number = try #require(NumberExtractor().numbers(in: plain).first)
    #expect(abs(number.box.x - 0.6) < 1e-9)
    #expect(abs(number.box.width - 0.4) < 1e-9)
  }

  @Test func confidenceComesFromTheLine() {
    let line = RecognizedLine(text: "EXIT 8", box: .fullImage, confidence: 0.5)
    #expect(NumberExtractor().numbers(in: line).first?.confidence == 0.5)
  }
}
