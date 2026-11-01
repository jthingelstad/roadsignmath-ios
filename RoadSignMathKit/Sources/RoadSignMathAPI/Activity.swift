import Foundation

// What's new on your signs (API 1.10.0, `GET /me/activity`): the ways
// other players found and the hearts they gave on the signs you posted or
// are a finder of, in the last 30 days, newest first. You shows it as
// "On your signs", with a dot on your avatar while something's new.

public struct MyActivity: Codable, Sendable, Equatable {
  /// How many days back it looks.
  public var days: Int
  /// Newest first.
  public var items: [ActivityItem]

  public init(days: Int = 30, items: [ActivityItem]) {
    self.days = days
    self.items = items
  }

  /// When the newest item happened.
  public var newest: Date? { items.map(\.at).max() }

  /// Anything after `seen`. Nothing seen yet is nothing new: the first
  /// read on a phone arrives seen, as badges do.
  public func hasNew(since seen: Date?) -> Bool {
    guard let seen, let newest else { return false }
    return newest > seen
  }
}

public struct ActivityItem: Codable, Sendable, Hashable {
  public enum Kind: String, Codable, Sendable {
    case way, heart
    /// A kind a newer server sends that this app doesn't know: left out.
    case other

    public init(from decoder: any Decoder) throws {
      self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
    }
  }

  /// The sign it happened on.
  public struct SignRef: Codable, Sendable, Hashable {
    public var id: String
    public var slug: String
    public var title: String
    /// Small; a held or hidden sign's is `/me/photos`, read with your
    /// token. Nil when you found the sign but didn't post it.
    public var photoThumbUrl: URL?

    public init(id: String, slug: String, title: String, photoThumbUrl: URL? = nil) {
      self.id = id
      self.slug = slug
      self.title = title
      self.photoThumbUrl = photoThumbUrl
    }
  }

  /// Who found the way or gave the heart. Handle and name are nil until
  /// they give a name.
  public struct Who: Codable, Sendable, Hashable {
    public var handle: String?
    public var name: String?
    public var avatarColor: String
    public var avatarThumbUrl: URL?

    public init(handle: String?, name: String?, avatarColor: String = "#006348", avatarThumbUrl: URL? = nil) {
      self.handle = handle
      self.name = name
      self.avatarColor = avatarColor
      self.avatarThumbUrl = avatarThumbUrl
    }

    /// Their name, or "Someone" before they've given one.
    public var shownName: String { name.flatMap { $0.isEmpty ? nil : $0 } ?? "Someone" }
  }

  public struct Way: Codable, Sendable, Hashable {
    public var id: String
    public var text: String
    /// LaTeX for drawing it; nil only if it no longer parses.
    public var tex: String?

    public init(id: String, text: String, tex: String?) {
      self.id = id
      self.text = text
      self.tex = tex
    }
  }

  public var kind: Kind
  public var at: Date
  public var sign: SignRef
  public var player: Who
  /// The way, for a way; nil for a heart.
  public var way: Way?

  public init(kind: Kind, at: Date, sign: SignRef, player: Who, way: Way? = nil) {
    self.kind = kind
    self.at = at
    self.sign = sign
    self.player = player
    self.way = way
  }
}

/// One line of "On your signs": a way someone found, or the hearts given
/// one sign, gathered ("Pat and 2 others hearted Cancel it all out").
public struct ActivityRow: Sendable, Hashable, Identifiable {
  public enum Kind: Sendable, Hashable {
    case way(ActivityItem.Way)
    case hearts
  }

  public var id: String
  public var kind: Kind
  /// The newest of it.
  public var at: Date
  public var sign: ActivityItem.SignRef
  /// Newest first; one for a way.
  public var players: [ActivityItem.Who]
  /// Since you last looked.
  public var new: Bool

  /// "Pat", "Pat and Sam", "Pat and 2 others".
  public var who: String {
    guard let first = players.first?.shownName else { return "Someone" }
    switch players.count {
    case 1: return first
    case 2:
      let second = players[1].shownName
      return first + " and " + (players[1].name == nil ? second.lowercased() : second)
    default: return first + " and \(players.count - 1) others"
    }
  }

  /// The rows for `items` (newest first), new ones being after `seen`.
  /// Each way is a row; hearts on the same sign gather into one, in the
  /// place of the newest, new ones apart from the ones seen before.
  public static func rows(_ items: [ActivityItem], seen: Date?) -> [ActivityRow] {
    var rows: [ActivityRow] = []
    var hearts: [String: Int] = [:]
    for item in items.sorted(by: { $0.at > $1.at }) {
      let new = seen.map { item.at > $0 } ?? false
      switch item.kind {
      case .way:
        guard let way = item.way else { continue }
        rows.append(ActivityRow(id: "way:" + way.id, kind: .way(way), at: item.at, sign: item.sign, players: [item.player], new: new))
      case .heart:
        let key = item.sign.id + (new ? ":new" : ":seen")
        if let index = hearts[key] {
          rows[index].players.append(item.player)
        } else {
          hearts[key] = rows.count
          rows.append(ActivityRow(id: "hearts:" + key, kind: .hearts, at: item.at, sign: item.sign, players: [item.player], new: new))
        }
      case .other:
        continue
      }
    }
    return rows
  }

  /// "now", "5m", "2h" today; then "Yesterday", "Oct 27", and "Oct 27,
  /// 2025" before this year.
  public static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
    let seconds = now.timeIntervalSince(date)
    if calendar.isDate(date, inSameDayAs: now) || seconds < 3600 {
      if seconds < 60 { return "now" }
      if seconds < 3600 { return "\(Int(seconds / 60))m" }
      return "\(Int(seconds / 3600))h"
    }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
      return "Yesterday"
    }
    var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: calendar.locale ?? .current, calendar: calendar,
                                 timeZone: calendar.timeZone)
      .month(.abbreviated).day()
    if calendar.component(.year, from: date) != calendar.component(.year, from: now) { style = style.year() }
    return date.formatted(style)
  }
}

extension APIClient {
  /// What's new on your signs: the last 30 days, newest first, at most
  /// 100. Never cached.
  public func myActivity(token: String) async throws -> MyActivity {
    try await answer(to: request("GET", ["me", "activity"], token: token))
  }
}
