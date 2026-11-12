import Foundation

// Keeping the game pleasant: reporting a sign, blocking a player and
// deleting a sign you posted. All need you signed in.

/// `POST /signs/{id}/report`'s answer: what the moderator decided when it
/// looked again with your reason.
public struct ReportOutcome: Codable, Sendable, Hashable {
  public enum Outcome: String, Codable, Sendable {
    /// It agreed: the sign is off the feed, the map and the website.
    case hidden
    /// It kept the sign up.
    case kept
  }

  public var outcome: Outcome
  /// The moderator's reason, for the player who reported.
  public var note: String

  public init(outcome: Outcome, note: String) {
    self.outcome = outcome
    self.note = note
  }
}

/// `POST /signs/{id}/duplicate`'s answer (API 1.12.0): the other sign's
/// slug and the note kept with it.
public struct DuplicateReceived: Codable, Sendable, Hashable {
  public var sameAs: String
  public var note: String?

  public init(sameAs: String, note: String?) {
    self.sameAs = sameAs
    self.note = note
  }
}

/// A player you blocked, from `GET /me/blocks`.
public struct BlockedPlayer: Codable, Sendable, Hashable, Identifiable {
  public var handle: String
  public var name: String
  public var id: String { handle }

  public init(handle: String, name: String) {
    self.handle = handle
    self.name = name
  }
}

extension APIClient {
  /// The longest reason a report takes.
  public static let reportMax = 300

  /// Reports a sign: the moderator looks at it again with `reason` and
  /// hides it if it agrees. One report per sign; sending another gives
  /// back the first answer. A 503 means the moderator couldn't answer and
  /// nothing changed.
  public func report(_ signId: String, reason: String, token: String) async throws -> ReportOutcome {
    try await answer(to: request("POST", ["signs", signId, "report"], body: ["reason": reason.clipped(to: APIClient.reportMax)], token: token))
  }

  /// Says a sign is the same road sign as another one, posted separately
  /// (`sameAs`, its id or slug), with an optional note. It's kept for
  /// later and changes nothing now; the moderator never sees it. Any sign,
  /// your own too. Sending another replaces your earlier one.
  public func reportDuplicate(_ signId: String, sameAs: String, note: String, token: String) async throws -> DuplicateReceived {
    var body = ["same_as": sameAs]
    let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    if !note.isEmpty { body["note"] = note.clipped(to: APIClient.reportMax) }
    return try await answer(to: request("POST", ["signs", signId, "duplicate"], body: body, token: token))
  }

  /// Blocks a player: their signs and ways are left out of everything you
  /// read. They aren't told.
  public func block(_ handle: String, token: String) async throws {
    try await answerEmpty(to: request("POST", ["players", handle, "block"], token: token))
  }

  /// Unblocks a player: their signs and ways come back.
  public func unblock(_ handle: String, token: String) async throws {
    try await answerEmpty(to: request("DELETE", ["players", handle, "block"], token: token))
  }

  /// The players you blocked.
  public func blocks(token: String) async throws -> [BlockedPlayer] {
    let blocks: Blocks = try await answer(to: request("GET", ["me", "blocks"], token: token))
    return blocks.players
  }

  /// Deletes a sign you posted: its photos, every way on it (other
  /// players' too) and its hearts. A 503 means its hearts couldn't be
  /// removed just now and the sign is still there.
  public func deleteSign(_ signId: String, token: String) async throws {
    try await answerEmpty(to: request("DELETE", ["signs", signId], token: token))
  }

  /// Reports a player to the person who runs Road Sign Math (API 1.15.0),
  /// with your name and handle. The moderator doesn't look and nothing is
  /// hidden. One report per player: sending another changes nothing. A
  /// 400 for yourself; it counts against the day's reports.
  public func reportPlayer(_ handle: String, reason: String, token: String) async throws {
    let _: PlayerReportReceived = try await answer(
      to: request("POST", ["players", handle, "report"], body: ["reason": reason.clipped(to: APIClient.reportMax)], token: token))
  }

  /// Takes you off a sign's finders (API 1.15.0): a sign that credits you
  /// and someone else posted. Your ways on it stay yours; when you were
  /// its only finder, its poster is credited instead. A 400 for a sign you
  /// posted (delete it instead), and a 409 `conflict` when another finder
  /// is leaving it just now: try again.
  public func leaveSign(_ signId: String, token: String) async throws {
    try await answerEmpty(to: request("DELETE", ["signs", signId, "finders", "me"], token: token))
  }

  /// A request whose answer has no body (204), or the server's error.
  func answerEmpty(to request: URLRequest) async throws {
    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    let _: NoBody = try APIClient.answer(status == 204 || data.isEmpty ? Data("{}".utf8) : data, status: status)
  }
}

private struct Blocks: Decodable { var players: [BlockedPlayer] }
private struct PlayerReportReceived: Decodable { var received: Bool? }
private struct NoBody: Decodable {}
