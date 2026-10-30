import Foundation

/// How well a sign's numbers were read.
public struct SignScore: Sendable, Hashable, Codable {
  /// Numbers the player used.
  public var expected: Int
  /// Numbers read.
  public var read: Int
  /// Expected numbers that were read, counting repeats once each
  /// (the multiset intersection).
  public var hits: Int

  public init(expected: [Decimal], read: [Decimal]) {
    self.expected = expected.count
    self.read = read.count
    var left = Multiset(read)
    var hits = 0
    for value in expected where left.remove(value) {
      hits += 1
    }
    self.hits = hits
  }

  /// hits / expected.
  public var recall: Double { expected == 0 ? 1 : Double(hits) / Double(expected) }
  /// Every number the player used was read.
  public var isFullHit: Bool { hits == expected }
  /// Numbers read that the player didn't use. On the archive these are
  /// often real numbers the old rules didn't allow (road numbers), so they
  /// are informative, not errors.
  public var extras: Int { read - hits }
}

/// A multiset of numbers, compared by value (2.50 is 2.5).
public struct Multiset: Sendable, Hashable {
  public private(set) var counts: [Decimal: Int] = [:]

  public init(_ values: [Decimal] = []) {
    for value in values { counts[value, default: 0] += 1 }
  }

  /// Takes one `value` out; false if there was none.
  @discardableResult
  public mutating func remove(_ value: Decimal) -> Bool {
    guard let count = counts[value], count > 0 else { return false }
    counts[value] = count == 1 ? nil : count - 1
    return true
  }

  /// The union: each value as many times as the most any one holds. A sign
  /// with two photos is read as the union of what each photo gave, so a
  /// number seen on both counts once.
  public static func union(_ sets: [[Decimal]]) -> [Decimal] {
    var most: [Decimal: Int] = [:]
    for values in sets {
      for (value, count) in Multiset(values).counts {
        most[value] = max(most[value] ?? 0, count)
      }
    }
    return most.keys.sorted().flatMap { Array(repeating: $0, count: most[$0]!) }
  }
}

/// Totals for one variant over a set of signs.
public struct ScoreSummary: Sendable, Hashable, Codable {
  public var signs: Int
  public var fullHits: Int
  public var meanRecall: Double
  public var extras: Int
  public var meanSecondsPerImage: Double

  public init(scores: [SignScore], seconds: [Double]) {
    signs = scores.count
    fullHits = scores.filter(\.isFullHit).count
    meanRecall = scores.isEmpty ? 0 : scores.map(\.recall).reduce(0, +) / Double(scores.count)
    extras = scores.map(\.extras).reduce(0, +)
    meanSecondsPerImage = seconds.isEmpty ? 0 : seconds.reduce(0, +) / Double(seconds.count)
  }

  public var fullHitShare: Double { signs == 0 ? 0 : Double(fullHits) / Double(signs) }
}
