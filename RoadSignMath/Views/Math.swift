import MathArt
import SwiftUI

/// A way's math as TeX sets it: drawn by MathArt from the LaTeX the API
/// sent (or written here from the text), as large as `size` allows and
/// smaller when the line is long, never cut off. VoiceOver reads the plain
/// text, which it speaks well ("square root", "divided by"). If the LaTeX
/// doesn't typeset, the text is shown as written.
struct MathLine: View {
  let text: String
  let tex: String?
  var size: CGFloat = 20
  /// The ink, as 0xRRGGBB for light and dark.
  var light: UInt32 = 0xFFFFFF
  var dark: UInt32 = 0xFFFFFF
  var fallback: Face = .plateText
  /// Set from the left, as in a list, rather than centred on a plate.
  var leading = false

  @Environment(\.colorScheme) private var scheme
  @ScaledMetric private var scaled: CGFloat
  @State private var width: CGFloat = 0

  init(text: String, tex: String?, size: CGFloat = 20, relativeTo: Font.TextStyle = .body,
       light: UInt32 = 0xFFFFFF, dark: UInt32 = 0xFFFFFF, fallback: Face = .plateText, leading: Bool = false) {
    self.text = text
    self.tex = MathArt.tex(for: text, sent: tex)
    self.size = size
    self.light = light
    self.dark = dark
    self.fallback = fallback
    self.leading = leading
    _scaled = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
  }

  var body: some View {
    Group {
      if let picture {
        // Drawn at the size that fits the width it's given. It never asks
        // for more width than that: if even the smallest size is too wide,
        // the picture scales down rather than widening the card or being
        // cut off.
        Image(uiImage: picture)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
          .frame(maxWidth: picture.size.width, maxHeight: picture.size.height)
      } else {
        Text(text)
          .face(fallback)
          .foregroundStyle(Color(uiColor: UIColor(rgb: ink)))
          .multilineTextAlignment(leading ? .leading : .center)
      }
    }
    .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    .accessibilityElement()
    .accessibilityLabel(spoken)
  }

  private var ink: UInt32 { scheme == .dark ? dark : light }

  private var picture: UIImage? {
    guard let tex else { return nil }
    let fit = width > 0 ? MathArt.fittingSize(tex: tex, preferred: scaled, width: width) : scaled
    return MathArt.picture(tex: tex, fontSize: fit, color: ink)
  }

  /// The text as VoiceOver should say it: "√(5 − 1) = 2" reads as
  /// "square root of (5 minus 1) equals 2".
  private var spoken: String { Self.spoken(text) }

  /// Math as VoiceOver should say it, as typed ("5-1") or as shown ("5 − 1").
  static func spoken(_ text: String) -> String {
    text.replacingOccurrences(of: "√", with: " square root of ")
      .replacingOccurrences(of: "sqrt", with: " square root of ")
      .replacingOccurrences(of: "−", with: " minus ")
      .replacingOccurrences(of: "-", with: " minus ")
      .replacingOccurrences(of: "×", with: " times ")
      .replacingOccurrences(of: "*", with: " times ")
      .replacingOccurrences(of: "÷", with: " divided by ")
      .replacingOccurrences(of: "/", with: " divided by ")
      .replacingOccurrences(of: "=", with: " equals ")
      .replacingOccurrences(of: "^", with: " to the power of ")
      .replacingOccurrences(of: "!", with: " factorial ")
      .split(separator: " ").joined(separator: " ")
  }
}

/// The math on a guide sign: white on the sign's green, inside a white
/// border, as the Design boards set it.
struct SignPlate: View {
  let text: String
  let tex: String?
  var size: CGFloat = 20
  var large = false

  var body: some View {
    MathLine(text: text, tex: tex, size: size)
      .padding(.horizontal, 12)
      .padding(.vertical, large ? 14 : 10)
      .frame(maxWidth: .infinity)
      .overlay {
        RoundedRectangle(cornerRadius: large ? 10 : 9, style: .continuous)
          .strokeBorder(.white, lineWidth: large ? 2.5 : 2)
      }
      .padding(4)
      .background(Color.signGreen, in: RoundedRectangle(cornerRadius: large ? 14 : 12, style: .continuous))
  }
}

#Preview {
  VStack(spacing: 12) {
    SignPlate(text: "(90 − 82) ÷ 8 × 1 × 2 = 6 ÷ (10 − 7)", tex: nil)
    SignPlate(text: "√(83 − √4) = 6 + 3", tex: nil, size: 24, large: true)
    SignPlate(text: "(35 ÷ 7 × 10 + 12) − 62 + 6 + 3 + 2 = 11", tex: nil)
  }
  .padding()
}
