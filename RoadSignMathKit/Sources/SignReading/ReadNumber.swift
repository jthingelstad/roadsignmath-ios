import Foundation

/// A rectangle on a photo in normalized coordinates (0...1 on each axis), with
/// the origin at the top left and y growing down, as the photo is shown.
/// Vision's own boxes have their origin at the bottom left; `TextRecognizer`
/// flips them.
public struct NormalizedBox: Sendable, Hashable, Codable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  public static let fullImage = NormalizedBox(x: 0, y: 0, width: 1, height: 1)

  public var maxX: Double { x + width }
  public var maxY: Double { y + height }

  /// The smallest box holding both.
  public func union(_ other: NormalizedBox) -> NormalizedBox {
    let minX = min(x, other.x)
    let minY = min(y, other.y)
    return NormalizedBox(
      x: minX, y: minY,
      width: max(maxX, other.maxX) - minX,
      height: max(maxY, other.maxY) - minY)
  }

  /// A horizontal slice of this box, `from` and `to` as fractions of its width.
  /// Used to place a number that is only part of a word ("6" in "6AM-10AM").
  public func horizontalSlice(from start: Double, to end: Double) -> NormalizedBox {
    let lower = max(0, min(1, start))
    let upper = max(lower, min(1, end))
    return NormalizedBox(x: x + width * lower, y: y, width: width * (upper - lower), height: height)
  }

  public var area: Double { width * height }

  /// This box, given in the coordinates of `region`, in the coordinates of
  /// the whole image `region` is part of.
  public func mapped(into region: NormalizedBox) -> NormalizedBox {
    NormalizedBox(
      x: region.x + x * region.width, y: region.y + y * region.height,
      width: width * region.width, height: height * region.height)
  }

  /// The box grown by `dx` and `dy` on each side, kept on the image.
  public func padded(dx: Double, dy: Double) -> NormalizedBox {
    let minX = max(0, x - dx)
    let minY = max(0, y - dy)
    return NormalizedBox(x: minX, y: minY, width: min(1, maxX + dx) - minX, height: min(1, maxY + dy) - minY)
  }

  /// How much of the smaller box lies inside the other, 0...1.
  public func overlap(with other: NormalizedBox) -> Double {
    let width = min(maxX, other.maxX) - max(x, other.x)
    let height = min(maxY, other.maxY) - max(y, other.y)
    guard width > 0, height > 0 else { return 0 }
    let smaller = min(area, other.area)
    return smaller > 0 ? (width * height) / smaller : 0
  }
}

/// A word Vision read within a line: its place in the line's text (in
/// `Character`s) and its box.
public struct RecognizedWord: Sendable, Hashable, Codable {
  public var range: Range<Int>
  public var box: NormalizedBox

  public init(range: Range<Int>, box: NormalizedBox) {
    self.range = range
    self.box = box
  }
}

/// One line of text Vision read on a photo.
public struct RecognizedLine: Sendable, Hashable, Codable {
  public var text: String
  public var box: NormalizedBox
  public var confidence: Float
  /// The line's words with their own boxes. Empty when they aren't known; a
  /// number's box is then estimated from its place in the line.
  public var words: [RecognizedWord]

  public init(text: String, box: NormalizedBox, confidence: Float = 1, words: [RecognizedWord] = []) {
    self.text = text
    self.box = box
    self.confidence = confidence
    self.words = words
  }

  /// This line, read on `region` of an image, placed on the whole image.
  public func mapped(into region: NormalizedBox) -> RecognizedLine {
    RecognizedLine(
      text: text, box: box.mapped(into: region), confidence: confidence,
      words: words.map { RecognizedWord(range: $0.range, box: $0.box.mapped(into: region)) })
  }
}

/// Why a number reads as it does. Shown on "Check the numbers" next to each
/// number, so the labels are short and for players.
public enum ReadingReason: String, Sendable, Hashable, Codable, CaseIterable {
  /// The number is on the sign as it is: `EXIT 8`, `1 MILE`, `HOV 2+`, `1/2`.
  case readFromPhoto
  /// Letters joined to the number were left off: `82nd St`, `35W`, `55MPH`.
  case lettersDropped
  /// One letter joined to the number was left off: `EXIT 7B` reads as 7.
  case readAs
  /// A time was split into its numbers: `6AM-10AM` gives 6 and 10, `7:30`
  /// gives 7 and 30.
  case timesSplit
}

/// A number read off a sign.
public struct ReadNumber: Sendable, Hashable, Codable {
  /// The number's value. Fractions are kept as their decimal value
  /// (`1/2` is 0.5); `text` keeps the exact form.
  public var value: Decimal
  /// The number as a player sees it: `7`, `1/2`, `2.5`, `12,000`.
  public var text: String
  /// The text on the sign it came from: `7B`, `82nd`, `6AM-10AM`.
  public var sourceText: String
  public var reason: ReadingReason
  /// Where the number is on the photo.
  public var box: NormalizedBox
  /// Vision's confidence in the line it came from.
  public var confidence: Float

  public init(
    value: Decimal, text: String, sourceText: String, reason: ReadingReason,
    box: NormalizedBox = .fullImage, confidence: Float = 1
  ) {
    self.value = value
    self.text = text
    self.sourceText = sourceText
    self.reason = reason
    self.box = box
    self.confidence = confidence
  }

  /// The "why" label "Check the numbers" shows.
  public var why: String {
    switch reason {
    case .readFromPhoto: "Read from the photo"
    case .lettersDropped: "Letters dropped"
    case .readAs: "Read as \(text)"
    case .timesSplit: "Times split in two"
    }
  }
}
