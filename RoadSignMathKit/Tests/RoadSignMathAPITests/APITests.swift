import Foundation
import Testing

@testable import RoadSignMathAPI

/// The fixtures are the live server's answers on 2026-10-30, so the models
/// read what the server really sends.
@Suite struct APITests {
  func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources")))
  }

  @Test func readsAPage() throws {
    let page: SignPage = try APIClient.answer(fixture("signs"), status: 200)
    #expect(page.signs.count == 2)
    #expect(page.nextCursor != nil)
    let sign = try #require(page.signs.first)
    #expect(sign.slug == "i-35w-at-82nd-street")
    #expect(sign.foundOn == "2025-09-01")
    #expect(sign.foundDay == DateComponents(year: 2025, month: 9, day: 1))
    #expect(sign.place.state == "MN")
    #expect(sign.place.approximate)
    #expect(sign.photos.first?.thumbUrl.lastPathComponent == "thumb.jpg")
    #expect(sign.firstWay?.tex == "\\frac{90 - 82}{8} \\times 1 \\times 2 = \\frac{6}{10 - 7}")
    #expect(sign.finders.first?.role == .found)
    #expect(sign.visibility == .shown)
    #expect(sign.numbers?.first(where: { $0.text == "EXIT 7B" })?.why == "Read as 7")
    #expect(sign.postedAt == Date(timeIntervalSince1970: 1_756_771_213))
  }

  @Test func readsASignWithItsWays() throws {
    let detail: SignDetail = try APIClient.answer(fixture("sign"), status: 200)
    #expect(detail.sign.title == "I-35W at 82nd Street")
    #expect(detail.ways.count == detail.sign.wayCount)
    #expect(detail.ways.first?.by?.handle == "tyler")
  }

  @Test func readsTheMap() throws {
    let map: MapPins = try APIClient.answer(fixture("map"), status: 200)
    #expect(map.pins.count == 16)
    #expect(map.years == [2021, 2023, 2025])
    #expect(map.pins.allSatisfy { $0.year != nil })
    let pin = try #require(map.pins.first { $0.slug == "i-35w-at-82nd-street" })
    #expect(pin.placeLabel == "I-35W at 82nd Street, Bloomington, Minnesota")
    #expect(pin.numbers?.contains("82") == true)
    #expect(pin.finders == [PinFinder(name: "Tyler", handle: "tyler")])
  }

  @Test func readsAnOlderServersPins() throws {
    let old = #"{"pins":[{"id":"a","slug":"a","title":"A","url":"https://example.com/signs/a","lat":null,"lng":null,"approximate":false,"state":null,"found_on":"2025-01-02","thumb_url":null}],"years":[2025]}"#
    let map: MapPins = try APIClient.answer(Data(old.utf8), status: 200)
    #expect(map.pins.first?.placeLabel == nil)
    #expect(map.pins.first?.finders == nil)
  }

  @Test func readsPlayersAndNear() throws {
    struct Players: Decodable { var players: [Player] }
    struct Near: Decodable { var signs: [Sign] }
    let players: Players = try APIClient.answer(fixture("players"), status: 200)
    #expect(players.players.map(\.handle).sorted() == ["jamie", "tammy", "tyler"])
    #expect(players.players.allSatisfy { $0.avatarColor.hasPrefix("#") })
    let near: Near = try APIClient.answer(fixture("near"), status: 200)
    #expect(near.signs.first?.miles == 0.5)
  }

  @Test func readsTheServersNo() throws {
    #expect(throws: APIError(status: 404, code: "not_found", message: "No sign by that id")) {
      let _: SignDetail = try APIClient.answer(fixture("error"), status: 404)
    }
    #expect(throws: APIError(status: 502, code: "http_502", message: HTTPURLResponse.localizedString(forStatusCode: 502))) {
      let _: SignDetail = try APIClient.answer(Data("<html>".utf8), status: 502)
    }
  }

  @Test func buildsURLs() {
    let client = APIClient(base: APIClient.local)
    #expect(client.url(["signs", "a b/c"]).absoluteString == "http://localhost:8787/api/v1/signs/a%20b%2Fc")
    #expect(client.url(["signs"], [URLQueryItem(name: "cursor", value: "x+y/="), URLQueryItem(name: "limit", value: "5")]).absoluteString
      == "http://localhost:8787/api/v1/signs?cursor=x%2By%2F%3D&limit=5")
    #expect(APIClient(base: APIClient.live).url(["map"]).absoluteString == "https://roadsignmath.xyz/api/v1/map")
  }
}
