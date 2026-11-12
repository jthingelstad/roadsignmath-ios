import Foundation
import Testing

@testable import RoadSignMathAPI

/// Website and home on a profile (API 1.15.0), reporting a player and
/// leaving a sign's finders, against a stub, never a server.
@Suite struct ProfileTests {
  /// A fixture with some keys set (NSNull for null) and others taken out.
  func fixture(_ name: String, set: [String: Any] = [:], drop: [String] = []) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources"))
    var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    for (key, value) in set { json[key] = value }
    for key in drop { json[key] = nil }
    return String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)
  }

  @Test func readsWebsiteAndHomeOnAPlayer() throws {
    let body = try fixture("player", set: ["website": "https://www.example.com/zoe", "home": "Minneapolis, MN"])
    let player = try APIClient.decoder.decode(Player.self, from: Data(body.utf8))
    #expect(player.website == "https://www.example.com/zoe")
    #expect(player.home == "Minneapolis, MN")
  }

  @Test func anOlderPlayerOrMeHasNone() throws {
    let player = try APIClient.decoder.decode(Player.self, from: Data(try fixture("player", drop: ["website", "home"]).utf8))
    #expect(player.website == nil && player.home == nil)
    let nulls = try fixture("player", set: ["website": NSNull(), "home": NSNull()])
    #expect(try APIClient.decoder.decode(Player.self, from: Data(nulls.utf8)).website == nil)
    let me = try APIClient.decoder.decode(Me.self, from: Data(try fixture("me", drop: ["website", "home"]).utf8))
    #expect(me.website == nil && me.home == nil)
    // A Me saved on the phone before 1.15.0 reads back too.
    let saved = try JSONEncoder().encode(me)
    #expect(try JSONDecoder().decode(Me.self, from: saved).home == nil)
  }

  @Test func setsTheWebsiteAndHome() async throws {
    let stub = Stub(status: 200, body: try fixture("me", set: ["website": "https://example.com/", "home": "Ames, IA"]))
    let me = try await stub.client.updateMe(token: "rsm_x", website: " example.com ")
    #expect(me.website == "https://example.com/")
    _ = try await stub.client.updateMe(token: "rsm_x", home: "Ames, IA\n")
    #expect(stub.requests.map(\.method) == ["PATCH", "PATCH"])
    #expect(stub.requests.allSatisfy { $0.path == "/api/v1/me" && $0.authorization == "Bearer rsm_x" })
    #expect(stub.requests.map(\.body) == [["website": "example.com"], ["home": "Ames, IA"]])
  }

  @Test func emptyTakesThemOffAndLongIsClipped() async throws {
    let stub = Stub(status: 200, body: try fixture("me"))
    _ = try await stub.client.updateMe(token: "rsm_x", website: "  ")
    _ = try await stub.client.updateMe(token: "rsm_x", home: String(repeating: "a", count: 80))
    #expect(stub.requests.first?.body == ["website": ""])
    #expect(stub.requests.last?.body?["home"]?.count == APIClient.homeMax)
  }

  @Test func refusedWordsAndABadAddressSayWhy() async throws {
    let refused = Stub(status: 422, body: #"{"error":{"code":"refused","message":"Our moderator wouldn't show that on your profile."}}"#)
    let error = await #expect(throws: APIError.self) { try await refused.client.updateMe(token: "rsm_x", home: "x") }
    #expect(error?.code == "refused")
    let bad = Stub(status: 400, body: #"{"error":{"code":"bad_request","message":"website must be a web address, like example.com"}}"#)
    let badError = await #expect(throws: APIError.self) { try await bad.client.updateMe(token: "rsm_x", website: "nope") }
    #expect(badError?.status == 400)
  }

  @Test func showsAWebsiteByItsHost() {
    #expect(ProfileWebsite.label("https://www.example.com/zoe") == "example.com")
    #expect(ProfileWebsite.label("http://Blog.Example.org") == "blog.example.org")
    #expect(ProfileWebsite.label("https://www.") == "www.")
    #expect(ProfileWebsite.label("javascript:alert(1)") == nil)
    #expect(ProfileWebsite.label("example.com") == nil)
    #expect(ProfileWebsite.label(nil) == nil)
    #expect(ProfileWebsite.url("https://example.com/a")?.absoluteString == "https://example.com/a")
    #expect(ProfileWebsite.url("mailto:zoe@example.com") == nil)
  }

  @Test func reportsAPlayer() async throws {
    let stub = Stub(status: 200, body: #"{"received":true}"#)
    try await stub.client.reportPlayer("sam", reason: "Inappropriate: the bio", token: "rsm_x")
    let sent = try #require(stub.requests.first)
    #expect(sent.method == "POST")
    #expect(sent.path == "/api/v1/players/sam/report")
    #expect(sent.authorization == "Bearer rsm_x")
    #expect(sent.body == ["reason": "Inappropriate: the bio"])
  }

  @Test func reportingYourselfIsA400() async throws {
    let stub = Stub(status: 400, body: #"{"error":{"code":"bad_request","message":"You can't report yourself"}}"#)
    let error = await #expect(throws: APIError.self) { try await stub.client.reportPlayer("me", reason: "Inappropriate", token: "rsm_x") }
    #expect(error?.status == 400)
  }

  @Test func leavesASign() async throws {
    let stub = Stub(status: 204, body: "")
    try await stub.client.leaveSign("01sign", token: "rsm_x")
    let sent = try #require(stub.requests.first)
    #expect(sent.method == "DELETE")
    #expect(sent.path == "/api/v1/signs/01sign/finders/me")
    #expect(sent.authorization == "Bearer rsm_x")
  }

  @Test func leavingWhileAnotherFinderLeavesIsA409() async throws {
    let stub = Stub(status: 409, body: #"{"error":{"code":"conflict","message":"This sign's finders are changing. Try again."}}"#)
    let error = await #expect(throws: APIError.self) { try await stub.client.leaveSign("01sign", token: "rsm_x") }
    #expect(error?.code == "conflict")
  }
}
