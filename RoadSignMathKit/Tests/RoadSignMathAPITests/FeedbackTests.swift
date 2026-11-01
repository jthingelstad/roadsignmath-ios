import Foundation
import Testing

@testable import RoadSignMathAPI

/// Feedback and the bio, against a stub, never a server.
@Suite struct FeedbackTests {
  /// `me.json` with its bio as given.
  func me(bio: String?) throws -> String {
    let url = try #require(Bundle.module.url(forResource: "me", withExtension: "json", subdirectory: "Resources"))
    var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    json["bio"] = bio ?? NSNull()
    return String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)
  }

  @Test func sendsFeedbackAsJSON() async throws {
    let stub = Stub(status: 202, body: #"{"sent":true}"#)
    try await stub.client.sendFeedback("  The map is great.\n", replyOK: true, app: "Road Sign Math 0.9.0", token: "rsm_x")
    let sent = try #require(stub.requests.first)
    #expect(sent.method == "POST")
    #expect(sent.path == "/api/v1/feedback")
    #expect(sent.authorization == "Bearer rsm_x")
    let data = try #require(sent.data)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["message"] as? String == "The map is great.")
    #expect(json["reply_ok"] as? Bool == true)
    #expect(json["app"] as? String == "Road Sign Math 0.9.0")
  }

  @Test func feedbackKeepsToTheLimitAndLeavesYourEmailOut() async throws {
    let stub = Stub(status: 202, body: #"{"sent":true}"#)
    try await stub.client.sendFeedback(String(repeating: "a", count: 2500), replyOK: false, app: nil, token: "rsm_x")
    let data = try #require(stub.requests.first?.data)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect((json["message"] as? String)?.count == APIClient.feedbackMax)
    #expect(json["reply_ok"] as? Bool == false)
    #expect(json["app"] == nil)
  }

  @Test func feedbackThatDidNotGoIsA503() async throws {
    let stub = Stub(status: 503, body: #"{"error":{"code":"unavailable","message":"The feedback didn't go. Try again in a minute."}}"#)
    let error = await #expect(throws: APIError.self) { try await stub.client.sendFeedback("Hi", replyOK: false, app: nil, token: "rsm_x") }
    #expect(error?.code == "unavailable")
  }

  @Test func setsTheBio() async throws {
    let stub = Stub(status: 200, body: try me(bio: "Driving + Math = Fun."))
    let me = try await stub.client.updateMe(token: "rsm_x", bio: " Driving + Math = Fun. ")
    #expect(me.bio == "Driving + Math = Fun.")
    let sent = try #require(stub.requests.first)
    #expect(sent.method == "PATCH")
    #expect(sent.path == "/api/v1/me")
    #expect(sent.body == ["bio": "Driving + Math = Fun."])
  }

  @Test func anEmptyBioTakesItOff() async throws {
    let stub = Stub(status: 200, body: try me(bio: nil))
    _ = try await stub.client.updateMe(token: "rsm_x", bio: "   ")
    #expect(stub.requests.first?.body == ["bio": ""])
  }
}
