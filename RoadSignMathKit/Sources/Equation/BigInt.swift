/// A signed whole number of any size: what the server's checker gets from
/// JavaScript's BigInt, made small. It does only what the checker needs, with
/// BigInt's meaning: division truncates toward zero, the remainder takes the
/// dividend's sign, and `>>` floors. The checker caps every value at 4096
/// bits, so plain schoolbook arithmetic is quick enough.
struct BigInt: Sendable, Hashable, Comparable, CustomStringConvertible {
  /// True only for a value below zero; zero is never negative.
  private(set) var isNegative: Bool
  /// Base 2³² digits, least significant first, with no zero digits on top.
  /// Zero is the empty array.
  private(set) var limbs: [UInt32]

  init(_ value: Int) {
    var m = value.magnitude
    var limbs: [UInt32] = []
    while m != 0 {
      limbs.append(UInt32(truncatingIfNeeded: m))
      m >>= 32
    }
    self.init(isNegative: value < 0, limbs: limbs)
  }

  private init(isNegative: Bool, limbs: [UInt32]) {
    var limbs = limbs
    while limbs.last == 0 { limbs.removeLast() }
    self.limbs = limbs
    self.isNegative = isNegative && !limbs.isEmpty
  }

  /// Decimal digits only, as the tokenizer hands them over.
  init?(digits: some StringProtocol) {
    guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
    var limbs: [UInt32] = []
    var chunk: UInt32 = 0
    var chunkDigits = 0
    for character in digits {
      chunk = chunk * 10 + UInt32(character.asciiValue! - 48)
      chunkDigits += 1
      if chunkDigits == 9 {
        limbs = Self.multiplyAdd(limbs, 1_000_000_000, chunk)
        chunk = 0
        chunkDigits = 0
      }
    }
    if chunkDigits > 0 {
      var scale: UInt32 = 1
      for _ in 0..<chunkDigits { scale *= 10 }
      limbs = Self.multiplyAdd(limbs, scale, chunk)
    }
    self.init(isNegative: false, limbs: limbs)
  }

  static let zero = BigInt(0)
  static let one = BigInt(1)

  var isZero: Bool { limbs.isEmpty }
  var magnitude: BigInt { BigInt(isNegative: false, limbs: limbs) }

  /// The number of binary digits in the magnitude, at least 1, as the
  /// server's `bits()` counts them (`0n.toString(2)` is "0").
  var bitCount: Int { max(1, Self.bitLength(limbs)) }

  // MARK: Arithmetic

  static prefix func - (x: BigInt) -> BigInt { BigInt(isNegative: !x.isNegative, limbs: x.limbs) }

  static func + (a: BigInt, b: BigInt) -> BigInt {
    if a.isNegative == b.isNegative { return BigInt(isNegative: a.isNegative, limbs: add(a.limbs, b.limbs)) }
    if compare(a.limbs, b.limbs) >= 0 { return BigInt(isNegative: a.isNegative, limbs: subtract(a.limbs, b.limbs)) }
    return BigInt(isNegative: b.isNegative, limbs: subtract(b.limbs, a.limbs))
  }

  static func - (a: BigInt, b: BigInt) -> BigInt { a + -b }

  static func * (a: BigInt, b: BigInt) -> BigInt {
    BigInt(isNegative: a.isNegative != b.isNegative, limbs: multiply(a.limbs, b.limbs))
  }

  /// Truncating division, as BigInt's `/` and `%`. The divisor is never zero.
  func quotientAndRemainder(dividingBy divisor: BigInt) -> (quotient: BigInt, remainder: BigInt) {
    precondition(!divisor.isZero, "BigInt division by zero")
    let (q, r) = Self.divide(limbs, divisor.limbs)
    return (BigInt(isNegative: isNegative != divisor.isNegative, limbs: q), BigInt(isNegative: isNegative, limbs: r))
  }

  static func / (a: BigInt, b: BigInt) -> BigInt { a.quotientAndRemainder(dividingBy: b).quotient }
  static func % (a: BigInt, b: BigInt) -> BigInt { a.quotientAndRemainder(dividingBy: b).remainder }

  /// `x >> k` for k ≥ 0, flooring as BigInt does: -5 >> 1 is -3.
  static func >> (x: BigInt, k: Int) -> BigInt {
    if !x.isNegative { return BigInt(isNegative: false, limbs: shiftRight(x.limbs, k)) }
    // -(((|x| - 1) >> k) + 1)
    let reduced = shiftRight(subtract(x.limbs, [1]), k)
    return BigInt(isNegative: true, limbs: add(reduced, [1]))
  }

  static func << (x: BigInt, k: Int) -> BigInt { BigInt(isNegative: x.isNegative, limbs: shiftLeft(x.limbs, k)) }

  /// x raised to a whole power e ≥ 0; anything to the 0 is 1.
  func power(_ e: Int) -> BigInt {
    var result = BigInt.one
    var base = self
    var e = e
    while e > 0 {
      if e & 1 == 1 { result = result * base }
      e >>= 1
      if e > 0 { base = base * base }
    }
    return result
  }

  /// The greatest common divisor of the magnitudes; 0 only when both are 0.
  static func gcd(_ a: BigInt, _ b: BigInt) -> BigInt {
    var a = a.magnitude
    var b = b.magnitude
    while !b.isZero { (a, b) = (b, a % b) }
    return a
  }

  /// The nearest Double, ties to even, as `Number(bigint)`; ±∞ beyond the
  /// Double range.
  var doubleValue: Double {
    let length = Self.bitLength(limbs)
    if length == 0 { return 0 }
    let value: Double
    if length <= 64 {
      value = Double(Self.low64(limbs))
    } else {
      // The top 64 bits, with the lowest set when anything below them is,
      // round exactly as the whole number would.
      let shift = length - 64
      var top = Self.low64(Self.shiftRight(limbs, shift))
      if Self.hasBitsBelow(limbs, shift) { top |= 1 }
      value = Double(sign: .plus, exponent: shift, significand: Double(top))
    }
    return isNegative ? -value : value
  }

  var description: String {
    if limbs.isEmpty { return "0" }
    var chunks: [UInt32] = []
    var rest = limbs
    while !rest.isEmpty {
      let (q, r) = Self.divideSmall(rest, 1_000_000_000)
      chunks.append(r)
      rest = q
    }
    var text = isNegative ? "-" : ""
    text += String(chunks.last!)
    for chunk in chunks.dropLast().reversed() {
      let digits = String(chunk)
      text += String(repeating: "0", count: 9 - digits.count) + digits
    }
    return text
  }

  static func < (a: BigInt, b: BigInt) -> Bool {
    if a.isNegative != b.isNegative { return a.isNegative }
    let c = compare(a.limbs, b.limbs)
    return a.isNegative ? c > 0 : c < 0
  }

  // MARK: Magnitudes

  private static func compare(_ a: [UInt32], _ b: [UInt32]) -> Int {
    if a.count != b.count { return a.count < b.count ? -1 : 1 }
    var i = a.count - 1
    while i >= 0 {
      if a[i] != b[i] { return a[i] < b[i] ? -1 : 1 }
      i -= 1
    }
    return 0
  }

  private static func add(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
    let (long, short) = a.count >= b.count ? (a, b) : (b, a)
    var result: [UInt32] = []
    result.reserveCapacity(long.count + 1)
    var carry: UInt64 = 0
    for i in 0..<long.count {
      let sum = UInt64(long[i]) + (i < short.count ? UInt64(short[i]) : 0) + carry
      result.append(UInt32(truncatingIfNeeded: sum))
      carry = sum >> 32
    }
    if carry != 0 { result.append(UInt32(carry)) }
    return result
  }

  /// a - b, where a ≥ b.
  private static func subtract(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
    var result = a
    var borrow: Int64 = 0
    for i in 0..<a.count {
      var difference = Int64(a[i]) - (i < b.count ? Int64(b[i]) : 0) - borrow
      if difference < 0 {
        difference += 1 << 32
        borrow = 1
      } else {
        borrow = 0
      }
      result[i] = UInt32(difference)
    }
    while result.last == 0 { result.removeLast() }
    return result
  }

  private static func multiply(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
    if a.isEmpty || b.isEmpty { return [] }
    var result = [UInt32](repeating: 0, count: a.count + b.count)
    for i in 0..<a.count {
      var carry: UInt64 = 0
      let ai = UInt64(a[i])
      for j in 0..<b.count {
        let t = ai * UInt64(b[j]) + UInt64(result[i + j]) + carry
        result[i + j] = UInt32(truncatingIfNeeded: t)
        carry = t >> 32
      }
      result[i + b.count] = UInt32(carry)
    }
    while result.last == 0 { result.removeLast() }
    return result
  }

  private static func multiplyAdd(_ a: [UInt32], _ m: UInt32, _ addend: UInt32) -> [UInt32] {
    var result: [UInt32] = []
    result.reserveCapacity(a.count + 1)
    var carry = UInt64(addend)
    for limb in a {
      let t = UInt64(limb) * UInt64(m) + carry
      result.append(UInt32(truncatingIfNeeded: t))
      carry = t >> 32
    }
    if carry != 0 { result.append(UInt32(carry)) }
    return result
  }

  private static func divideSmall(_ a: [UInt32], _ d: UInt32) -> ([UInt32], UInt32) {
    var quotient = [UInt32](repeating: 0, count: a.count)
    var remainder: UInt64 = 0
    var i = a.count - 1
    while i >= 0 {
      let current = (remainder << 32) | UInt64(a[i])
      quotient[i] = UInt32(current / UInt64(d))
      remainder = current % UInt64(d)
      i -= 1
    }
    while quotient.last == 0 { quotient.removeLast() }
    return (quotient, UInt32(remainder))
  }

  /// Long division a bit at a time, starting from where the divisor's top
  /// bit meets the dividend's, so a small quotient is quick.
  private static func divide(_ a: [UInt32], _ b: [UInt32]) -> ([UInt32], [UInt32]) {
    if compare(a, b) < 0 { return ([], a) }
    if b.count == 1 {
      let (q, r) = divideSmall(a, b[0])
      return (q, r == 0 ? [] : [r])
    }
    let shift = bitLength(a) - bitLength(b)
    var remainder = a
    var divisor = shiftLeft(b, shift)
    var quotient = [UInt32](repeating: 0, count: shift / 32 + 1)
    var bit = shift
    while bit >= 0 {
      if compare(remainder, divisor) >= 0 {
        remainder = subtract(remainder, divisor)
        quotient[bit / 32] |= 1 << UInt32(bit % 32)
      }
      divisor = shiftRight(divisor, 1)
      bit -= 1
    }
    while quotient.last == 0 { quotient.removeLast() }
    return (quotient, remainder)
  }

  private static func shiftLeft(_ a: [UInt32], _ k: Int) -> [UInt32] {
    if a.isEmpty || k == 0 { return a }
    let words = k / 32
    let bits = UInt32(k % 32)
    var result = [UInt32](repeating: 0, count: words)
    result.reserveCapacity(words + a.count + 1)
    if bits == 0 {
      result.append(contentsOf: a)
      return result
    }
    var carry: UInt32 = 0
    for limb in a {
      result.append((limb << bits) | carry)
      carry = limb >> (32 - bits)
    }
    if carry != 0 { result.append(carry) }
    return result
  }

  private static func shiftRight(_ a: [UInt32], _ k: Int) -> [UInt32] {
    let words = k / 32
    if words >= a.count { return [] }
    let bits = UInt32(k % 32)
    var result = Array(a[words...])
    if bits != 0 {
      for i in 0..<result.count {
        let high = i + 1 < result.count ? result[i + 1] << (32 - bits) : 0
        result[i] = (result[i] >> bits) | high
      }
    }
    while result.last == 0 { result.removeLast() }
    return result
  }

  private static func bitLength(_ a: [UInt32]) -> Int {
    guard let top = a.last else { return 0 }
    return (a.count - 1) * 32 + (32 - top.leadingZeroBitCount)
  }

  private static func low64(_ a: [UInt32]) -> UInt64 {
    (a.count > 0 ? UInt64(a[0]) : 0) | (a.count > 1 ? UInt64(a[1]) << 32 : 0)
  }

  private static func hasBitsBelow(_ a: [UInt32], _ k: Int) -> Bool {
    let words = k / 32
    for i in 0..<min(words, a.count) where a[i] != 0 { return true }
    let bits = k % 32
    guard bits > 0, words < a.count else { return false }
    return a[words] & ((1 << UInt32(bits)) - 1) != 0
  }
}
