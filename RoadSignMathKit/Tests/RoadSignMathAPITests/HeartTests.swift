import Foundation
import Testing

@testable import RoadSignMathAPI

/// Hearts: a sign's count and yours, giving and taking back a heart, and
/// reads that carry your token so they can say which you hearted. The
/// requests go to a stub, never a server.
@Suite struct HeartTests {
  @Test func heartsAndTakesBack() async throws {
    let stub = Stub(status: 200, body: #"{"hearted":true,"hearts":7}"#)
    let given = try await stub.client.heart("01sign", true, token: "rsm_x")
    _ = try await stub.client.heart("01sign", false, token: "rsm_x")
    #expect(given == HeartState(hearted: true, hearts: 7))
    #expect(stub.requests.map(\.method) == ["PUT", "DELETE"])
    #expect(stub.requests.allSatisfy { $0.path == "/api/v1/signs/01sign/heart" && $0.authorization == "Bearer rsm_x" })
  }

  @Test func anUncountedHeartHasNoCount() async throws {
    let stub = Stub(status: 200, body: #"{"hearted":false,"hearts":null}"#)
    let state = try await stub.client.heart("01sign", false, token: "rsm_x")
    #expect(state == HeartState(hearted: false, hearts: nil))
  }

  @Test func aHeartThatCouldNotBeCountedIsA503() async throws {
    let stub = Stub(status: 503, body: #"{"error":{"code":"unavailable","message":"Hearts couldn’t be counted just now."}}"#)
    let error = await #expect(throws: APIError.self) { try await stub.client.heart("01sign", true, token: "rsm_x") }
    #expect(error?.status == 503)
    #expect(error?.code == "unavailable")
  }

  @Test func readsCarryTheTokenOnlyWhenGiven() async throws {
    let stub = Stub(status: 200, body: #"{"signs":[],"next_cursor":null}"#)
    _ = try await stub.client.signs(limit: 20)
    _ = try await stub.client.signs(limit: 20, token: "rsm_x")
    #expect(stub.requests.map(\.authorization) == [nil, "Bearer rsm_x"])
  }

  @Test func aSignSaysItsHearts() throws {
    let json = #"""
      {"id":"01s","slug":"s","title":"S","url":"https://roadsignmath.xyz/signs/s","found_on":"2025-09-01",
       "posted_at":"2025-09-02T01:00:00Z","place":{"label":"Ames, IA","approximate":true},"photos":[],
       "finders":[],"way_count":0,"visibility":"shown","hearts":12,"hearted":true}
      """#
    let sign: Sign = try APIClient.answer(Data(json.utf8), status: 200)
    #expect(sign.hearts == 12)
    #expect(sign.hearted == true)
    // An older server, or a read without a token, says nothing of yours.
    let plain: Sign = try APIClient.answer(Data(json.replacingOccurrences(of: #","hearts":12,"hearted":true"#, with: "").utf8), status: 200)
    #expect(plain.hearts == nil)
    #expect(plain.hearted == nil)
  }
}
