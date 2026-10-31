import CoreGraphics
import CoreText
import Foundation
import ImageIO
import SignReading

/// A made-up road sign, drawn rather than photographed: two exit signs on a
/// gantry against a sky. A Debug build in the simulator, which has no
/// camera, shoots it, and the tests read it, so no real photo (with its
/// plates and faces) ever enters the repo.
public enum SampleSign {
  /// A line of text on the sign, where it is drawn (0...1, origin top left)
  /// and the numbers in it.
  public struct Line: Sendable, Hashable {
    public var text: String
    public var x: Double
    public var y: Double
    public var size: Double
    public var numbers: [String]
  }

  /// Two signs, five numbers on the left and right together: 90 − 82 = 8,
  /// and 7 + 1 = 8.
  public static let lines: [Line] = [
    Line(text: "EXIT 8", x: 0.27, y: 0.20, size: 0.055, numbers: ["8"]),
    Line(text: "82nd St", x: 0.12, y: 0.34, size: 0.085, numbers: ["82"]),
    Line(text: "EXIT 7B", x: 0.69, y: 0.20, size: 0.055, numbers: ["7"]),
    Line(text: "90th St", x: 0.56, y: 0.34, size: 0.085, numbers: ["90"]),
    Line(text: "1 MILE", x: 0.62, y: 0.50, size: 0.06, numbers: ["1"]),
  ]

  /// The numbers drawn, in reading order.
  public static let numbers = ["8", "7", "82", "90", "1"]

  /// The sign at `width` by `height` pixels.
  public static func image(width: Int = 1600, height: Int = 1000) -> CGImage? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let w = Double(width)
    let h = Double(height)
    // CoreGraphics draws from the bottom left; the layout is from the top.
    func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CGRect {
      CGRect(x: x * w, y: h - (y + height) * h, width: width * w, height: height * h)
    }

    // A late-afternoon sky, the road below.
    let sky = CGGradient(
      colorsSpace: space,
      colors: [color(0x8DB8DE), color(0xDCE8F0)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(
      sky, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * 0.18), options: [.drawsAfterEndLocation])
    context.setFillColor(color(0x5E6763))
    context.fill(rect(0, 0.82, 1, 0.18))

    // The gantry and its two signs.
    context.setFillColor(color(0x8A9298))
    context.fill(rect(0.03, 0.08, 0.94, 0.03))
    context.fill(rect(0.04, 0.08, 0.025, 0.76))
    context.fill(rect(0.935, 0.08, 0.025, 0.76))
    for x in [0.08, 0.52] {
      let panel = rect(x, 0.13, 0.4, 0.48)
      context.setFillColor(color(0x006348))
      context.addPath(CGPath(roundedRect: panel, cornerWidth: 18, cornerHeight: 18, transform: nil))
      context.fillPath()
      context.setStrokeColor(color(0xFFFFFF))
      context.setLineWidth(6)
      let border = panel.insetBy(dx: 10, dy: 10)
      context.addPath(CGPath(roundedRect: border, cornerWidth: 12, cornerHeight: 12, transform: nil))
      context.strokePath()
    }

    for line in lines {
      draw(line.text, at: line.x, line.y, size: line.size * h, in: context, height: h, width: w)
    }
    return context.makeImage()
  }

  /// The sign as a JPEG file, with a day and a place in its metadata, as a
  /// photo from the library would have.
  public static func photo() -> PhotoFile? {
    guard let image = image() else { return nil }
    let properties: [CFString: Any] = [
      kCGImagePropertyExifDictionary: [
        kCGImagePropertyExifDateTimeOriginal: "2025:09:01 17:42:00",
        kCGImagePropertyExifOffsetTimeOriginal: "-05:00",
      ] as [CFString: Any],
      kCGImagePropertyGPSDictionary: [
        kCGImagePropertyGPSLatitude: 44.857, kCGImagePropertyGPSLatitudeRef: "N",
        kCGImagePropertyGPSLongitude: 93.29, kCGImagePropertyGPSLongitudeRef: "W",
      ] as [CFString: Any],
    ]
    return PhotoFile.jpeg(image, properties: properties).flatMap(PhotoFile.init(data:))
  }

  private static func draw(
    _ text: String, at x: Double, _ y: Double, size: Double, in context: CGContext, height: Double, width: Double
  ) {
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    let attributes: [CFString: Any] = [
      kCTFontAttributeName: font,
      kCTForegroundColorAttributeName: color(0xFFFFFF),
    ]
    let string = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
    let line = CTLineCreateWithAttributedString(string)
    var ascent: CGFloat = 0
    CTLineGetTypographicBounds(line, &ascent, nil, nil)
    context.textPosition = CGPoint(x: x * width, y: height - y * height - ascent)
    CTLineDraw(line, context)
  }

  private static func color(_ rgb: UInt32) -> CGColor {
    CGColor(
      srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
      blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
  }
}
