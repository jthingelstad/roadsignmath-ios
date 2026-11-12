import Foundation

/// A player's page on a tab's stack of sign ids: `@jamie`, or `@<their id>`
/// when opened from an id link to their page.
public enum PlayerPath {
  public static func of(_ handle: String) -> String { "@" + handle }
  public static func handle(_ id: String) -> String? { id.hasPrefix("@") ? String(id.dropFirst()) : nil }
}

/// A roadsignmath.xyz link the app was opened with (not the sign-in
/// email's, which `SignInLink` reads): a sign's page opens that sign, a
/// player's page that player, anything else Home.
public enum AppLink: Hashable, Sendable {
  case sign(String)
  case player(String)
  case home

  public init(_ url: URL) {
    let parts = url.pathComponents.filter { $0 != "/" }
    if parts.count == 2, parts[0] == "signs", !parts[1].isEmpty {
      self = .sign(PageKey.normalized(parts[1]))
    } else if parts.count == 2, parts[0] == "players", !parts[1].isEmpty {
      self = .player(PageKey.normalized(parts[1]))
    } else {
      self = .home
    }
  }

  /// Home's stack for it: the sign or player on its own, or nothing (Home
  /// as it is) for any other link.
  public var homePath: [String]? {
    switch self {
    case .sign(let key): [key]
    case .player(let key): [PlayerPath.of(key)]
    case .home: nil
    }
  }

  /// What's over Home when a link arrives.
  public struct Covers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// Capture, at any step.
    public static let capture = Covers(rawValue: 1)
    /// The sign-in screen: the first-run cover, or a sign-in under way.
    public static let signIn = Covers(rawValue: 2)
    /// A sheet: You, a report, "Find another way", a badge.
    public static let sheet = Covers(rawValue: 4)
  }

  /// What gets out of the way, in order, so the linked page shows.
  public enum Clearing: Hashable, Sendable {
    /// Capture steps aside keeping its shot, its step and what's written,
    /// so the camera button opens it where it was.
    case captureAside
    /// The sign-in screen closes as "Look around first" would; an email
    /// waiting for its code still waits.
    case closeSignIn
    /// Sheets that can close for a link close (`closesForSnap`).
    case closeSheets
  }

  /// What clears for a link, given what's up. Capture closing takes what
  /// it presents with it.
  public static func clearing(_ up: Covers) -> [Clearing] {
    var steps: [Clearing] = []
    if up.contains(.capture) { steps.append(.captureAside) }
    if up.contains(.signIn) { steps.append(.closeSignIn) }
    if up.contains(.sheet), !up.contains(.capture) { steps.append(.closeSheets) }
    return steps
  }
}
