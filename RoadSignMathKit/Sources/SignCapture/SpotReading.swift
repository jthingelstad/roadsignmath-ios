import Foundation
import SignReading

/// "+ Add a number we missed" with a tap on the photo: the part of the
/// photo around the tap is read again on its own, close up, which finds
/// many numbers the whole photo's reading skipped (the spike's crops did
/// the same), and the number nearest the tap is offered.
public enum SpotReading {
  /// The part of the photo read for a tap: a third of its width and a
  /// quarter of its height around the spot, kept on the photo.
  public static func region(around x: Double, _ y: Double) -> NormalizedBox {
    centered(x, y, width: 0.34, height: 0.24)
  }

  /// A small box for a number added at a spot when nothing was read there.
  public static func marker(at x: Double, _ y: Double) -> NormalizedBox {
    centered(x, y, width: 0.06, height: 0.05)
  }

  /// Of the numbers read near a spot, the one to offer: a number whose box
  /// holds the spot, else the nearest. Numbers lying where the list already
  /// has one (half the smaller box overlapping) are left out, since those
  /// aren't missed.
  public static func nearest(
    _ numbers: [ReadNumber], to x: Double, _ y: Double, excluding taken: [NormalizedBox] = []
  ) -> ReadNumber? {
    let fresh = numbers.filter { number in !taken.contains { $0.overlap(with: number.box) > 0.5 } }
    return fresh.min { distance($0.box, x, y) < distance($1.box, x, y) }
  }

  /// How far a spot is from a box: 0 inside it.
  static func distance(_ box: NormalizedBox, _ x: Double, _ y: Double) -> Double {
    let dx = max(box.x - x, 0, x - box.maxX)
    let dy = max(box.y - y, 0, y - box.maxY)
    return (dx * dx + dy * dy).squareRoot()
  }

  static func centered(_ x: Double, _ y: Double, width: Double, height: Double) -> NormalizedBox {
    let left = min(max(x - width / 2, 0), 1 - width)
    let top = min(max(y - height / 2, 0), 1 - height)
    return NormalizedBox(x: left, y: top, width: width, height: height)
  }
}

#if canImport(Vision)
import CoreGraphics

extension SpotReading {
  /// The number nearest `x`, `y` (0...1 on the photo), read from the part
  /// of `image` around it. Nil when nothing new is there.
  public static func number(
    near x: Double, _ y: Double, in image: CGImage, excluding taken: [NormalizedBox] = [],
    recognition: RecognitionOptions = .photo
  ) async throws -> ReadNumber? {
    let lines = try await TextRecognizer(options: recognition).lines(in: image, region: region(around: x, y))
    return nearest(NumberExtractor().numbers(in: lines), to: x, y, excluding: taken)
  }
}
#endif
