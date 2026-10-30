import Foundation

// The equation checker: parses a way's text, says whether it is true, and
// lists the numbers it uses. A port of the server's `src/domain/equation.ts`
// (jthingelstad/roadsignmath.xyz); both are tested against
// `contracts/equation-vectors.json`, so change them together.
//
// Grammar (lowest binding first):
//   equation := expr ('=' expr)+
//   expr     := term (('+' | '−') term)*
//   term     := unary (('×' | '÷') unary)*
//   unary    := '−' unary | power
//   power    := root ('^' unary)?          right-associative
//   root     := '√' root | postfix         √ applies to what follows: √4! is √(4!)
//   postfix  := primary '!'*
//   primary  := number | '(' expr ')'
// ASCII stand-ins are accepted (- * x / sqrt) and come back in canonical form.

/// One piece of a side of an equation, as the checker parses it.
public indirect enum MathNode: Sendable, Hashable {
  /// A number as written, normalized: "07" is "7", ".5" is "0.5".
  case number(String)
  case binary(MathOperator, MathNode, MathNode)
  case negate(MathNode)
  case squareRoot(MathNode)
  case factorial(MathNode)
  /// Brackets as the player wrote them.
  case group(MathNode)
}

public enum MathOperator: String, Sendable, Hashable, CaseIterable {
  case add = "+"
  case subtract = "−"
  case multiply = "×"
  case divide = "÷"
  case power = "^"
}

/// Why a way isn't true, with the server's codes.
public enum EquationError: String, Sendable, Hashable, CaseIterable, Error {
  case empty
  case parse
  case noEquals = "no-equals"
  case divideByZero = "divide-by-zero"
  case notReal = "not-real"
  case tooBig = "too-big"
  case notTrue = "not-true"
}

/// The checker's answer for a way's text.
public enum EquationCheck: Sendable, Hashable {
  case solved(SolvedEquation)
  case failed(EquationFailure)

  public var isTrue: Bool {
    if case .solved = self { return true }
    return false
  }
}

public struct SolvedEquation: Sendable, Hashable {
  /// Unicode operators, spaces around + − × ÷ =, none around ^ √ !.
  public var canonical: String
  /// Two or more sides.
  public var sides: [MathNode]
  /// What every side equals: "2", "-3", "0.75", "1/3", or "≈1.41421" when
  /// every side is irrational.
  public var value: String
  /// Every number literal, in reading order.
  public var numbers: [String]
}

public struct EquationFailure: Sendable, Hashable {
  public var error: EquationError
  /// For the player: what to fix.
  public var message: String
  /// Present once the text parses.
  public var canonical: String?
  public var numbers: [String]?
  /// Each side's value, when the math isn't true.
  public var values: [String]?
}

public enum EquationChecker {
  static let maxLength = 400
  static let maxBits = 4096

  /// The longest text `parse` takes. A way is at most 400 characters, but
  /// its canonical text can be longer: "1+1" comes back as "1 + 1", and no
  /// one-character operator grows past three. So three times the way's
  /// limit parses the canonical text of every way `check` accepts, and
  /// still bounds the recursion well inside the 16 MB stack below.
  static let parseLength = 3 * maxLength

  /// The sides of a way, or nil when the text doesn't parse. What the app
  /// draws from. Text longer than any way's canonical text can be is nil
  /// too: the parser recurses once a bracket, and no stack is deep enough
  /// for any length at all.
  public static func parse(_ text: String) -> [MathNode]? {
    if text.utf16.count > parseLength { return nil }
    if text.utf16.count > inlineLength { return onLargeStack { parseHere(text) } }
    return parseHere(text)
  }

  static func parseHere(_ text: String) -> [MathNode]? {
    guard let tokens = try? tokenize(text) else { return nil }
    var parser = Parser(tokens: tokens)
    return try? parser.equation()
  }

  public static func check(_ text: String) -> EquationCheck {
    if text.utf16.count > inlineLength && text.utf16.count <= maxLength { return onLargeStack { checkHere(text) } }
    return checkHere(text)
  }

  private static func checkHere(_ text: String) -> EquationCheck {
    if trimmed(text).isEmpty { return .failed(EquationFailure(error: .empty, message: "Write some math first")) }
    if text.utf16.count > maxLength {
      return .failed(EquationFailure(error: .tooBig, message: "That math is too long to check"))
    }
    let sides: [MathNode]
    do throws(ParseError) {
      var parser = Parser(tokens: try tokenize(text))
      sides = try parser.equation()
    } catch {
      return .failed(EquationFailure(error: .parse, message: error.message))
    }
    let canonical = sides.map(format).joined(separator: " = ")
    let numbers = sides.flatMap(numbersIn)
    if sides.count < 2 {
      return .failed(EquationFailure(error: .noEquals, message: "Add an = so there are two sides",
                                     canonical: canonical, numbers: numbers))
    }
    var values: [Value] = []
    do throws(MathError) {
      for side in sides { values.append(try evaluate(side)) }
    } catch {
      return .failed(EquationFailure(error: error.code, message: error.message, canonical: canonical, numbers: numbers))
    }
    let texts = values.map(valueText)
    if !values.allSatisfy({ equal($0, values[0]) }) {
      return .failed(EquationFailure(error: .notTrue,
                                     message: "Not true yet: the sides are \(texts.joined(separator: " and "))",
                                     canonical: canonical, numbers: numbers, values: texts))
    }
    let value = texts.first { !$0.hasPrefix("≈") } ?? texts[0]
    return .solved(SolvedEquation(canonical: canonical, sides: sides, value: value, numbers: numbers))
  }

  /// The parser and the evaluator recurse once for each bracket, √ or −. A
  /// Debug build's frames are big enough that about 100 deep overflows a
  /// secondary thread's 512 KB stack (an optimized build manages all 400).
  /// So text longer than this is parsed on a thread of its own with room
  /// to spare; shorter text, nearly every way anyone writes, runs where it
  /// is called.
  static let inlineLength = 64

  static func onLargeStack<T: Sendable>(_ work: @escaping @Sendable () -> T) -> T {
    let box = ResultBox<T>()
    let done = DispatchSemaphore(value: 0)
    let thread = Thread {
      box.value = work()
      done.signal()
    }
    thread.stackSize = 16 << 20
    thread.start()
    done.wait()
    return box.value!
  }

  /// The light check's second half: every number in the math must be one of
  /// the sign's numbers, each used no more often than the sign shows it.
  /// Returns the numbers that don't match.
  public static func numbersNotOnSign(used: [String], onSign: [String]) -> [String] {
    var left: [String: Int] = [:]
    for n in onSign { left[normalizeNumber(n), default: 0] += 1 }
    var missing: [String] = []
    for n in used {
      let key = normalizeNumber(n)
      let count = left[key] ?? 0
      if count > 0 {
        left[key] = count - 1
      } else {
        missing.append(n)
      }
    }
    return missing
  }

  /// "07" → "7", ".5" → "0.5", "2.50" → "2.5", so sign numbers compare by value.
  public static func normalizeNumber(_ text: String) -> String {
    let parts = trimmed(text).split(separator: ".", omittingEmptySubsequences: false)
    var whole = Array(parts[0].unicodeScalars)
    var fraction = parts.count > 1 ? Array(parts[1].unicodeScalars) : []
    // /^0+(?=\d)/: the longest run of leading zeros that a digit follows.
    let zeros = whole.prefix { $0 == "0" }.count
    var k = zeros
    while k > 0 {
      if k < whole.count && isDigit(whole[k]) {
        whole.removeFirst(k)
        break
      }
      k -= 1
    }
    while fraction.last == "0" { fraction.removeLast() }
    let wholeText = whole.isEmpty ? "0" : String(String.UnicodeScalarView(whole))
    return fraction.isEmpty ? wholeText : wholeText + "." + String(String.UnicodeScalarView(fraction))
  }

  /// Canonical text: Unicode operators, spaces around + − × ÷ =, none around ^ √ !.
  public static func format(_ node: MathNode) -> String {
    switch node {
    case .number(let text): text
    case .group(let arg): "(\(format(arg)))"
    case .negate(let arg): "−\(format(arg))"
    case .squareRoot(let arg): "√\(format(arg))"
    case .factorial(let arg): "\(format(arg))!"
    case .binary(.power, let left, let right): "\(format(left))^\(format(right))"
    case .binary(let op, let left, let right): "\(format(left)) \(op.rawValue) \(format(right))"
    }
  }

  /// Every number literal, in reading order. The 2 of a square root is not one.
  public static func numbersIn(_ node: MathNode) -> [String] {
    switch node {
    case .number(let text): [text]
    case .group(let arg), .negate(let arg), .squareRoot(let arg), .factorial(let arg): numbersIn(arg)
    case .binary(_, let left, let right): numbersIn(left) + numbersIn(right)
    }
  }
}

/// Carries a result off the parsing thread; written once, before the
/// semaphore is signalled, and read once after.
private final class ResultBox<T>: @unchecked Sendable {
  var value: T?
}

// MARK: - Tokens

private enum Token: Equatable {
  case number(String)
  case op(Character)

  var text: String {
    switch self {
    case .number(let text): text
    case .op(let c): String(c)
    }
  }
}

struct ParseError: Error {
  let message: String
}

private let operators: [Unicode.Scalar: Character] = [
  "+": "+",
  "-": "−",
  "−": "−",
  "–": "−",
  "*": "×",
  "×": "×",
  "·": "×",
  "x": "×",
  "/": "÷",
  "÷": "÷",
  "^": "^",
  "√": "√",
  "!": "!",
  "(": "(",
  ")": ")",
  "=": "=",
]

/// JavaScript's `\s`, which `trim()` also strips.
private func isSpace(_ c: Unicode.Scalar) -> Bool {
  switch c.value {
  case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
  default: false
  }
}

private func isDigit(_ c: Unicode.Scalar) -> Bool { ("0"..."9").contains(c) }

private func trimmed(_ text: String) -> String {
  let scalars = Array(text.unicodeScalars)
  guard let first = scalars.firstIndex(where: { !isSpace($0) }),
        let last = scalars.lastIndex(where: { !isSpace($0) }) else { return "" }
  return String(String.UnicodeScalarView(scalars[first...last]))
}

private func tokenize(_ input: String) throws(ParseError) -> [Token] {
  let s = Array(input.unicodeScalars)
  var tokens: [Token] = []
  var i = 0
  while i < s.count {
    let c = s[i]
    if isSpace(c) {
      i += 1
      continue
    }
    if isDigit(c) || c == "." {
      // /^(?:\d+(?:\.\d+)?|\.\d+)/
      var j = i
      while j < s.count && isDigit(s[j]) { j += 1 }
      if j == i {
        guard j + 1 < s.count, isDigit(s[j + 1]) else { throw ParseError(message: "“\(c)” is not a number") }
      }
      if j < s.count && s[j] == "." && j + 1 < s.count && isDigit(s[j + 1]) {
        j += 1
        while j < s.count && isDigit(s[j]) { j += 1 }
      }
      let text = String(String.UnicodeScalarView(s[i..<j]))
      tokens.append(.number(EquationChecker.normalizeNumber(text)))
      i = j
      continue
    }
    if c == "s" && i + 3 < s.count && s[i + 1] == "q" && s[i + 2] == "r" && s[i + 3] == "t" {
      tokens.append(.op("√"))
      i += 4
      continue
    }
    guard let op = operators[c] else { throw ParseError(message: "“\(c)” isn’t something the checker knows") }
    tokens.append(.op(op))
    i += 1
  }
  return tokens
}

// MARK: - Parser

private struct Parser {
  let tokens: [Token]
  var i = 0

  init(tokens: [Token]) { self.tokens = tokens }

  mutating func equation() throws(ParseError) -> [MathNode] {
    var sides = [try expr()]
    while peek("=") {
      i += 1
      sides.append(try expr())
    }
    if i < tokens.count { throw ParseError(message: "Unexpected “\(tokens[i].text)”") }
    return sides
  }

  private mutating func expr() throws(ParseError) -> MathNode {
    var left = try term()
    while peek("+") || peek("−") {
      let op: MathOperator = tokens[i] == .op("+") ? .add : .subtract
      i += 1
      left = .binary(op, left, try term())
    }
    return left
  }

  private mutating func term() throws(ParseError) -> MathNode {
    var left = try unary()
    while peek("×") || peek("÷") {
      let op: MathOperator = tokens[i] == .op("×") ? .multiply : .divide
      i += 1
      left = .binary(op, left, try unary())
    }
    return left
  }

  private mutating func unary() throws(ParseError) -> MathNode {
    if peek("−") {
      i += 1
      return .negate(try unary())
    }
    return try power()
  }

  private mutating func power() throws(ParseError) -> MathNode {
    let base = try root()
    if peek("^") {
      i += 1
      return .binary(.power, base, try unary())
    }
    return base
  }

  private mutating func root() throws(ParseError) -> MathNode {
    if peek("√") {
      i += 1
      return .squareRoot(try root())
    }
    return try postfix()
  }

  private mutating func postfix() throws(ParseError) -> MathNode {
    var node = try primary()
    while peek("!") {
      i += 1
      node = .factorial(node)
    }
    return node
  }

  private mutating func primary() throws(ParseError) -> MathNode {
    guard i < tokens.count else { throw ParseError(message: "The math ends too soon") }
    switch tokens[i] {
    case .number(let text):
      i += 1
      if i < tokens.count, case .number = tokens[i] { throw ParseError(message: "Put an operator after \(text)") }
      if peek("(") || peek("√") { throw ParseError(message: "Put an operator after \(text)") }
      return .number(text)
    case .op("("):
      i += 1
      let inner = try expr()
      if !peek(")") { throw ParseError(message: "A bracket is never closed") }
      i += 1
      return .group(inner)
    case let token:
      throw ParseError(message: "Unexpected “\(token.text)”")
    }
  }

  private func peek(_ op: Character) -> Bool { i < tokens.count && tokens[i] == .op(op) }
}

// MARK: - Values: exact rationals where possible, a float where a root is irrational.

private enum Value {
  /// n/d in lowest terms, d > 0.
  case exact(BigInt, BigInt)
  case approximate(Double)
}

private struct MathError: Error {
  let code: EquationError
  let message: String

  static let divideByZero = MathError(code: .divideByZero, message: "Something is divided by zero")
  static let tooBig = MathError(code: .tooBig, message: "The numbers get too big to check")
}

private func rational(_ n: BigInt, _ d: BigInt) throws(MathError) -> Value {
  if d.isZero { throw .divideByZero }
  var (n, d) = (n, d)
  if d.isNegative { (n, d) = (-n, -d) }
  var g = BigInt.gcd(n, d)
  if g.isZero { g = .one }
  n = n / g
  d = d / g
  if n.bitCount > EquationChecker.maxBits || d.bitCount > EquationChecker.maxBits { throw .tooBig }
  return .exact(n, d)
}

/// The nearest float. Huge rationals are scaled first so n/d doesn't become
/// ∞/∞; one beyond the float range is ±∞.
private func toFloat(_ v: Value) -> Double {
  switch v {
  case .approximate(let x):
    return x
  case .exact(var n, var d):
    let shift = min(n.bitCount, d.bitCount) - 1000
    if shift > 0 {
      n = n >> shift
      d = d >> shift
    }
    return n.doubleValue / d.doubleValue
  }
}

private func float(_ x: Double) throws(MathError) -> Value {
  if !x.isFinite { throw .tooBig }
  return .approximate(x)
}

private func parseNumber(_ text: String) throws(MathError) -> Value {
  let parts = text.split(separator: ".", omittingEmptySubsequences: false)
  let fraction = parts.count > 1 ? parts[1] : ""
  let n = BigInt(digits: parts[0] + fraction)!
  return try rational(n, BigInt(10).power(fraction.count))
}

/// Floor of √n by Newton's method, starting above the root so it only falls.
private func isqrt(_ n: BigInt) -> BigInt {
  if n < BigInt(2) { return n }
  var x = BigInt.one << ((n.bitCount + 1) / 2)
  while true {
    let y = (x + n / x) >> 1
    if !(y < x) { return x }
    x = y
  }
}

// The recursion stays in `evaluate`, which only dispatches; each case's work
// is in a function of its own, so a deep tree (400 characters of √ or
// brackets) keeps small frames even in a Debug build.
private func evaluate(_ node: MathNode) throws(MathError) -> Value {
  switch node {
  case .number(let text): return try parseNumber(text)
  case .group(let arg): return try evaluate(arg)
  case .negate(let arg): return try negate(evaluate(arg))
  case .squareRoot(let arg): return try squareRoot(evaluate(arg))
  case .factorial(let arg): return try factorial(evaluate(arg))
  case .binary(let op, let left, let right): return try combine(op, evaluate(left), evaluate(right))
  }
}

@inline(never)
private func negate(_ a: Value) throws(MathError) -> Value {
  switch a {
  case .exact(let n, let d): return try rational(-n, d)
  case .approximate(let x): return try float(-x)
  }
}

@inline(never)
private func combine(_ op: MathOperator, _ a: Value, _ b: Value) throws(MathError) -> Value {
  if op == .power { return try power(a, b) }
  if case .exact(let an, let ad) = a, case .exact(let bn, let bd) = b {
    switch op {
    case .add: return try rational(an * bd + bn * ad, ad * bd)
    case .subtract: return try rational(an * bd - bn * ad, ad * bd)
    case .multiply: return try rational(an * bn, ad * bd)
    default: return try rational(an * bd, ad * bn)
    }
  }
  let x = toFloat(a)
  let y = toFloat(b)
  if op == .divide && abs(y) < 1e-12 { throw .divideByZero }
  switch op {
  case .add: return try float(x + y)
  case .subtract: return try float(x - y)
  case .multiply: return try float(x * y)
  default: return try float(x / y)
  }
}

@inline(never)
private func power(_ a: Value, _ b: Value) throws(MathError) -> Value {
  if case .exact(let an, let ad) = a, case .exact(let bn, let bd) = b, bd == .one {
    let e = bn.magnitude
    if e * BigInt((an > ad ? an : ad).bitCount) > BigInt(EquationChecker.maxBits) { throw .tooBig }
    if an.isZero && bn.isNegative { throw .divideByZero }
    // e × bits ≤ 4096 and bits ≥ 1, so e fits an Int.
    let power = Int(e.description)!
    return bn.isNegative ? try rational(ad.power(power), an.power(power)) : try rational(an.power(power), ad.power(power))
  }
  let r = JSNumber.pow(toFloat(a), toFloat(b))
  if r.isNaN { throw MathError(code: .notReal, message: "That power has no real answer") }
  return try float(r)
}

@inline(never)
private func squareRoot(_ a: Value) throws(MathError) -> Value {
  let negative = switch a {
  case .exact(let n, _): n.isNegative
  case .approximate(let x): x < 0
  }
  if negative { throw MathError(code: .notReal, message: "There is no square root of a negative number") }
  if case .exact(let n, let d) = a {
    let rn = isqrt(n)
    let rd = isqrt(d)
    if rn * rn == n && rd * rd == d { return try rational(rn, rd) }
  }
  return try float(toFloat(a).squareRoot())
}

@inline(never)
private func factorial(_ a: Value) throws(MathError) -> Value {
  guard case .exact(let n, let d) = a, d == .one, !n.isNegative else {
    throw MathError(code: .notReal, message: "Factorials only work on whole numbers 0 and up")
  }
  if BigInt(200) < n { throw .tooBig }
  var r = BigInt.one
  var k = 2
  let last = Int(n.description)!
  while k <= last {
    r = r * BigInt(k)
    k += 1
  }
  return try rational(r, .one)
}

private func equal(_ a: Value, _ b: Value) -> Bool {
  if case .exact(let an, let ad) = a, case .exact(let bn, let bd) = b { return an == bn && ad == bd }
  let x = toFloat(a)
  let y = toFloat(b)
  // An exact side beyond the float range can't equal an approximate one, which is always finite.
  if !x.isFinite || !y.isFinite { return false }
  return abs(x - y) <= 1e-9 * max(1, abs(x), abs(y))
}

/// How a side's value reads to a person: "2", "-3", "0.75", "1/3", "≈1.41421".
private func valueText(_ v: Value) -> String {
  switch v {
  case .approximate(let x):
    return "≈" + JSNumber.roundedString(x, significantDigits: 6)
  case .exact(let n, let d):
    if d == .one { return n.description }
    var rest = d
    while (rest % BigInt(2)).isZero { rest = rest / BigInt(2) }
    while (rest % BigInt(5)).isZero { rest = rest / BigInt(5) }
    if rest == .one { return JSNumber.string(n.doubleValue / d.doubleValue) }
    return "\(n)/\(d)"
  }
}
