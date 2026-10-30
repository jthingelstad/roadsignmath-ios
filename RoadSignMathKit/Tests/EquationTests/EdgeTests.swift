import Foundation
import Testing

@testable import Equation

/// Edges past the shared vectors, each answer taken from the server's
/// checker (`check()` in src/domain/equation.ts) on 2026-10-30. Most are
/// about how a value reads, which comes from JavaScript's number printing.
@Suite struct EdgeTests {
  /// (text, error or nil for true, the value or the sides' values)
  @Test(arguments: [
    ("2^0.5 = √2", nil, ["≈1.41421"]),
    ("4^0.5 = 2", nil, ["2"]),
    ("1234565^2^0.5 = 1", "not-true", ["≈411815000", "1"]),
    // An exact tie at six digits rounds up, as toPrecision does.
    ("(1234565^2)^(1÷2) = 1", "not-true", ["≈1234570", "1"]),
    ("1^(10^400 ÷ 3) = 1", "not-real", []),
    ("2^(10^400÷3)=1", "too-big", []),
    ("(10^400+1) ÷ 2 = 1", "not-true", ["Infinity", "1"]),
    ("(10^300+1)÷2 = 5", "not-true", ["5e+299", "5"]),
    ("0.1^400 = 0", "not-true", ["0", "0"]),
    ("√0.25 = 0.5", nil, ["0.5"]),
    ("√(1÷3) = 1", "not-true", ["≈0.57735", "1"]),
    ("√2 ÷ 0.0000000000001 = 1", "divide-by-zero", []),
    ("0^0 = 1", nil, ["1"]),
    ("0^−1 = 1", "divide-by-zero", []),
    ("(−8)^(1÷3) = −2", "not-real", []),
    ("2^−3 = 0.125", nil, ["0.125"]),
    ("√√√√√√16 = 1", "not-true", ["≈1.04427", "1"]),
    ("3!!=720", nil, ["720"]),
    ("201! = 1", "too-big", []),
    ("(−1)! = 1", "not-real", []),
    ("  ", "empty", []),
    ("\u{00A0}2=2\u{FEFF}", nil, ["2"]),
    ("2\u{0085}=2", "parse", []),
    ("１ = 1", "parse", []),
    ("1. = 1", "parse", []),
    ("1.2.3 = 1", "parse", []),
    ("(((((2))))) = 2", nil, ["2"]),
    ("√2 = 1.41421", "not-true", ["≈1.41421", "1.41421"]),
    ("10^−7 = 1", "not-true", ["1e-7", "1"]),
    ("1 ÷ 2^70 = 1", "not-true", ["8.470329472543003e-22", "1"]),
    ("2^80 ÷ 3 = 1", "not-true", ["1208925819614629174706176/3", "1"]),
    ("(2^53+1) = 2^53", "not-true", ["9007199254740993", "9007199254740992"]),
    ("√(2^200) = 2^100", nil, ["1267650600228229401496703205376"]),
    ("12345678901234567890123 ÷ 10 = 1", "not-true", ["1.2345678901234568e+21", "1"]),
    ("1 ÷ 1024 = 1", "not-true", ["0.0009765625", "1"]),
    ("√3 × 10^20 = 1", "not-true", ["≈173205000000000000000", "1"]),
    ("√3 ÷ 10^9 = 1", "not-true", ["≈1.73205e-9", "1"]),
    ("√2 × 10^21 = 1", "not-true", ["≈1.41421e+21", "1"]),
    ("(√2)^(10^3) = 1", "not-true", ["≈3.27339e+150", "1"]),
    ("√99999999999999999999 = 1", "not-true", ["≈10000000000", "1"]),
    ("352 = 11 × −6-960^−1 = 21", "not-true", ["352", "-63361/960", "21"]),
    ("319 = (7-2.5)^287", "not-true", ["319", "2.964773045213904e+187"]),
  ] as [(String, String?, [String])])
  func agreesWithTheServer(text: String, error: String?, values: [String]) {
    switch EquationChecker.check(text) {
    case .solved(let solved):
      #expect(error == nil)
      #expect([solved.value] == values)
    case .failed(let failure):
      #expect(failure.error.rawValue == error)
      if failure.error == .notTrue { #expect(failure.values == values) }
    }
  }

  @Test func parseMessages() {
    func message(_ text: String) -> String? {
      if case .failed(let f) = EquationChecker.check(text) { return f.message }
      return nil
    }
    #expect(message("2 + a = 3") == "“a” isn’t something the checker knows")
    #expect(message("2 2 = 4") == "Put an operator after 2")
    #expect(message("(2 = 2") == "A bracket is never closed")
    #expect(message("2 + = 3") == "Unexpected “=”")
    #expect(message("2 +") == "The math ends too soon")
    #expect(message("2 + 2 = 5") == "Not true yet: the sides are 4 and 5")
  }

  /// The longest text the checker takes, nested as deep as it goes, parses
  /// and evaluates without running out of stack, off the main thread as the
  /// app checks while you type.
  /// Past 400 characters nothing parses, however it nests, so drawing
  /// pasted text can't overflow the stack (Codex on #2).
  @Test func tooLongToParse() {
    let deep = String(repeating: "(", count: 10_000) + "1" + String(repeating: ")", count: 10_000) + "=1"
    #expect(EquationChecker.parse(deep) == nil)
    #expect(EquationChecker.tex(of: deep) == nil)
    guard case .failed(let failure) = EquationChecker.check(deep) else {
      Issue.record("expected too-big")
      return
    }
    #expect(failure.error == .tooBig)
    let tooLong = String(repeating: "1 + ", count: 300) + "1 = 301"
    #expect(tooLong.count > 1200)
    #expect(EquationChecker.parse(tooLong) == nil)
  }

  /// A way within 400 characters can come back longer once canonical; the
  /// checker must still parse and draw its own output.
  @Test func canonicalLongerThanTheWay() throws {
    let way = Array(repeating: "1", count: 101).joined(separator: "+") + "=101"
    #expect(way.count <= 400)
    guard case .solved(let solved) = EquationChecker.check(way) else {
      Issue.record("expected true")
      return
    }
    #expect(solved.canonical.count > 400)
    let fromWay = try #require(EquationChecker.tex(of: way))
    #expect(EquationChecker.tex(of: solved.canonical) == fromWay)
    #expect(EquationChecker.parse(solved.canonical) == solved.sides)
    // The worst a way can grow: every other character an operator.
    let widest = Array(repeating: "1", count: 199).joined(separator: "*") + "=1"
    #expect(widest.count <= 400)
    guard case .solved(let wide) = EquationChecker.check(widest) else {
      Issue.record("expected true")
      return
    }
    #expect(EquationChecker.parse(wide.canonical) != nil)
  }

  /// The deepest text `parse` takes still fits its stack in Debug.
  @Test func deepestParse() {
    let depth = 598
    let deep = String(repeating: "(", count: depth) + "1" + String(repeating: ")", count: depth) + "=1"
    #expect(deep.utf16.count <= 1200)
    #expect(EquationChecker.parse(deep) != nil)
  }

  @Test func deepNesting() async {
    let depth = 198
    let brackets = String(repeating: "(", count: depth) + "2" + String(repeating: ")", count: depth) + "= 2"
    #expect(brackets.count == 400)
    let roots = String(repeating: "√", count: 396) + "1=1"
    let minuses = String(repeating: "−", count: 197) + "1=" + String(repeating: "−", count: 197) + "1"
    let answers = await Task.detached { [brackets, roots, minuses] in
      [brackets, roots, minuses].map { EquationChecker.check($0).isTrue }
    }.value
    #expect(answers == [true, true, true])
    if case .failed(let f) = EquationChecker.check(brackets + " ") { #expect(f.error == .tooBig) } else { Issue.record("401 long") }
  }

  @Test func treeAndText() throws {
    let sides = try #require(EquationChecker.parse("(90 - 82) / 8 * 1 * 2 = 6 / (10 - 7)"))
    #expect(sides.count == 2)
    #expect(sides[1] == .binary(.divide, .number("6"), .group(.binary(.subtract, .number("10"), .number("7")))))
    #expect(sides[1].bare == sides[1])
    #expect(MathNode.group(.group(.number("1"))).bare == .number("1"))
    #expect(EquationChecker.parse("2 +") == nil)
    #expect(EquationChecker.tex(of: "2 +") == nil)
  }

  @Test func normalizesNumbers() {
    #expect(EquationChecker.normalizeNumber("07") == "7")
    #expect(EquationChecker.normalizeNumber(".5") == "0.5")
    #expect(EquationChecker.normalizeNumber("2.50") == "2.5")
    #expect(EquationChecker.normalizeNumber("000") == "0")
    #expect(EquationChecker.normalizeNumber(" 10.0 ") == "10")
  }
}

@Suite struct BigIntTests {
  @Test func readsAndWritesDigits() {
    let text = "788657867364790503552363213932185062295135977687173263294742533244359449963403342920304284011984623904177212138919638830257642790242637105061926624952829931113462857270763317237396988943922445621451664240254033291864131227428294853277524242407573903240321257405579568660226031904170324062351700858796178922222789623703897374720000000000000000000000000000000000000000000000000"
    #expect(BigInt(digits: text)?.description == text)
    #expect(BigInt(digits: "000123")?.description == "123")
    #expect(BigInt(digits: "") == nil)
    #expect(BigInt(digits: "1a") == nil)
    #expect(BigInt(-42).description == "-42")
    #expect(BigInt(0).description == "0")
  }

  @Test func divisionTruncatesLikeJavaScript() {
    let (q, r) = BigInt(-7).quotientAndRemainder(dividingBy: BigInt(2))
    #expect(q == BigInt(-3))
    #expect(r == BigInt(-1))
    let (q2, r2) = BigInt(7).quotientAndRemainder(dividingBy: BigInt(-2))
    #expect(q2 == BigInt(-3))
    #expect(r2 == BigInt(1))
    let big = BigInt(10).power(100) + BigInt(7)
    let divisor = BigInt(10).power(40) + BigInt(3)
    let (bq, br) = big.quotientAndRemainder(dividingBy: divisor)
    #expect(bq * divisor + br == big)
    #expect(br < divisor)
  }

  @Test func shiftsFloor() {
    #expect(BigInt(-5) >> 1 == BigInt(-3))
    #expect(BigInt(5) >> 1 == BigInt(2))
    #expect(BigInt(-4) >> 1 == BigInt(-2))
    #expect(BigInt(1) << 100 == BigInt(2).power(100))
  }

  @Test func becomesTheNearestDouble() {
    #expect(BigInt(2).power(53).doubleValue == 9_007_199_254_740_992)
    // 2^53 + 1 is a tie between 2^53 and 2^53 + 2: even wins.
    #expect((BigInt(2).power(53) + .one).doubleValue == 9_007_199_254_740_992)
    #expect((BigInt(2).power(53) + BigInt(3)).doubleValue == 9_007_199_254_740_996)
    // Past 64 bits, anything below the kept bits still rounds up.
    #expect((BigInt(2).power(80) + BigInt(2).power(27) + .one).doubleValue == 0x1p80 + 0x1p28)
    #expect(BigInt(2).power(1024).doubleValue == .infinity)
    #expect((-BigInt(2).power(1100)).doubleValue == -.infinity)
    #expect(BigInt(10).power(300).doubleValue == 1e300)
  }

  @Test func gcdAndCounts() {
    #expect(BigInt.gcd(BigInt(-12), BigInt(18)) == BigInt(6))
    #expect(BigInt.gcd(.zero, .zero) == .zero)
    #expect(BigInt(0).bitCount == 1)
    #expect(BigInt(255).bitCount == 8)
    #expect(BigInt(-256).bitCount == 9)
  }
}

@Suite struct JSNumberTests {
  @Test(arguments: [
    (0.3, "0.3"), (1e21, "1e+21"), (1e20, "100000000000000000000"), (1e-7, "1e-7"),
    (0.000001, "0.000001"), (123.456, "123.456"), (-0.5, "-0.5"), (5e-324, "5e-324"),
    (1.7976931348623157e308, "1.7976931348623157e+308"), (-0.0, "0"), (Double.infinity, "Infinity"),
  ])
  func writesLikeJavaScript(value: Double, text: String) {
    #expect(JSNumber.string(value) == text)
  }

  @Test func toPrecisionSix() {
    #expect(JSNumber.roundedString(2.0.squareRoot(), significantDigits: 6) == "1.41421")
    #expect(JSNumber.roundedString(999_999.5, significantDigits: 6) == "1000000")
    #expect(JSNumber.roundedString(-0.000012345678, significantDigits: 6) == "-0.0000123457")
    #expect(JSNumber.roundedString(1_234_565, significantDigits: 6) == "1234570")
    // The smallest and largest doubles: every digit is worked out exactly.
    #expect(JSNumber.roundedString(5e-324, significantDigits: 6) == "5e-324")
    #expect(JSNumber.roundedString(.greatestFiniteMagnitude, significantDigits: 6) == "1.79769e+308")
    #expect(JSNumber.roundedString(0.1, significantDigits: 6) == "0.1")
  }

  @Test func powLikeJavaScript() {
    #expect(JSNumber.pow(1, .infinity).isNaN)
    #expect(JSNumber.pow(-1, -.infinity).isNaN)
    #expect(JSNumber.pow(0, 0) == 1)
    #expect(JSNumber.pow(2, 0.5) == 2.0.squareRoot())
  }
}
