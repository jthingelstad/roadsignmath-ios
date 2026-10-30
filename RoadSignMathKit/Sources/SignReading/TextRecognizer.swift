#if canImport(Vision)
import CoreGraphics
import Foundation
import Vision

/// How Vision reads a photo.
public struct RecognitionOptions: Sendable, Hashable, Codable {
  public enum Level: String, Sendable, Hashable, Codable, CaseIterable {
    case accurate
    case fast
  }

  public var level: Level
  /// Vision's language correction. It tends to turn digits into words, so
  /// numbers read better with it off.
  public var usesLanguageCorrection: Bool
  /// Photos narrower than this (in pixels) are scaled up 2x before reading.
  /// Nil reads every photo at its own size.
  public var upscalesBelowWidth: Int?
  /// The smallest text to read, as a fraction of the image's height. Nil
  /// leaves Vision's default.
  public var minimumTextHeightFraction: Float?
  /// BCP 47 language codes, most likely first.
  public var languages: [String]

  public init(
    level: Level = .accurate,
    usesLanguageCorrection: Bool = false,
    upscalesBelowWidth: Int? = 1000,
    minimumTextHeightFraction: Float? = nil,
    languages: [String] = ["en-US"]
  ) {
    self.level = level
    self.usesLanguageCorrection = usesLanguageCorrection
    self.upscalesBelowWidth = upscalesBelowWidth
    self.minimumTextHeightFraction = minimumTextHeightFraction
    self.languages = languages
  }

  /// What the app reads a taken photo with.
  public static let photo = RecognitionOptions()
}

/// Reads the text on a photo with Vision.
public struct TextRecognizer: Sendable {
  public var options: RecognitionOptions

  public init(options: RecognitionOptions = .photo) {
    self.options = options
  }

  /// The lines of text on `image`, upright as given, with their boxes on
  /// the whole image. With a `region`, only that part of the image is read
  /// (cropped, and scaled up if it is small), and the boxes are mapped back.
  public func lines(in image: CGImage, region: NormalizedBox? = nil) async throws -> [RecognizedLine] {
    var input = image
    if let region {
      let pixels = CGRect(
        x: region.x * Double(image.width), y: region.y * Double(image.height),
        width: region.width * Double(image.width), height: region.height * Double(image.height)
      ).integral
      guard let cropped = image.cropping(to: pixels) else { return [] }
      input = cropped
    }
    if let limit = options.upscalesBelowWidth, input.width < limit,
      let larger = ImageScaling.scaled(input, by: 2)
    {
      input = larger
    }

    var request = RecognizeTextRequest()
    request.recognitionLevel = options.level == .fast ? .fast : .accurate
    request.usesLanguageCorrection = options.usesLanguageCorrection
    request.recognitionLanguages = options.languages.map { Locale.Language(identifier: $0) }
    if let height = options.minimumTextHeightFraction {
      request.minimumTextHeightFraction = height
    }

    let observations = try await request.perform(on: input)
    let lines = observations.compactMap { observation -> RecognizedLine? in
      guard let best = observation.topCandidates(1).first else { return nil }
      return RecognizedLine(
        text: best.string,
        box: NormalizedBox(observation.boundingBox),
        confidence: best.confidence,
        words: Self.words(of: best))
    }
    guard let region else { return lines }
    return lines.map { $0.mapped(into: region) }
  }

  /// Each space-separated word of the line with Vision's box for it.
  static func words(of text: RecognizedText) -> [RecognizedWord] {
    let string = text.string
    var words: [RecognizedWord] = []
    var offset = 0
    var index = string.startIndex
    while index < string.endIndex {
      if string[index].isWhitespace {
        index = string.index(after: index)
        offset += 1
        continue
      }
      var end = index
      var length = 0
      while end < string.endIndex, !string[end].isWhitespace {
        end = string.index(after: end)
        length += 1
      }
      if let rectangle = text.boundingBox(for: index..<end) {
        words.append(
          RecognizedWord(range: offset..<(offset + length), box: NormalizedBox(rectangle.boundingBox)))
      }
      offset += length
      index = end
    }
    return words
  }
}

extension NormalizedBox {
  /// From Vision's box, whose origin is at the bottom left.
  init(_ rect: NormalizedRect) {
    self.init(
      x: rect.origin.x, y: 1 - rect.origin.y - rect.height,
      width: rect.width, height: rect.height)
  }
}
#endif
