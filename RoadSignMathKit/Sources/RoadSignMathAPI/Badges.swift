import Foundation

// Badges (API 1.6.0): little road signs a player collects for what
// happened on the road. No points: nothing is added up, ranked or
// compared. The server works them out from the shown signs and their ways
// each time it's asked, so a badge follows its sign.

/// Each shelf is drawn as a family of road signs: white plates for the
/// firsts, green guide signs and interstate shields for places, yellow
/// diamonds for the math, brown for the seasons, blue service signs for
/// the secret ones.
public enum BadgeShelf: String, Codable, Sendable, Hashable, CaseIterable {
  case firsts, places, math, seasons, secret
  /// A shelf this app doesn't know yet, from a newer server.
  case other

  public init(from decoder: any Decoder) throws {
    self = BadgeShelf(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
  }

  /// The five shelves, in the order the server lists them.
  public static let shown: [BadgeShelf] = [.firsts, .places, .math, .seasons, .secret]
}

/// A badge in `GET /badges`. A secret one is only its id and shelf until
/// it's earned.
public struct CatalogBadge: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var shelf: BadgeShelf
  public var secret: Bool
  public var name: String?
  /// How it's earned, in a line.
  public var how: String?
  /// What its sign shows: a word, a symbol or a number. Empty for a
  /// stepped badge, whose sign shows the step.
  public var mark: String?
  /// For a badge earned in steps, each step's count, smallest first.
  public var steps: [Int]?

  public init(id: String, shelf: BadgeShelf, secret: Bool = false, name: String?, how: String?, mark: String?, steps: [Int]? = nil) {
    self.id = id
    self.shelf = shelf
    self.secret = secret
    self.name = name
    self.how = how
    self.mark = mark
    self.steps = steps
  }
}

/// The sign that earned a badge.
public struct BadgeSign: Codable, Sendable, Hashable {
  public var id: String
  public var slug: String
  public var title: String
  public var url: URL

  public init(id: String, slug: String, title: String, url: URL) {
    self.id = id
    self.slug = slug
    self.title = title
    self.url = url
  }
}

/// A badge a player has: what it is, the day and the sign that first
/// earned it, and for a stepped badge the step reached (its `mark`).
public struct EarnedBadge: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var shelf: BadgeShelf
  public var name: String
  public var how: String
  public var mark: String
  public var step: Int?
  /// "2025-09-01": the day the sign was found, or for math the day the
  /// way was written.
  public var earnedOn: String
  public var sign: BadgeSign

  public init(id: String, shelf: BadgeShelf, name: String, how: String, mark: String, step: Int? = nil, earnedOn: String, sign: BadgeSign) {
    self.id = id
    self.shelf = shelf
    self.name = name
    self.how = how
    self.mark = mark
    self.step = step
    self.earnedOn = earnedOn
    self.sign = sign
  }

  /// "Square Root", or "States: 5" with its step, as the website names it.
  public var title: String { step.map { "\(name): \($0)" } ?? name }

  /// The day it was earned.
  public var day: DateComponents? { Sign.day(earnedOn) }
}

public struct BadgeCatalog: Codable, Sendable, Hashable {
  public var badges: [CatalogBadge]
}

extension APIClient {
  /// Every badge there is, in the server's order. Secret ones say only
  /// their id and shelf.
  public func badges() async throws -> [CatalogBadge] {
    let catalog: BadgeCatalog = try await get(["badges"])
    return catalog.badges
  }
}

// MARK: Shelves

/// One place on a shelf: a badge earned or still out there.
public struct BadgeSlot: Sendable, Hashable, Identifiable {
  public var badge: CatalogBadge
  public var earned: EarnedBadge?
  public var id: String { badge.id }

  public init(badge: CatalogBadge, earned: EarnedBadge?) {
    self.badge = badge
    self.earned = earned
  }

  /// The next step to reach: the first one when it isn't earned yet, the
  /// one after the step reached, nil at the top or for a badge without
  /// steps.
  public var nextStep: Int? {
    guard let steps = badge.steps, !steps.isEmpty else { return nil }
    guard let reached = earned?.step else { return earned == nil ? steps.first : nil }
    return steps.first { $0 > reached }
  }

  /// A secret one not earned: its sign stays blank.
  public var hidden: Bool { earned == nil && badge.secret }
}

public enum Badges {
  /// The five shelves, each with every badge in the catalog's order:
  /// the earned ones carrying how they were earned. An earned badge the
  /// catalog doesn't list (a newer server, or no catalog) goes on its
  /// shelf after the rest; a shelf with nothing on it is left out.
  public static func shelves(catalog: [CatalogBadge], earned: [EarnedBadge]) -> [(shelf: BadgeShelf, slots: [BadgeSlot])] {
    let byId = Dictionary(earned.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let listed = Set(catalog.map(\.id))
    var slots = catalog.map { BadgeSlot(badge: $0, earned: byId[$0.id]) }
    for badge in earned where !listed.contains(badge.id) {
      slots.append(BadgeSlot(badge: CatalogBadge(badge), earned: badge))
    }
    let order = BadgeShelf.shown + [.other]
    return order.compactMap { shelf in
      let mine = slots.filter { $0.badge.shelf == shelf }
      return mine.isEmpty ? nil : (shelf, mine)
    }
  }

  /// The newest earned first (by the day, then the catalog's order), for
  /// the few shown on your page.
  public static func newest(_ earned: [EarnedBadge]) -> [EarnedBadge] {
    earned.enumerated()
      .sorted { ($0.element.earnedOn, -$0.offset) > ($1.element.earnedOn, -$1.offset) }
      .map(\.element)
  }
}

extension CatalogBadge {
  /// An earned badge as far as it says: a stepped one's steps aren't
  /// known without the catalog.
  public init(_ earned: EarnedBadge) {
    self.init(id: earned.id, shelf: earned.shelf, name: earned.name, how: earned.how,
              mark: earned.step == nil ? earned.mark : "")
  }
}

// MARK: Seen

/// The badges a player has seen on this phone, so a new one gets a dot
/// until it's looked at. A stepped badge is seen per step, so reaching the
/// next step is new again.
public struct SeenBadges: Codable, Sendable, Hashable {
  public var keys: Set<String>

  public init(keys: Set<String> = []) {
    self.keys = keys
  }

  /// The first time a player's badges are read here: the ones already
  /// earned arrive seen, so nothing is made a fuss of on day one.
  public init(arriving earned: [EarnedBadge]) {
    keys = Set(earned.map(SeenBadges.key))
  }

  public static func key(_ badge: EarnedBadge) -> String {
    badge.step.map { "\(badge.id):\($0)" } ?? badge.id
  }

  public func isSeen(_ badge: EarnedBadge) -> Bool { keys.contains(SeenBadges.key(badge)) }

  /// The earned badges not seen yet, in the order given.
  public func unseen(_ earned: [EarnedBadge]) -> [EarnedBadge] { earned.filter { !isSeen($0) } }

  public mutating func see(_ badges: [EarnedBadge]) {
    keys.formUnion(badges.map(SeenBadges.key))
  }
}
