import CoreGraphics

/// Resizing photos with CoreGraphics, on the phone and the Mac alike.
public enum ImageScaling {
  /// `image` drawn at `factor` times its size with high-quality
  /// interpolation, in sRGB. Nil if the drawing can't be made.
  public static func scaled(_ image: CGImage, by factor: Double) -> CGImage? {
    let width = Int((Double(image.width) * factor).rounded())
    let height = Int((Double(image.height) * factor).rounded())
    return resized(image, width: width, height: height)
  }

  /// `image` drawn at `width` by `height` pixels.
  public static func resized(_ image: CGImage, width: Int, height: Int) -> CGImage? {
    guard width > 0, height > 0,
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }
}
