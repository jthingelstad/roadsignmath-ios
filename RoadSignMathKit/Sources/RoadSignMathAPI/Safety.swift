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
    try await answer(to: request("POST", ["signs", signId, "report"], body: ["reason": String(reason.prefix(APIClient.reportMax))], token: token))
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

  /// A request whose answer has no body (204), or the server's error.
  func answerEmpty(to request: URLRequest) async throws {
    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    let _: NoBody = try APIClient.answer(status == 204 || data.isEmpty ? Data("{}".utf8) : data, status: status)
  }
}

private struct Blocks: Decodable { var players: [BlockedPlayer] }
private struct NoBody: Decodable {}
