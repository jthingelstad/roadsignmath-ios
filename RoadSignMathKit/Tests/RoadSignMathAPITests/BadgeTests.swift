import Foundation
import Testing

@testable import RoadSignMathAPI

/// Badges (API 1.6.0): the catalog, the earned badges on a player and on
/// you, `unlocked` on a post's answer, the shelves the app draws and the
/// badges seen on this phone. `badges.json` is the live catalog on
/// 2026-10-30; the others are shaped like the server's contract.
@Suite struct BadgeTests {
  func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources")))
  }

  func catalog() throws -> [CatalogBadge] {
    let catalog: BadgeCatalog = try APIClient.answer(fixture("badges"), status: 200)
    return catalog.badges
  }

  func earned(_ id: String, step: Int? = nil, on day: String = "2025-09-01", shelf: BadgeShelf = .math) -> EarnedBadge {
    EarnedBadge(
      id: id, shelf: shelf, name: id, how: "How.", mark: step.map(String.init) ?? "×", step: step, earnedOn: day,
      sign: BadgeSign(id: "01s", slug: "s", title: "S", url: URL(string: "https://roadsignmath.xyz/signs/s")!))
  }

  @Test func readsTheCatalogWithSecretsBlank() throws {
    let badges = try catalog()
    #expect(badges.count == 28)
    #expect(badges.first?.id == "first-sign")
    #expect(badges.first?.name == "First Sign")
    let states = try #require(badges.first { $0.id == "states" })
    #expect(states.shelf == .places)
    #expect(states.steps == [2, 3, 5, 10])
    #expect(states.mark == "")
    let secrets = badges.filter(\.secret)
    #expect(secrets.count == 5)
    #expect(secrets.allSatisfy { $0.shelf == .secret && $0.name == nil && $0.how == nil && $0.mark == nil })
  }

  @Test func asksForTheCatalog() async throws {
    let stub = Stub(status: 200, body: String(decoding: try fixture("badges"), as: UTF8.self))
    let badges = try await stub.client.badges()
    #expect(badges.count == 28)
    #expect(stub.requests.map(\.path) == ["/api/v1/badges"])
    #expect(stub.requests.first?.authorization == nil)
  }

  @Test func anUnknownShelfStillReads() throws {
    let json = #"{"badges":[{"id":"new","shelf":"weather","secret":false,"name":"Rain","how":"A sign in the rain.","mark":"R","steps":null}]}"#
    let catalog: BadgeCatalog = try APIClient.answer(Data(json.utf8), status: 200)
    #expect(catalog.badges.first?.shelf == .other)
  }

  @Test func readsAPlayersAndYourBadges() throws {
    let player: Player = try APIClient.answer(fixture("player"), status: 200)
    let badges = try #require(player.badges)
    #expect(badges.map(\.id) == ["first-sign", "states", "square-root"])
    #expect(badges[1].step == 2)
    #expect(badges[1].title == "States: 2")
    #expect(badges[2].title == "Square Root")
    #expect(badges[0].earnedOn == "2025-08-06")
    #expect(badges[0].sign.slug == "on-the-way-to-the-airport")
    #expect(badges[0].day == DateComponents(year: 2025, month: 8, day: 6))

    let me: Me = try APIClient.answer(fixture("me"), status: 200)
    #expect(me.badges?.count == 3)
    // A Me from before 1.6.0 (the sign-in fixture, or one saved on the
    // phone) has none, and still reads.
    let done: SignedIn = try APIClient.answer(fixture("signed-in"), status: 200)
    #expect(done.me.badges == nil)
    let saved = try JSONEncoder().encode(Me(handle: "z", name: "Z", avatarColor: "#000000", url: URL(string: "https://x.invalid")!, email: "z@example.com", needsName: false))
    #expect(try JSONDecoder().decode(Me.self, from: saved).badges == nil)
  }

  @Test func readsWhatAPostUnlocked() throws {
    let posted: SignDetail = try APIClient.answer(fixture("posted"), status: 201)
    #expect(posted.unlocked.map(\.title) == ["Square Root", "States: 3"])
    // A plain read of a sign has no unlocked.
    let read: SignDetail = try APIClient.answer(fixture("sign"), status: 200)
    #expect(read.unlocked.isEmpty)
  }

  // MARK: Shelves

  @Test func shelvesFollowTheCatalog() throws {
    let shelves = Badges.shelves(catalog: try catalog(), earned: [earned("square-root"), earned("states", step: 3, shelf: .places)])
    #expect(shelves.map(\.shelf) == [.firsts, .places, .math, .seasons, .secret])
    #expect(shelves.map(\.slots.count) == [6, 5, 10, 2, 5])
    let places = shelves[1].slots
    #expect(places[0].earned?.step == 3)
    #expect(places[0].nextStep == 5)
    // Not earned: the first step is the one to reach.
    #expect(places[1].id == "mile-markers")
    #expect(places[1].nextStep == 3)
    #expect(shelves[2].slots.compactMap(\.earned).map(\.id) == ["square-root"])
    #expect(shelves[4].slots.allSatisfy { $0.hidden })
  }

  @Test func theTopStepHasNoNext() throws {
    let shelves = Badges.shelves(catalog: try catalog(), earned: [earned("states", step: 10, shelf: .places)])
    #expect(shelves[1].slots[0].nextStep == nil)
  }

  @Test func anEarnedSecretShowsAndOneTheCatalogLacksIsKept() throws {
    var secret = earned("secret-2", shelf: .secret)
    secret.name = "Route 66"
    let shelves = Badges.shelves(catalog: try catalog(), earned: [secret, earned("brand-new")])
    let route66 = try #require(shelves[4].slots.first { $0.id == "secret-2" })
    #expect(!route66.hidden)
    #expect(route66.earned?.name == "Route 66")
    #expect(shelves[2].slots.last?.id == "brand-new")
    // With no catalog at all, the earned ones still make shelves.
    #expect(Badges.shelves(catalog: [], earned: [secret]).map(\.shelf) == [.secret])
  }

  @Test func newestFirstThenCatalogOrder() {
    let list = [earned("a", on: "2024-01-01"), earned("b", on: "2025-06-01"), earned("c", on: "2025-06-01")]
    #expect(Badges.newest(list).map(\.id) == ["b", "c", "a"])
  }

  // MARK: Seen

  @Test func earnedBeforeArriveSeen() throws {
    let before = [earned("times-table"), earned("states", step: 2, shelf: .places)]
    var seen = SeenBadges(arriving: before)
    #expect(seen.unseen(before).isEmpty)
    // A new badge, and the next step of one already had, are new.
    let after = before + [earned("square-root"), earned("states", step: 3, shelf: .places)]
    #expect(seen.unseen(after).map(SeenBadges.key) == ["square-root", "states:3"])
    seen.see([after[2]])
    #expect(seen.unseen(after).map(SeenBadges.key) == ["states:3"])
    let saved = try JSONDecoder().decode(SeenBadges.self, from: JSONEncoder().encode(seen))
    #expect(saved == seen)
  }
}
