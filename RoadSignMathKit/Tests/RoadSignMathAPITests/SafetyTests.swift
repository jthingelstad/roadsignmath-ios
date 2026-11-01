import Foundation
import Testing

@testable import RoadSignMathAPI

/// Reporting a sign, blocking and unblocking a player, the players you
/// blocked, and deleting a sign you posted. The requests go to a stub,
/// never a server.
@Suite struct SafetyTests {
  @Test func reportsWithAReason() async throws {
    let stub = Stub(status: 200, body: #"{"outcome":"hidden","note":"It shows a rude gesture."}"#)
    let answer = try await stub.client.report("01sign", reason: "Inappropriate: a rude gesture", token: "rsm_x")
    #expect(answer == ReportOutcome(outcome: .hidden, note: "It shows a rude gesture."))
    let sent = try #require(stub.requests.first)
    #expect(sent.method == "POST")
    #expect(sent.path == "/api/v1/signs/01sign/report")
    #expect(sent.authorization == "Bearer rsm_x")
    #expect(sent.body == ["reason": "Inappropriate: a rude gesture"])
  }

  @Test func aReportKeepsToTheLimit() async throws {
    let stub = Stub(status: 200, body: #"{"outcome":"kept","note":"It's a road sign."}"#)
    let answer = try await stub.client.report("01sign", reason: String(repeating: "a", count: 400), token: "rsm_x")
    #expect(answer.outcome == .kept)
    #expect(stub.requests.first?.body?["reason"]?.count == APIClient.reportMax)
  }

  @Test func aReportTheModeratorCouldNotAnswerIsA503() async throws {
    let stub = Stub(status: 503, body: #"{"error":{"code":"unavailable","message":"Try again in a minute."}}"#)
    let error = await #expect(throws: APIError.self) { try await stub.client.report("01sign", reason: "Inappropriate", token: "rsm_x") }
    #expect(error?.code == "unavailable")
  }

  @Test func blocksAndUnblocks() async throws {
    let stub = Stub(status: 204, body: "")
    try await stub.client.block("sam", token: "rsm_x")
    try await stub.client.unblock("sam", token: "rsm_x")
    #expect(stub.requests.map(\.method) == ["POST", "DELETE"])
    #expect(stub.requests.allSatisfy { $0.path == "/api/v1/players/sam/block" && $0.authorization == "Bearer rsm_x" })
  }

  @Test func readsTheBlockedPlayers() async throws {
    let stub = Stub(status: 200, body: #"{"players":[{"handle":"sam","name":"Sam"}]}"#)
    let blocked = try await stub.client.blocks(token: "rsm_x")
    #expect(blocked == [BlockedPlayer(handle: "sam", name: "Sam")])
    #expect(stub.requests.first?.path == "/api/v1/me/blocks")
  }

  @Test func deletesASign() async throws {
    let stub = Stub(status: 204, body: "")
    try await stub.client.deleteSign("01sign", token: "rsm_x")
    #expect(stub.requests.first?.method == "DELETE")
    #expect(stub.requests.first?.path == "/api/v1/signs/01sign")
  }

  @Test func aDeleteThatCouldNotFinishIsA503() async throws {
    let stub = Stub(status: 503, body: #"{"error":{"code":"unavailable","message":"Try again in a minute."}}"#)
    let error = await #expect(throws: APIError.self) { try await stub.client.deleteSign("01sign", token: "rsm_x") }
    #expect(error?.status == 503)
  }
}
