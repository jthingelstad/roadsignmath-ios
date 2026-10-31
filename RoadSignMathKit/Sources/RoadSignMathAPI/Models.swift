import Foundation

// The JSON the server's read routes answer with (OpenAPI 1.6.0 at
// GET /api/v1/openapi.json). Keys are snake_case on the wire and camelCase
// here; `APIClient` decodes with `.convertFromSnakeCase`. Every field the
// schema allows to be null is optional, so a new nullable field never
// breaks an older app.

public struct Sign: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var slug: String
  public var title: String
  /// The sign's page on roadsignmath.xyz, for sharing.
  public var url: URL
  public var caption: String?
  /// The calendar day it was found, "2025-09-01".
  public var foundOn: String
  public var postedAt: Date
  public var postedBy: String?
  public var place: Place
  public var photos: [Photo]
  /// Not sent with signs near a place.
  public var numbers: [SignNumber]?
  public var finders: [Finder]
  public var firstWay: FirstWay?
  public var wayCount: Int
  public var visibility: Visibility
  public var moderationNote: String?
  /// How far away, with signs near a place only.
  public var miles: Double?
}

public struct SignDetail: Codable, Sendable, Hashable, Identifiable {
  public var sign: Sign
  public var ways: [Way]
  /// Since API 1.6.0, on posting a sign (and adding a way): the badges
  /// that answer earned, or reached a new step of. Empty on a plain read.
  public var unlocked: [EarnedBadge]
  public var id: String { sign.id }

  public init(from decoder: any Decoder) throws {
    sign = try Sign(from: decoder)
    let container = try decoder.container(keyedBy: Keys.self)
    ways = try container.decode([Way].self, forKey: .ways)
    unlocked = try container.decodeIfPresent([EarnedBadge].self, forKey: .unlocked) ?? []
  }

  public func encode(to encoder: any Encoder) throws {
    try sign.encode(to: encoder)
    var container = encoder.container(keyedBy: Keys.self)
    try container.encode(ways, forKey: .ways)
    if !unlocked.isEmpty { try container.encode(unlocked, forKey: .unlocked) }
  }

  private enum Keys: String, CodingKey { case ways, unlocked }
}

public enum Visibility: String, Codable, Sendable, Hashable {
  case shown, held, hidden
}

public struct Place: Codable, Sendable, Hashable {
  public var label: String
  /// Two-letter US state.
  public var state: String?
  public var lat: Double?
  public var lng: Double?
  /// Placed by town, not by where the photo was taken.
  public var approximate: Bool
}

public struct Photo: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var width: Int
  public var height: Int
  public var alt: String
  public var url: URL
  public var thumbUrl: URL
}

public struct SignNumber: Codable, Sendable, Hashable {
  public var value: String
  /// What it was read from, "EXIT 7B".
  public var text: String?
  /// Why the value differs from the text, "Read as 7".
  public var why: String?
  /// Where on the first photo: x, y, width, height as fractions.
  public var box: [Double]?
}

public struct Finder: Codable, Sendable, Hashable {
  public enum Role: String, Codable, Sendable, Hashable {
    case found
    case tookPhoto = "took_photo"
    case spotted
  }

  public var name: String
  public var handle: String?
  public var role: Role
}

public struct FirstWay: Codable, Sendable, Hashable {
  public var text: String
  /// LaTeX for drawing the math; nil only if the text no longer parses.
  public var tex: String?
  public var value: String
}

public struct Way: Codable, Sendable, Hashable, Identifiable {
  public struct By: Codable, Sendable, Hashable {
    public var handle: String
    public var name: String
  }

  public var id: String
  public var text: String
  public var tex: String?
  public var value: String
  public var numbers: [String]
  public var by: By?
  public var createdAt: Date
}

public struct SignPage: Codable, Sendable, Hashable {
  public var signs: [Sign]
  public var nextCursor: String?
}

public struct Pin: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var slug: String
  public var title: String
  public var url: URL
  public var lat: Double?
  public var lng: Double?
  public var approximate: Bool
  public var state: String?
  public var foundOn: String
  public var thumbUrl: URL?
  /// Since API 1.4.0, enough to search the map without reading every
  /// sign: where it was (the sign's `place.label`), its checked numbers in
  /// the sign's order, and who found it. Optional, so an older server's
  /// pins still read.
  public var placeLabel: String?
  public var numbers: [String]?
  public var finders: [PinFinder]?
}

/// A finder on a pin: the name shown, and the handle when the finder has
/// an account (the signs from before the app have names only).
public struct PinFinder: Codable, Sendable, Hashable {
  public var name: String
  public var handle: String?
}

public struct MapPins: Codable, Sendable, Hashable {
  public var pins: [Pin]
  public var years: [Int]
}

public struct Player: Codable, Sendable, Hashable, Identifiable {
  public var handle: String
  public var name: String
  /// "#006348"
  public var avatarColor: String
  /// Since API 1.7.0: their profile photo, 512 pixels square, and the
  /// same at 160 for small faces. Nil when they show their first letter.
  public var avatarUrl: URL?
  public var avatarThumbUrl: URL?
  public var bio: String?
  public var url: URL
  public var signCount: Int
  public var states: [String]
  public var firstYear: Int?
  /// With one player only.
  public var signs: [Sign]?
  /// With one player only, since API 1.6.0: the badges they've earned, in
  /// the catalog's order. Never the ones not earned, and no count.
  public var badges: [EarnedBadge]?
  public var id: String { handle }
}

public struct APIIndex: Codable, Sendable, Hashable {
  public var apiVersion: String
  public var signs: Int
  public var players: Int
  public var states: Int
}

/// What the server says when it says no: `{"error": {"code", "message"}}`.
public struct APIError: Error, Codable, Sendable, Hashable {
  public var status: Int
  public var code: String
  public var message: String
}

extension Sign {
  /// "2025-09-01" as a day, or nil.
  public var foundDay: DateComponents? { Sign.day(foundOn) }

  static func day(_ text: String) -> DateComponents? {
    let parts = text.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return DateComponents(year: parts[0], month: parts[1], day: parts[2])
  }

  /// Who found it, the photo's taker and anyone who spotted it, finders
  /// first, as the sign lists them.
  public var foundBy: [Finder] { finders.filter { $0.role == .found } + finders.filter { $0.role != .found } }
}

extension Pin {
  public var year: Int? { Sign.day(foundOn)?.year }
}
