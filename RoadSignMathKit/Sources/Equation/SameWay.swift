import Foundation

// The same-way rule, a port of `sameWayKey` in the server's
// `src/domain/equation.ts` (Jamie, 2026-11-11: a reordered way earns
// nothing). Tested against the vectors' `same_way` pairs.

extension EquationChecker {
  /// What a way says, with its order taken out: two ways with the same key
  /// are the same way. Terms added or taken away are sorted, each keeping
  /// its own sign, and so are factors multiplied or divided, each keeping
  /// whether it divides; the same inside every root, power and bracket.
  /// Brackets in a + or × place do nothing and go; those after a − or ÷
  /// stay whole, since 7 − (4 − 1) isn't 7 − 4 + 1. The sides are sorted
  /// too, so 7 = 3 + 4 is 3 + 4 = 7. Sorted by UTF-16 code units, as
  /// JavaScript sorts, so the key is the server's, character for character.
  /// Nil when the text doesn't parse.
  public static func sameWayKey(_ text: String) -> String? {
    guard let sides = parse(text) else { return nil }
    if text.utf16.count > inlineLength { return onLargeStack { sideKeys(sides) } }
    return sideKeys(sides)
  }

  /// Whether `text` is the same way as one of `ways`, by the rule above.
  public static func isSameWay(_ text: String, asAnyOf ways: [String]) -> Bool {
    guard let key = sameWayKey(text) else { return false }
    return ways.contains { sameWayKey($0) == key }
  }

  private static func sideKeys(_ sides: [MathNode]) -> String {
    jsSorted(sides.map(wayKey)).joined(separator: " = ")
  }

  private static func wayKey(_ node: MathNode) -> String {
    switch node {
    case .number(let text): text
    case .group(let arg): wayKey(arg)
    case .negate(let arg): "−(\(wayKey(arg)))"
    case .squareRoot(let arg): "√(\(wayKey(arg)))"
    case .factorial(let arg): "!(\(wayKey(arg)))"
    case .binary(.power, let left, let right): "^(\(wayKey(left)),\(wayKey(right)))"
    case .binary(.add, _, _), .binary(.subtract, _, _): chain("+", sumTerms(node))
    case .binary(.multiply, _, _), .binary(.divide, _, _): chain("×", productFactors(node))
    }
  }

  private static func unwrap(_ node: MathNode) -> MathNode {
    if case .group(let arg) = node { return unwrap(arg) }
    return node
  }

  /// The terms of a chain of + and −, each with its sign. A bracket in a + place opens up.
  private static func sumTerms(_ node: MathNode) -> [String] {
    switch unwrap(node) {
    case .binary(.add, let left, let right): sumTerms(left) + sumTerms(right)
    case .binary(.subtract, let left, let right): sumTerms(left) + ["−" + wayKey(right)]
    case let other: ["+" + wayKey(other)]
    }
  }

  /// The factors of a chain of × and ÷, each saying whether it divides. A bracket in a × place opens up.
  private static func productFactors(_ node: MathNode) -> [String] {
    switch unwrap(node) {
    case .binary(.multiply, let left, let right): productFactors(left) + productFactors(right)
    case .binary(.divide, let left, let right): productFactors(left) + ["÷" + wayKey(right)]
    case let other: ["×" + wayKey(other)]
    }
  }

  private static func chain(_ kind: String, _ items: [String]) -> String {
    "\(kind)(\(jsSorted(items).joined(separator: ",")))"
  }

  private static func jsSorted(_ items: [String]) -> [String] {
    items.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
  }
}
