import CoreGraphics
import Foundation
import RoadSignMathAPI
import SignCapture
import SignReading

/// The parts of a post made from what Capture kept: the photo to send, the
/// checked numbers, the place's state, and who found it.
public enum PostParts {
  /// The photo to send: upright, at most 2048 pixels on its long side, a
  /// JPEG with none of the original's metadata (no GPS, no camera), and
  /// under the server's 4 MB. The numbers' boxes are fractions of the
  /// upright picture, so they still fit.
  public static func photo(_ file: PhotoFile) -> Data? {
    for (pixels, quality) in [(2048, 0.85), (2048, 0.7), (1600, 0.7), (1200, 0.6)] {
      guard let image = file.image(maxPixels: pixels), let data = PhotoFile.jpeg(image, quality: quality) else {
        return nil
      }
      if data.count <= APIClient.photoBytes { return data }
    }
    return nil
  }

  /// The kept numbers as the server takes them: the value, what it was
  /// read from (`EXIT 7B`) when that says more than the value, why the
  /// value differs from it, and where it is on the photo.
  public static func numbers(_ kept: [CheckedNumber]) -> [PostNumber] {
    kept.prefix(NumberList.limit).map { number in
      let value = number.valueText
      let source = number.sourceText ?? number.text
      let text = source == value ? nil : source.clipped(to: 40)
      return PostNumber(value: value, text: text, why: why(number, value: value, text: text), box: number.box.map(box))
    }
  }

  private static func why(_ number: CheckedNumber, value: String, text: String?) -> String? {
    guard text != nil else { return nil }
    if number.isFixed { return "Fixed by hand" }
    guard number.isRead else { return nil }
    let why = number.why
    return why == "Read from the photo" ? nil : why.clipped(to: 60)
  }

  /// A box kept inside the photo, as the server checks it.
  static func box(_ box: NormalizedBox) -> [Double] {
    let x = min(max(box.x, 0), 1)
    let y = min(max(box.y, 0), 1)
    let width = min(max(box.width, 0), 1 - x)
    let height = min(max(box.height, 0), 1 - y)
    return [x, y, width, height].map { ($0 * 10_000).rounded() / 10_000 }
  }

  /// The state in a place's label, `MN` from `Bloomington, MN`: the last
  /// part when it's two capital letters.
  public static func state(in label: String) -> String? {
    guard let last = label.split(separator: ",").last?.trimmingCharacters(in: .whitespaces),
      last.count == 2, last.allSatisfy({ $0.isASCII && $0.isUppercase })
    else { return nil }
    return last
  }

  /// A title to start from, `Bloomington Math`, from the place's town.
  public static func title(near label: String?) -> String? {
    guard let town = label?.split(separator: ",").first?.trimmingCharacters(in: .whitespaces), !town.isEmpty
    else { return nil }
    return "\(town) Math".clipped(to: APIClient.titleMax)
  }

  /// Who found it. Alone, the poster is its finder, which the server
  /// assumes, so nil. With others who spotted it, the poster took the
  /// photo and the others spotted it: a player as `@handle` (one of
  /// `players`), anyone else by name. Blank and repeated names are
  /// dropped, and it stops at the server's six.
  public static func finders(poster: String, spotters: [String], players: Set<String>) -> [PostFinder]? {
    var finders: [PostFinder] = []
    var seen: Set<String> = [poster.lowercased()]
    for raw in spotters {
      let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      if text.hasPrefix("@"), players.contains(String(text.dropFirst()).lowercased()) {
        let handle = String(text.dropFirst()).lowercased()
        guard seen.insert(handle).inserted else { continue }
        finders.append(.player(handle, .spotted))
      } else {
        let name = text.clipped(to: APIClient.finderNameMax)
        guard seen.insert("name:" + name.lowercased()).inserted else { continue }
        finders.append(.named(name, .spotted))
      }
      if finders.count == APIClient.findersMax - 1 { break }
    }
    return finders.isEmpty ? nil : [.player(poster, .tookPhoto)] + finders
  }
}
