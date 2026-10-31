import CoreText
import SwiftUI

// Road Sign Math's look, from the Design boards: a guide sign's green and
// white on a pale road-map ground, Overpass for words (the face highway
// signs grew from) and Latin Modern for the math. Light then dark; the
// sign plate stays green and white in both, as a real sign does.

extension Color {
  /// The sign's green: the plate, the pins, actions.
  static let signGreen = Color(light: 0x006348, dark: 0x006348)
  /// Green as words and icons on the ground, lighter in the dark.
  static let greenInk = Color(light: 0x006348, dark: 0x5CC29A)
  static let ground = Color(light: 0xF3F5F2, dark: 0x0E1310)
  static let card = Color(light: 0xFFFFFF, dark: 0x181F1B)
  static let ink = Color(light: 0x18201C, dark: 0xE9EEEA)
  static let ink2 = Color(light: 0x3B4540, dark: 0xBAC4BE)
  static let ink3 = Color(light: 0x55605A, dark: 0x8E9993)
  static let rule = Color(light: 0xD8DED9, dark: 0x2A332E)
  static let ruleStrong = Color(light: 0xB9C3BB, dark: 0x3A453F)
  /// Warnings and the way out: sign out, delete, a wrong code.
  static let warn = Color(light: 0xB01C33, dark: 0xFF8A98)
  /// A heart, as the website draws it (`--heart`, `--heart-soft`).
  static let heart = Color(light: 0xB01C33, dark: 0xE0566B)
  static let heartSoft = Color(light: 0xFBE9EC, dark: 0x3A1D23)
  /// Behind the ways found so far.
  static let wayGround = Color(light: 0xE3EFE9, dark: 0x15291F)
  static let wayInk = Color(light: 0x1F3A2E, dark: 0xCDE8DA)
  /// A selected pin's ring.
  static let signYellow = Color(light: 0xF2B300, dark: 0xF2B300)
  static let photoGround = Color(light: 0xDDE3DD, dark: 0x222A25)

  init(light: UInt32, dark: UInt32) {
    self.init(uiColor: UIColor { UIColor(rgb: $0.userInterfaceStyle == .dark ? dark : light) })
  }

  /// "#006348", as the API sends a player's colour.
  init?(hex: String) {
    guard hex.hasPrefix("#"), hex.count == 7, let rgb = UInt32(hex.dropFirst(), radix: 16) else { return nil }
    self.init(uiColor: UIColor(rgb: rgb))
  }
}

extension UIColor {
  convenience init(rgb: UInt32, alpha: CGFloat = 1) {
    self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
              blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
  }
}

/// Overpass and Overpass Mono, bundled (OFL, Fonts/) and named in
/// Info.plist's UIAppFonts. Each is one variable font, so the weight is
/// set on its axis.
struct Face {
  enum Family { case overpass, mono }

  var family: Family = .overpass
  var size: CGFloat
  var weight: CGFloat
  var style: Font.TextStyle
  /// Letter spacing in ems.
  var tracking: CGFloat = 0

  static let brand = Face(size: 21, weight: 900, style: .title3, tracking: -0.01)
  static let screenTitle = Face(size: 18, weight: 900, style: .headline)
  static let title = Face(size: 24, weight: 900, style: .title2, tracking: -0.01)
  static let section = Face(size: 17, weight: 900, style: .headline)
  static let name = Face(size: 15, weight: 800, style: .subheadline)
  static let nameLarge = Face(size: 16, weight: 800, style: .body)
  static let meta = Face(size: 13, weight: 400, style: .footnote)
  static let metaBold = Face(size: 13, weight: 700, style: .footnote)
  static let body = Face(size: 15, weight: 400, style: .body)
  static let bodyBold = Face(size: 15, weight: 800, style: .body)
  static let pill = Face(size: 14, weight: 800, style: .subheadline)
  static let action = Face(size: 15, weight: 800, style: .body)
  static let plateText = Face(size: 18, weight: 800, style: .body)
  static let avatar = Face(size: 15, weight: 900, style: .subheadline)
  static let number = Face(family: .mono, size: 16, weight: 700, style: .body)
  static let miles = Face(family: .mono, size: 13, weight: 700, style: .footnote)
  static let tab = Face(size: 11, weight: 700, style: .caption2)
  static let tabOn = Face(size: 11, weight: 800, style: .caption2)
  static let search = Face(size: 16, weight: 400, style: .body)
  /// The sign-in screens' big words.
  static let hero = Face(size: 34, weight: 900, style: .largeTitle, tracking: -0.02)
  static let display = Face(size: 30, weight: 900, style: .largeTitle, tracking: -0.02)
  static let lead = Face(size: 17, weight: 400, style: .body)
  static let field = Face(size: 17, weight: 400, style: .body)
  static let label = Face(size: 15, weight: 800, style: .subheadline)
  static let button = Face(size: 17, weight: 800, style: .body)
  static let guideSign = Face(size: 24, weight: 800, style: .title2)
  static let digit = Face(family: .mono, size: 26, weight: 700, style: .title2)

  func font(size: CGFloat) -> Font {
    let axes: [NSNumber: NSNumber] = [NSNumber(value: Self.wght): NSNumber(value: Double(weight))]
    let name = family == .overpass ? "Overpass-Regular" : "OverpassMono-Regular"
    let attributes: [CFString: Any] = [kCTFontNameAttribute: name, kCTFontVariationAttribute: axes]
    return Font(CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(attributes as CFDictionary), size, nil))
  }

  /// The 'wght' axis, as CoreText names it.
  private static let wght: UInt32 = 0x7767_6874
}

/// A face at the size Dynamic Type asks for.
private struct FaceModifier: ViewModifier {
  let face: Face
  @ScaledMetric private var size: CGFloat

  init(_ face: Face) {
    self.face = face
    _size = ScaledMetric(wrappedValue: face.size, relativeTo: face.style)
  }

  func body(content: Content) -> some View {
    content.font(face.font(size: size)).tracking(face.tracking * size)
  }
}

extension View {
  func face(_ face: Face) -> some View { modifier(FaceModifier(face)) }
}

extension String {
  /// " ∙ " between bits of a line. Overpass's own middle dot (U+00B7) has a
  /// contextual form, for Catalan's l·l, that sets it tight against what
  /// follows; the bullet operator is the same dot without it.
  static let dot = " \u{2219} "
}
