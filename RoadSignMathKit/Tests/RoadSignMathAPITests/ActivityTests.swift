import Foundation
import Testing

@testable import RoadSignMathAPI

/// "On your signs": reading `GET /me/activity`, gathering it into rows and
/// saying when. The requests go to a stub, never a server.
@Suite struct ActivityTests {
  /// Friday 2025-10-31, 8 PM Central.
  let now = Date(timeIntervalSince1970: 1_761_958_800)

  /// Central time, US English, Gregorian: the days don't move with the
  /// Mac running the tests.
  var central: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    calendar.locale = Locale(identifier: "en_US")
    return calendar
  }

  func hoursBefore(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

  let gantry = ActivityItem.SignRef(id: "01sign", slug: "i-35w-at-82nd-street", title: "I-35W at 82nd Street")
  let cancel = ActivityItem.SignRef(id: "02sign", slug: "cancel-it-all-out", title: "Cancel it all out")

  func heart(_ name: String?, on sign: ActivityItem.SignRef, _ hours: Double) -> ActivityItem {
    ActivityItem(kind: .heart, at: hoursBefore(hours), sign: sign, player: .init(handle: name?.lowercased(), name: name))
  }

  @Test func readsWhatsNewWithYourToken() async throws {
    let stub = Stub(status: 200, body: """
      {"days":30,"items":[
        {"kind":"way","at":"2025-11-01T00:00:00.000Z",
         "sign":{"id":"01sign","slug":"i-35w-at-82nd-street","title":"I-35W at 82nd Street","photo_thumb_url":"https://roadsignmath.xyz/photos/01ph/thumb"},
         "player":{"handle":"jamie","name":"Jamie","avatar_color":"#006348","avatar_thumb_url":null},
         "way":{"id":"01way","text":"90-82-8+6=10-7+2+1","tex":"90-82-8+6=10-7+2+1"}},
        {"kind":"heart","at":"2025-10-30T18:00:00.000Z",
         "sign":{"id":"02sign","slug":"cancel-it-all-out","title":"Cancel it all out","photo_thumb_url":null},
         "player":{"handle":null,"name":null,"avatar_color":"#004C80","avatar_thumb_url":null},
         "way":null},
        {"kind":"cheer","at":"2025-10-30T12:00:00.000Z",
         "sign":{"id":"02sign","slug":"cancel-it-all-out","title":"Cancel it all out","photo_thumb_url":null},
         "player":{"handle":"sam","name":"Sam","avatar_color":"#004C80","avatar_thumb_url":null},
         "way":null}
      ]}
      """)
    let activity = try await stub.client.myActivity(token: "rsm_x")
    #expect(stub.requests.first?.method == "GET")
    #expect(stub.requests.first?.path == "/api/v1/me/activity")
    #expect(stub.requests.first?.authorization == "Bearer rsm_x")
    #expect(activity.days == 30)
    #expect(activity.items.map(\.kind) == [.way, .heart, .other])
    #expect(activity.items[0].way?.text == "90-82-8+6=10-7+2+1")
    #expect(activity.items[0].sign.photoThumbUrl?.absoluteString == "https://roadsignmath.xyz/photos/01ph/thumb")
    #expect(activity.items[1].player.shownName == "Someone")
    // A kind this app doesn't know is no row.
    #expect(ActivityRow.rows(activity.items, seen: nil).count == 2)
  }

  @Test func heartsOnOneSignGatherIntoARow() {
    let way = ActivityItem(kind: .way, at: hoursBefore(2), sign: gantry, player: .init(handle: "jamie", name: "Jamie"),
                           way: .init(id: "01way", text: "1+1=2", tex: "1+1=2"))
    let items = [way, heart("Pat", on: cancel, 20), heart("Sam", on: gantry, 22), heart("Lee", on: cancel, 30),
                 heart(nil, on: cancel, 40)]
    let rows = ActivityRow.rows(items, seen: hoursBefore(100))
    #expect(rows.map(\.id) == ["way:01way", "hearts:02sign:new", "hearts:01sign:new"])
    #expect(rows[1].who == "Pat and 2 others")
    #expect(rows[1].at == hoursBefore(20))
    #expect(rows[2].who == "Sam")
    #expect(rows.map(\.new) == [true, true, true])
  }

  @Test func newHeartsStayApartFromOnesSeenBefore() {
    let items = [heart("Pat", on: cancel, 1), heart("Sam", on: cancel, 30)]
    let rows = ActivityRow.rows(items, seen: hoursBefore(10))
    #expect(rows.map(\.id) == ["hearts:02sign:new", "hearts:02sign:seen"])
    #expect(rows.map(\.new) == [true, false])
  }

  @Test func twoNamesAndSomeone() {
    let rows = ActivityRow.rows([heart("Pat", on: cancel, 1), heart(nil, on: cancel, 2)], seen: nil)
    #expect(rows.first?.who == "Pat and someone")
    let flipped = ActivityRow.rows([heart(nil, on: cancel, 1), heart("Pat", on: cancel, 2)], seen: nil)
    #expect(flipped.first?.who == "Someone and Pat")
  }

  @Test func theFirstReadArrivesSeen() {
    let activity = MyActivity(items: [heart("Pat", on: cancel, 1)])
    // Nothing seen on this phone yet: no dot on day one.
    #expect(!activity.hasNew(since: nil))
    #expect(ActivityRow.rows(activity.items, seen: nil).map(\.new) == [false])
    #expect(activity.hasNew(since: hoursBefore(2)))
    #expect(!activity.hasNew(since: hoursBefore(1)))
    #expect(!MyActivity(items: []).hasNew(since: .distantPast))
  }

  @Test func whenInWords() {
    #expect(ActivityRow.when(now.addingTimeInterval(-20), now: now, calendar: central) == "now")
    #expect(ActivityRow.when(hoursBefore(0.25), now: now, calendar: central) == "15m")
    #expect(ActivityRow.when(hoursBefore(2), now: now, calendar: central) == "2h")
    // 9 PM Thursday is yesterday, though under a day ago.
    #expect(ActivityRow.when(hoursBefore(23), now: now, calendar: central) == "Yesterday")
    #expect(ActivityRow.when(hoursBefore(4 * 24), now: now, calendar: central) == "Oct 27")
    #expect(ActivityRow.when(hoursBefore(365 * 24), now: now, calendar: central) == "Oct 31, 2024")
    // Just after midnight, a few minutes before is still minutes.
    let earlyMorning = Date(timeIntervalSince1970: 1_761_973_500)  // Saturday 00:05 Central
    #expect(ActivityRow.when(earlyMorning.addingTimeInterval(-600), now: earlyMorning, calendar: central) == "10m")
  }
}
