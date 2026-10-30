import Foundation

/// How JavaScript writes numbers, so a value reads exactly as the server
/// writes it ("0.3", "1e+21", "≈4.89898").
enum JSNumber {
  /// `String(x)`: the shortest digits that read back as x, laid out by
  /// ECMAScript's Number::toString.
  static func string(_ x: Double) -> String {
    if x.isNaN { return "NaN" }
    if x.isInfinite { return x < 0 ? "-Infinity" : "Infinity" }
    if x == 0 { return "0" }
    if x < 0 { return "-" + string(-x) }
    // Swift's description is also the shortest round-trip digits; only the
    // layout differs. Read it as digits and a decimal point position.
    let (digits, point) = decompose(x.description)
    return layout(digits: digits, point: point)
  }

  /// `Number(x.toPrecision(p))` written back as text: x rounded to p
  /// significant digits, a tie going to the larger, then as `string(_:)`.
  static func roundedString(_ x: Double, significantDigits p: Int) -> String {
    if !x.isFinite || x == 0 { return string(x) }
    let negative = x < 0
    // A double's exact decimal expansion has at most 767 significant digits,
    // so this is exact and nothing is rounded before we round.
    let exact = String(format: "%.780e", abs(x))
    let (all, point) = decompose(exact)
    var kept = Array(all.prefix(p)).map { Int($0.asciiValue! - 48) }
    while kept.count < p { kept.append(0) }
    var exponent = point
    let next = all.count > p ? Int(Array(all)[p].asciiValue! - 48) : 0
    if next >= 5 {
      var i = p - 1
      while i >= 0 {
        if kept[i] == 9 {
          kept[i] = 0
          i -= 1
        } else {
          kept[i] += 1
          break
        }
      }
      if i < 0 {
        kept.insert(1, at: 0)
        kept.removeLast()
        exponent += 1
      }
    }
    let text = "0." + kept.map(String.init).joined() + "e" + String(exponent)
    let rounded = Double(text)!
    return string(negative ? -rounded : rounded)
  }

  /// "123.45" → ("12345", 3); "1.5e-07" → ("15", -6); "0.0001" → ("1", -3).
  /// The digits have no leading or trailing zeros; the value is
  /// 0.digits × 10^point.
  private static func decompose(_ text: String) -> (String, Int) {
    let parts = text.lowercased().split(separator: "e", omittingEmptySubsequences: false)
    let mantissa = parts[0]
    let exponent = parts.count > 1 ? Int(parts[1])! : 0
    let pieces = mantissa.split(separator: ".", omittingEmptySubsequences: false)
    let whole = String(pieces[0])
    let fraction = pieces.count > 1 ? String(pieces[1]) : ""
    var digits = Substring(whole + fraction)
    var point = whole.count + exponent
    while digits.first == "0" {
      digits = digits.dropFirst()
      point -= 1
    }
    while digits.last == "0" { digits = digits.dropLast() }
    return (String(digits), point)
  }

  private static func layout(digits: String, point n: Int) -> String {
    let k = digits.count
    if k <= n && n <= 21 { return digits + String(repeating: "0", count: n - k) }
    if 0 < n && n <= 21 {
      let index = digits.index(digits.startIndex, offsetBy: n)
      return digits[..<index] + "." + digits[index...]
    }
    if -6 < n && n <= 0 { return "0." + String(repeating: "0", count: -n) + digits }
    let e = n - 1
    let exponent = (e < 0 ? "-" : "+") + String(abs(e))
    if k == 1 { return digits + "e" + exponent }
    return String(digits.prefix(1)) + "." + digits.dropFirst() + "e" + exponent
  }

  /// `Math.pow`: C's pow, except that JavaScript has no answer for 1 or -1
  /// raised to an infinite power.
  static func pow(_ x: Double, _ y: Double) -> Double {
    if y.isInfinite && abs(x) == 1 { return .nan }
    return Foundation.pow(x, y)
  }
}
