import Foundation
import Testing

@testable import RoadSignMathAPI

/// Posting's calls: the photo sent as itself, the post as the server's
/// SignPost with its Idempotency-Key, and the similar signs. The requests
/// go to a stub, never a server.
@Suite struct PostingCallTests {
  func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources"))
    return String(decoding: try Data(contentsOf: url), as: UTF8.self)
  }

  @Test func uploadsThePhotoAsItIs() async throws {
    let stub = Stub(status: 201, body: #"{"id":"01up","width":2048,"height":1536}"#)
    let photo = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
    let upload = try await stub.client.uploadPhoto(photo, token: "rsm_x")
    #expect(upload == Upload(id: "01up", width: 2048, height: 1536))
    let sent = try #require(stub.requests.first)
    #expect(sent.method == "POST")
    #expect(sent.path == "/api/v1/photos")
    #expect(sent.authorization == "Bearer rsm_x")
    #expect(sent.headers["Content-Type"] == "image/jpeg")
    #expect(sent.data == photo)
  }

  @Test func postsWithTheKeyAndTheServersShape() async throws {
    let stub = Stub(status: 201, body: try fixture("sign"))
    let post = SignPost(
      photoIds: ["01up"], title: "Bloomington Math",
      numbers: [PostNumber(value: "8", text: "EXIT 8", why: "Letters dropped", box: [0.1, 0.2, 0.05, 0.04]), PostNumber(value: "82")],
      place: PostPlace(label: "Bloomington, MN", state: "MN", lat: 44.857, lng: -93.29, approximate: false),
      foundOn: "2025-09-01", way: "90 − 82 = 8")
    let detail = try await stub.client.postSign(post, key: "rsm-key-123", token: "rsm_x")
    #expect(detail.sign.slug == "i-35w-at-82nd-street")
    let sent = try #require(stub.requests.first)
    #expect(sent.method == "POST")
    #expect(sent.path == "/api/v1/signs")
    #expect(sent.headers["Idempotency-Key"] == "rsm-key-123")
    #expect(sent.headers["Content-Type"] == "application/json")
    let body = try #require(sent.data)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(Set(json.keys) == ["photo_ids", "title", "numbers", "place", "found_on", "way"])
    #expect(json["photo_ids"] as? [String] == ["01up"])
    #expect(json["found_on"] as? String == "2025-09-01")
    let numbers = try #require(json["numbers"] as? [[String: Any]])
    #expect(Set(numbers[0].keys) == ["value", "text", "why", "box"])
    // Nothing the server didn't ask for: a number with only a value sends
    // only its value.
    #expect(Set(numbers[1].keys) == ["value"])
    let place = try #require(json["place"] as? [String: Any])
    #expect(place["label"] as? String == "Bloomington, MN")
    #expect(place["approximate"] as? Bool == false)
  }

  @Test func unsolvedAndAloneLeavesWayAndFindersOut() throws {
    let post = SignPost(
      photoIds: ["01up"], title: "Sign", numbers: [PostNumber(value: "7")],
      place: PostPlace(label: "Ames, IA", approximate: true), foundOn: "2026-10-30")
    let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(post)) as? [String: Any])
    #expect(json["way"] == nil)
    #expect(json["finders"] == nil)
    #expect(json["caption"] == nil)
  }

  @Test func findersAreAHandleOrAName() throws {
    let finders: [PostFinder] = [.player("zoe", .tookPhoto), .named("Tyler", .spotted)]
    let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(finders)) as? [[String: String]])
    #expect(json == [["handle": "zoe", "role": "took_photo"], ["name": "Tyler", "role": "spotted"]])
  }

  @Test func asksForThePopularSigns() async throws {
    let stub = Stub(status: 200, body: try fixture("near"))
    let signs = try await stub.client.popularSigns(token: "rsm_p_secret")
    #expect(!signs.isEmpty)
    let sent = try #require(stub.requests.first)
    #expect(sent.method == "GET")
    #expect(sent.path == "/api/v1/signs/popular")
  }

  @Test func asksForSimilarSigns() async throws {
    let stub = Stub(status: 200, body: try fixture("near"))
    let signs = try await stub.client.similarSigns(latitude: 44.857, longitude: -93.29, numbers: ["90", "82", "8", "7"])
    #expect(!signs.isEmpty)
    #expect(signs[0].miles != nil)
    let sent = try #require(stub.requests.first)
    #expect(sent.method == "GET")
    #expect(sent.path == "/api/v1/signs/similar")
    #expect(sent.authorization == nil)
    let query = try #require(sent.query)
    #expect(query.contains("lat=44.857"))
    #expect(query.contains("lng=-93.29"))
    #expect(query.contains("numbers=90%2C82%2C8%2C7"))
  }

  @Test func addsAWayAsItsText() async throws {
    let stub = Stub(status: 201, body: try fixture("posted"))
    let detail = try await stub.client.addWay("90 − 82 − 8 + 6 = 10 − 7 + 2 + 1", to: "01sign", token: "rsm_x")
    #expect(!detail.ways.isEmpty)
    let sent = try #require(stub.requests.first)
    #expect(sent.method == "POST")
    #expect(sent.path == "/api/v1/signs/01sign/ways")
    #expect(sent.authorization == "Bearer rsm_x")
    #expect(sent.headers["Content-Type"] == "application/json")
    let body = try #require(sent.data)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
    #expect(json == ["text": "90 − 82 − 8 + 6 = 10 − 7 + 2 + 1"])
  }

  @Test func aWaySomeoneFoundIsAConflict() async throws {
    let stub = Stub(status: 409, body: #"{"error":{"code":"conflict","message":"Someone already found that way"}}"#)
    let error = await #expect(throws: APIError.self) {
      _ = try await stub.client.addWay("7 + 12 = 19", to: "01sign", token: "rsm_x")
    }
    #expect(error?.code == "conflict")
    #expect(error?.message == "Someone already found that way")
  }

  @Test func aRefusalIsTheServersWords() async throws {
    let stub = Stub(status: 400, body: #"{"error":{"code":"bad_request","message":"Give your name first"}}"#)
    let post = SignPost(
      photoIds: ["01up"], title: "Sign", numbers: [PostNumber(value: "7")],
      place: PostPlace(label: "Ames, IA", approximate: true), foundOn: "2026-10-30")
    let error = await #expect(throws: APIError.self) {
      _ = try await stub.client.postSign(post, key: "rsm-key-123", token: "rsm_x")
    }
    #expect(error?.message == "Give your name first")
  }
}
