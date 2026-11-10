import Foundation
import Testing

@testable import Posting
@testable import RoadSignMathAPI

/// The outbox on disk across builds: what an earlier build wrote still
/// reads, and a post this build can't read is set aside, never dropped or
/// written over, while the ones it can read still go.
@Suite struct OutboxFolderTests {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-\(UUID().uuidString)")
  var folder: OutboxFolder { OutboxFolder(url: url) }
  var index: URL { url.appendingPathComponent("outbox.json") }

  /// `outbox.json` as builds up to 39 (0.9.0) wrote it: one post in every
  /// state, with and without an upload, a way, finders and badges. A change
  /// to `OutboxItem`, `SignPost` or `PostedSign` has to keep reading it.
  func build39() throws -> Data {
    try Data(contentsOf: #require(Bundle.module.url(forResource: "outbox-build-39", withExtension: "json", subdirectory: "Resources")))
  }

  func put(_ data: Data) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try data.write(to: index)
  }

  /// The posts in a list file, as JSON.
  func posts(in file: URL) throws -> [[String: Any]] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
  }

  func files() -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
  }

  @Test func readsWhatAnEarlierBuildWrote() throws {
    defer { try? FileManager.default.removeItem(at: url) }
    try put(build39())
    let items = folder.load()
    #expect(items.count == 7)
    #expect(items.map(\.post.title) == (1...7).map { "Ames Math \($0)" })
    #expect(items[0].state == .waiting(problem: nil))
    #expect(items[0].key == "rsm-00000000-0000-4000-8000-000000000001")
    #expect(items[0].post.way == "30 − 23 = 7")
    #expect(items[0].post.finders == [.player("zoe", .tookPhoto), .named("Tyler", .spotted)])
    #expect(items[0].post.numbers.first == PostNumber(value: "7", text: "EXIT 7B", why: "Read as 7", box: [0.1, 0.2, 0.3, 0.4]))
    #expect(items[1].state == .waiting(problem: Delivery.offline))
    #expect(items[1].uploadId == "01up1")
    #expect(items[1].unsureSince == Date(timeIntervalSinceReferenceDate: 814_992_931))
    #expect(items[1].attempts == 2)
    #expect(items[2].state == .needsSignIn)
    #expect(items[3].posted?.slug == "ames-math")
    #expect(items[3].posted?.unlocked == nil)
    guard case .held(_, let note) = items[4].state else { Issue.record("not held: \(items[4].state)"); return }
    #expect(note == "A person will look at this one.")
    #expect(items[5].state == .refused("That title is taken."))
    #expect(items[6].posted?.unlocked?.map(\.title) == ["First Sign", "Signs: 5"])
    #expect(items[6].uploadedAt == Date(timeIntervalSinceReferenceDate: 814_993_221.5))
    // Nothing was unreadable, so nothing else was written.
    #expect(files() == ["outbox.json"])
    #expect(try Data(contentsOf: index) == build39())
  }

  @Test func aPostItCannotReadIsSetAsideAndTheRestStillGo() throws {
    defer { try? FileManager.default.removeItem(at: url) }
    // The second post is in a state this build has never heard of, as a
    // newer build might write, and the fifth has lost its post.
    var written = try #require(JSONSerialization.jsonObject(with: build39()) as? [[String: Any]])
    written[1]["state"] = ["scheduled": ["for": 815_000_000]]
    written[4]["post"] = nil
    try put(JSONSerialization.data(withJSONObject: written))
    let photo = Data([7, 7])
    let second = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000002"))
    try folder.savePhoto(photo, for: second)

    let items = folder.load()
    #expect(items.map(\.post.title) == [1, 3, 4, 6, 7].map { "Ames Math \($0)" })
    // The two it couldn't read are kept as they were written, with the photo.
    let aside = try posts(in: folder.unreadable)
    #expect(aside.map { $0["id"] as? String } == ["00000000-0000-4000-8000-000000000002", "00000000-0000-4000-8000-000000000005"])
    #expect((aside[0] as NSDictionary).isEqual(written[1]))
    #expect((aside[1] as NSDictionary).isEqual(written[4]))
    #expect(folder.photo(second) == photo)

    // The app saving its list (a post went, say) doesn't touch them, and
    // loading again doesn't set them aside twice.
    try folder.save(Array(items.dropLast()))
    #expect(folder.load().count == 4)
    #expect(try posts(in: folder.unreadable).count == 2)
  }

  @Test func aBuildThatCanReadItSendsItAfterAll() throws {
    defer { try? FileManager.default.removeItem(at: url) }
    // Set aside by another build: one post this build reads fine, and one
    // it can't either.
    let written = try #require(JSONSerialization.jsonObject(with: build39()) as? [[String: Any]])
    var strange = written[2]
    strange["state"] = ["scheduled": [:]]
    try put(JSONSerialization.data(withJSONObject: [written[0]]))
    try JSONSerialization.data(withJSONObject: [written[1], strange]).write(to: folder.unreadable)

    let items = folder.load()
    #expect(items.map(\.post.title) == ["Ames Math 1", "Ames Math 2"])
    #expect(items[1].uploadId == "01up1")
    // It's in the list on disk now, and only the strange one is still aside.
    #expect(try posts(in: index).count == 2)
    #expect(try posts(in: folder.unreadable).map { $0["id"] as? String } == ["00000000-0000-4000-8000-000000000003"])

    // Stopped between the two writes last time, a post is in both files:
    // it's sent once, and leaves the aside file.
    try JSONSerialization.data(withJSONObject: [written[1], strange]).write(to: folder.unreadable)
    #expect(folder.load().map(\.post.title) == ["Ames Math 1", "Ames Math 2"])
    #expect(try posts(in: folder.unreadable).count == 1)

    // With nothing left aside, the file goes.
    try JSONSerialization.data(withJSONObject: [written[3]]).write(to: folder.unreadable)
    #expect(folder.load().count == 3)
    #expect(files() == ["outbox.json"])
  }

  @Test func aFileThatIsNotAListIsMovedAsideWhole() throws {
    defer { try? FileManager.default.removeItem(at: url) }
    let damaged = Data(#"[{"id":"00000000-0000-4000-8000-000000000001","handle":"zo"#.utf8)
    try put(damaged)
    #expect(folder.load().isEmpty)
    let kept = try #require(files().first { $0.hasPrefix("outbox-damaged-") })
    #expect(try Data(contentsOf: url.appendingPathComponent(kept)) == damaged)
    // The next post starts a new list beside it.
    let item = OutboxItem(
      handle: "zoe",
      post: SignPost(title: "Ames Math", numbers: [], place: PostPlace(label: "Ames, IA", approximate: true), foundOn: "2026-10-30"))
    try folder.save([item])
    #expect(folder.load() == [item])
    #expect(files().contains(kept))
  }

  @Test func whatIsDueSoon() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func item(_ handle: String, in wait: TimeInterval, _ state: OutboxItem.State = .waiting(problem: nil)) -> OutboxItem {
      var item = OutboxItem(
        handle: handle,
        post: SignPost(title: "Ames Math", numbers: [], place: PostPlace(label: "Ames, IA", approximate: true), foundOn: "2026-10-30"),
        now: now)
      item.nextTry = now.addingTimeInterval(wait)
      item.state = state
      return item
    }
    #expect(![OutboxItem]().hasPostDue(for: "zoe", now: now))
    #expect([item("zoe", in: 0)].hasPostDue(for: "zoe", now: now))
    // Someone else's, or with no one signed in, waits for them.
    #expect(![item("pat", in: 0)].hasPostDue(for: "zoe", now: now))
    #expect(![item("zoe", in: 0)].hasPostDue(for: nil, now: now))
    // Backing off: a few seconds is worth staying for, half an hour isn't.
    #expect(![item("zoe", in: 5)].hasPostDue(for: "zoe", now: now))
    #expect([item("zoe", in: 5)].hasPostDue(for: "zoe", within: 10, now: now))
    #expect(![item("zoe", in: 1800)].hasPostDue(for: "zoe", within: 10, now: now))
    // Done, refused or waiting for sign-in: nothing to send.
    let sign = PostedSign(id: "1", slug: "s", title: "S", url: URL(string: "https://roadsignmath.xyz/signs/s")!)
    for state in [OutboxItem.State.needsSignIn, .posted(sign), .held(sign, note: nil), .refused("No")] {
      #expect(![item("zoe", in: 0, state)].hasPostDue(for: "zoe", within: 10, now: now))
    }
  }
}
