import Foundation

/// Reads a sign's numbers from a photo: Vision's text, read in one or more
/// passes, then the number rules.
///
/// Vision often skips a digit standing on its own (a distance at the end of
/// a row, a route number in a shield). Reading again a crop of the part of
/// the photo that holds the text finds many of them, and so does reading
/// each quarter of the photo, so a photo is read in passes, each adding only
/// numbers in places no earlier pass read one. The spike (docs/SPIKE.md)
/// chose all six passes for a taken photo: on the 16 new-era signs they read
/// every number on 14, against 12 with the text region alone and 9 with one
/// pass, at about five times the time of one pass.
public struct SignReader: Sendable {
  public enum Passes: String, Sendable, Hashable, Codable, CaseIterable {
    /// The whole photo, once.
    case whole
    /// The whole photo, then a crop around all the text it found.
    case textRegion
    /// The two above, then four overlapping quarters of the photo.
    case textRegionAndQuarters
  }

  public var recognition: RecognitionOptions
  public var passes: Passes
  public var rules: NumberExtractor.Rules

  public init(
    recognition: RecognitionOptions = .photo, passes: Passes = .textRegionAndQuarters,
    rules: NumberExtractor.Rules = .signRules
  ) {
    self.recognition = recognition
    self.passes = passes
    self.rules = rules
  }

  /// What the app reads a taken photo with.
  public static let photo = SignReader()

  /// The four overlapping quarters, each 55% of the photo on a side.
  public static let quarters: [NormalizedBox] = [(0.0, 0.0), (0.45, 0.0), (0.0, 0.45), (0.45, 0.45)].map {
    NormalizedBox(x: $0.0, y: $0.1, width: 0.55, height: 0.55)
  }

  /// The crop the text-region pass reads: every line found, padded by 8% of
  /// the photo on each side. Nil when nothing was found.
  public static func textRegion(of lines: [RecognizedLine]) -> NormalizedBox? {
    guard let first = lines.first else { return nil }
    return lines.dropFirst().reduce(first.box) { $0.union($1.box) }.padded(dx: 0.08, dy: 0.08)
  }

  /// The numbers from the lines of each pass, in pass order. A number from a
  /// later pass is kept only where no number already kept lies (half the
  /// smaller box overlapping), so a number two passes read counts once, and
  /// the first pass wins when two passes read the same place differently.
  public func numbers(fromPasses passes: [[RecognizedLine]]) -> [ReadNumber] {
    let extractor = NumberExtractor(rules: rules)
    var kept: [ReadNumber] = []
    for (index, lines) in passes.enumerated() {
      let found = extractor.numbers(in: lines)
      if index == 0 {
        kept = found
        continue
      }
      let earlier = kept
      kept += found.filter { number in
        !earlier.contains { $0.box.overlap(with: number.box) > 0.5 }
      }
    }
    return kept
  }
}

#if canImport(Vision)
import CoreGraphics

extension SignReader {
  /// The lines each pass read on `image`, boxes on the whole image.
  public func linesByPass(in image: CGImage) async throws -> [[RecognizedLine]] {
    let recognizer = TextRecognizer(options: recognition)
    let whole = try await recognizer.lines(in: image)
    var result = [whole]
    guard passes != .whole else { return result }
    if let region = Self.textRegion(of: whole) {
      result.append(try await recognizer.lines(in: image, region: region))
    }
    if passes == .textRegionAndQuarters {
      for quarter in Self.quarters {
        result.append(try await recognizer.lines(in: image, region: quarter))
      }
    }
    return result
  }

  /// The numbers on the sign in `image`.
  public func numbers(in image: CGImage) async throws -> [ReadNumber] {
    numbers(fromPasses: try await linesByPass(in: image))
  }
}
#endif
