import CoreGraphics
import Equation
import Foundation
import SwiftMath

#if canImport(UIKit)
  import UIKit
  public typealias MathPicture = UIImage
#else
  import AppKit
  public typealias MathPicture = NSImage
#endif

/// The math drawn as TeX draws it: the LaTeX `EquationChecker.tex` writes
/// (the same the API sends and the website draws), typeset by SwiftMath in
/// Latin Modern, the face of TeX itself.
///
/// Typesetting is quick but not free, and a feed draws the same few
/// equations over and over as it scrolls, so every picture is kept by its
/// LaTeX, size and colour. SwiftMath keeps its fonts in shared state, so
/// all of it happens on the main actor.
@MainActor
public enum MathArt {
  /// The math at `fontSize` points in `color` (0xRRGGBB), or nil when the
  /// LaTeX doesn't typeset (the caller shows the plain text instead).
  public static func picture(tex: String, fontSize: CGFloat, color: UInt32) -> MathPicture? {
    let size = (fontSize * 2).rounded() / 2
    let key = "\(size)|\(color)|\(tex)" as NSString
    if let kept = pictures.object(forKey: key) { return kept }
    var image = MathImage(latex: tex, fontSize: size, textColor: MTColor(rgb: color), labelMode: .display, textAlignment: .center)
    let (error, picture, _) = image.asImage()
    guard error == nil, let picture, picture.size.width > 0 else { return nil }
    pictures.setObject(picture, forKey: key)
    return picture
  }

  /// The largest size, up to `preferred`, at which the math fits in
  /// `width` points: a long equation gets smaller rather than cut off.
  /// TeX's layout scales with the font, so one measurement is enough.
  public static func fittingSize(tex: String, preferred: CGFloat, width: CGFloat, smallest: CGFloat = 11) -> CGFloat {
    guard width > 0, let natural = picture(tex: tex, fontSize: preferred, color: 0xFFFFFF)?.size.width, natural > width
    else { return preferred }
    return max(smallest, (preferred * width / natural * 2).rounded(.down) / 2)
  }

  /// Whether SwiftMath reads this LaTeX.
  public static func typesets(_ tex: String) -> Bool {
    var error: NSError?
    return MTMathListBuilder.build(fromString: tex, error: &error) != nil && error == nil
  }

  /// The LaTeX for a way: the API's when it sent one, else written here from
  /// the plain text, else nil (draw the text).
  public nonisolated static func tex(for text: String, sent: String?) -> String? {
    sent ?? EquationChecker.tex(of: text)
  }

  private static let pictures: NSCache<NSString, MathPicture> = {
    let cache = NSCache<NSString, MathPicture>()
    cache.countLimit = 400
    return cache
  }()
}

extension MTColor {
  fileprivate convenience init(rgb: UInt32) {
    self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
              blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
  }
}
