extension EquationChecker {
  /// LaTeX for the math, byte for byte as the server's `tex()` writes it
  /// (the `tex` the API sends): ÷ is a stacked fraction, √ a radical over
  /// what it applies to, ^ a raised exponent. Brackets the fraction bar,
  /// radical or exponent already shows are dropped; every other bracket
  /// stays as written. The app draws the math from this LaTeX, as the
  /// website does, so a sign's math looks the same in both.
  public static func tex(_ node: MathNode) -> String {
    switch node {
    case .number(let text): text
    case .group(let arg): "\\left(\(tex(arg))\\right)"
    case .negate(let arg): "-\(tex(arg))"
    case .squareRoot(let arg): "\\sqrt{\(tex(arg.bare))}"
    case .factorial(let arg): "\(tex(arg))!"
    case .binary(.power, let left, let right): "{\(tex(left))}^{\(tex(right.bare))}"
    case .binary(.divide, let left, let right): "\\frac{\(tex(left.bare))}{\(tex(right.bare))}"
    case .binary(.add, let left, let right): "\(tex(left)) + \(tex(right))"
    case .binary(.subtract, let left, let right): "\(tex(left)) - \(tex(right))"
    case .binary(.multiply, let left, let right): "\(tex(left)) \\times \(tex(right))"
    }
  }

  /// The LaTeX for a way's text, or nil when it doesn't parse. Writing it
  /// recurses as deep as parsing does, so long text is parsed and written
  /// together on the parser's large stack. (`tex(_:)` on a node runs where
  /// it is called; use this for text of any length.)
  public static func tex(of text: String) -> String? {
    if text.utf16.count > parseLength { return nil }
    if text.utf16.count > inlineLength { return onLargeStack { texHere(text) } }
    return texHere(text)
  }

  private static func texHere(_ text: String) -> String? {
    parseHere(text).map { $0.map(tex).joined(separator: " = ") }
  }
}

extension MathNode {
  /// What a fraction, root or exponent already groups needs no brackets of
  /// its own: the node inside any brackets around it.
  public var bare: MathNode {
    if case .group(let inner) = self { return inner.bare }
    return self
  }
}
