import Foundation
import Synchronization
import Testing

@testable import Posting
@testable import RoadSignMathAPI

/// The outbox's tries: upload then post with one key, what each kind of
/// failure does next, and the folder on disk. The sender is a fake that
/// answers as told, never a server.
@Suite struct OutboxTests {
  let start = Date(timeIntervalSince1970: 1_800_000_000)

  /// One post, the same one all through a test.
  let item: OutboxItem

  init() {
    item = OutboxItem(
      handle: "zoe",
      post: SignPost(
        title: "Ames Math", numbers: [PostNumber(value: "7")], place: PostPlace(label: "Ames, IA", approximate: true),
        foundOn: "2026-10-30"),
      now: start)
  }

  @Test func uploadsThenPostsWithItsKey() async throws {
    let fake = Fake()
    let sent = await Delivery.attempt(item, photo: Data([1, 2]), sender: fake.sender, now: { [start] in start })
    #expect(sent.posted?.slug == "ames-math")
    #expect(sent.state == .posted(PostedSign(id: "01sign", slug: "ames-math", title: "Ames Math", url: URL(string: "https://roadsignmath.xyz/signs/ames-math")!)))
    #expect(fake.uploads == [Data([1, 2])])
    #expect(fake.posts.map(\.1) == [item.key])
    #expect(fake.posts.first?.0.photoIds == ["01up1"])
    #expect(item.key.count >= 8 && item.key.count <= 128)
  }

  @Test func aPostKeepsTheBadgesItEarned() async throws {
    let fake = Fake(unlocked: """
      [{"id":"first-sign","shelf":"firsts","name":"First Sign","how":"Post your first sign.","mark":"1ST","step":null,
        "earned_on":"2026-10-30","sign":{"id":"01sign","slug":"ames-math","title":"Ames Math","url":"https://roadsignmath.xyz/signs/ames-math"}}]
      """)
    let sent = await Delivery.attempt(item, photo: Data([1]), sender: fake.sender)
    #expect(sent.posted?.unlocked?.map(\.title) == ["First Sign"])
    // Kept on disk with the post, so Home can say it after a relaunch.
    let saved = try JSONDecoder().decode(OutboxItem.self, from: JSONEncoder().encode(sent))
    #expect(saved.posted?.unlocked?.first?.earnedOn == "2026-10-30")
    // An outbox saved before badges still reads.
    let old = #"{"id":"01sign","slug":"ames-math","title":"Ames Math","url":"https://roadsignmath.xyz/signs/ames-math"}"#
    #expect(try JSONDecoder().decode(PostedSign.self, from: Data(old.utf8)).unlocked == nil)
  }

  @Test func aHeldPostSaysTheNote() async throws {
    let fake = Fake(visibility: "held", note: "A person will look at this one.")
    let sent = await Delivery.attempt(item, photo: Data([1]), sender: fake.sender)
    guard case .held(let sign, let note) = sent.state else { Issue.record("not held: \(sent.state)"); return }
    #expect(sign.slug == "ames-math")
    #expect(note == "A person will look at this one.")
  }

  @Test func offlineWaitsAndTriesAgainWithTheSameUpload() async throws {
    let fake = Fake()
    fake.failPosts([URLError(.notConnectedToInternet)])
    let first = await Delivery.attempt(item, photo: Data([1]), sender: fake.sender, now: { [start] in start })
    #expect(first.state == .waiting(problem: Delivery.offline))
    #expect(first.nextTry == start.addingTimeInterval(5))
    #expect(first.uploadId == "01up1")
    #expect(!first.isDue(at: start))
    #expect(first.isDue(at: start.addingTimeInterval(5)))

    let second = await Delivery.attempt(first, photo: Data([1]), sender: fake.sender, now: { [start] in start })
    #expect(second.posted != nil)
    // One upload, and the same key both times: one sign.
    #expect(fake.uploads.count == 1)
    #expect(fake.posts.map(\.1) == [item.key, item.key])
  }

  @Test func aBusyServerBacksOff() async throws {
    let fake = Fake()
    fake.failPosts(Array(repeating: APIError(status: 503, code: "unavailable", message: "Our moderator couldn’t look just now."), count: 3))
    var next = item
    var waits: [TimeInterval] = []
    for _ in 0..<3 {
      next = await Delivery.attempt(next, photo: Data([1]), sender: fake.sender, now: { [start] in start })
      waits.append(next.nextTry.timeIntervalSince(start))
      guard case .waiting(let problem) = next.state else { Issue.record("not waiting"); return }
      #expect(problem?.contains("try again on its own") == true)
    }
    #expect(waits == [5, 15, 60])
    #expect(Backoff.delay(after: 40) == 1800)
  }

  @Test func aRefusalIsSaidInTheServersWords() async throws {
    let fake = Fake()
    fake.failPosts([APIError(status: 400, code: "bad_request", message: "9 isn’t on the sign that often")])
    let sent = await Delivery.attempt(item, photo: Data([1]), sender: fake.sender)
    #expect(sent.state == .refused("9 isn’t on the sign that often"))
    #expect(!sent.isWaiting)
  }

  @Test func signedOutWaitsForThePlayer() async throws {
    let fake = Fake()
    fake.failUploads([SignedOut()])
    let sent = await Delivery.attempt(item, photo: Data([1]), sender: fake.sender)
    #expect(sent.state == .needsSignIn)
    #expect(sent.isWaiting)
    #expect(!sent.isDue(at: .distantFuture))
    var back = sent
    back.retry(now: start)
    #expect(back.isDue(at: start))
  }

  @Test func tooManyTodayWaitsAnHour() async throws {
    let fake = Fake()
    fake.failPosts([APIError(status: 429, code: "rate_limited", message: "Too many posts today. Try again tomorrow.")])
    let sent = await Delivery.attempt(item, photo: Data([1]), sender: fake.sender, now: { [start] in start })
    #expect(sent.state == .waiting(problem: "Too many posts today. Try again tomorrow."))
    #expect(sent.nextTry == start.addingTimeInterval(3600))
  }

  @Test func aLostUploadIsSentAgainOnce() async throws {
    let fake = Fake()
    let gone = APIError(status: 400, code: "bad_request", message: "Photo 01up1 isn’t one of your uploads, or it waited too long")
    var waiting = item
    waiting.uploadId = "01up1"
    waiting.uploadedAt = start
    fake.failPosts([gone])
    // The old upload is refused: the photo goes again at once.
    let again = await Delivery.attempt(waiting, photo: Data([1]), sender: fake.sender, now: { [start] in start })
    #expect(again.uploadId == nil)
    #expect(again.isDue(at: start))
    let posted = await Delivery.attempt(again, photo: Data([1]), sender: fake.sender, now: { [start] in start })
    #expect(posted.posted != nil)
    #expect(fake.uploads.count == 1)

    // Refused the same way just after a fresh upload: said, not looped.
    fake.failPosts([gone])
    let refused = await Delivery.attempt(item, photo: Data([1]), sender: fake.sender)
    #expect(refused.state == .refused(gone.message))
  }

  @Test func anOldUploadIsSentAgain() async throws {
    let fake = Fake()
    var old = item
    old.uploadId = "01old"
    old.uploadedAt = start
    let later = start.addingTimeInterval(21 * 3600)
    let sent = await Delivery.attempt(old, photo: Data([1]), sender: fake.sender, now: { later })
    #expect(fake.uploads.count == 1)
    #expect(fake.posts.first?.0.photoIds == ["01up1"])
    #expect(sent.posted != nil)
  }

  @Test func aStillBeingMadePostTriesAgainSoon() async throws {
    let fake = Fake()
    fake.failPosts([APIError(status: 409, code: "conflict", message: "That post is still being made. Try again in a moment.")])
    let sent = await Delivery.attempt(item, photo: Data([1]), sender: fake.sender, now: { [start] in start })
    #expect(sent.nextTry == start.addingTimeInterval(5))
    #expect(sent.isWaiting)
  }

  @Test func aMissingPhotoIsSaid() async throws {
    let sent = await Delivery.attempt(item, photo: nil, sender: Fake().sender)
    guard case .refused = sent.state else { Issue.record("not refused"); return }
  }

  @Test func anUnansweredPostThatMadeItsSignIsFoundNotSentAgain() async throws {
    let fake = Fake()
    fake.failPosts([URLError(.timedOut)])
    let first = await Delivery.attempt(item, photo: Data([1]), sender: fake.sender, now: { [start] in start })
    #expect(first.unsureSince == start)
    #expect(first.isWaiting)

    // The server made it before the connection dropped. Days later, the
    // next try finds it on the poster's page and posts nothing.
    fake.madeOnServer("01up1")
    let late = start.addingTimeInterval(3 * 86400)
    let found = await Delivery.attempt(first, photo: Data([1]), sender: fake.sender, now: { late })
    #expect(found.posted?.slug == "ames-math")
    // Found on the page, which doesn't say what that post earned.
    #expect(found.posted?.unlocked == nil)
    #expect(fake.posts.count == 1)
    #expect(fake.looks.map { "\($0.0) \($0.1)" } == ["zoe 01up1"])
  }

  @Test func anUnansweredPostThatMadeNothingIsSentAgain() async throws {
    let fake = Fake()
    fake.failPosts([URLError(.networkConnectionLost)])
    let first = await Delivery.attempt(item, photo: Data([1]), sender: fake.sender, now: { [start] in start })
    let late = start.addingTimeInterval(3 * 86400)
    let again = await Delivery.attempt(first, photo: Data([1]), sender: fake.sender, now: { late })
    #expect(again.posted != nil)
    #expect(again.unsureSince == nil)
    #expect(fake.looks.count == 1)
    #expect(fake.posts.count == 2)
  }

  @Test func aLookThatFailsWaitsAndLooksAgain() async throws {
    let fake = Fake()
    fake.failPosts([URLError(.timedOut)])
    fake.failLooks([URLError(.notConnectedToInternet)])
    let first = await Delivery.attempt(item, photo: Data([1]), sender: fake.sender, now: { [start] in start })
    let offline = await Delivery.attempt(first, photo: Data([1]), sender: fake.sender, now: { [start] in start })
    #expect(offline.state == .waiting(problem: Delivery.offline))
    #expect(offline.unsureSince == start)
    #expect(fake.posts.count == 1)

    fake.madeOnServer("01up1")
    let found = await Delivery.attempt(offline, photo: Data([1]), sender: fake.sender, now: { [start] in start })
    #expect(found.posted != nil)
    #expect(fake.posts.count == 1)
  }

  @Test func onlyAPostThatMayHaveGoneIsUnsure() async throws {
    #expect(Delivery.Outcome.unanswered(URLError(.timedOut)))
    #expect(Delivery.Outcome.unanswered(APIError(status: 504, code: "http_504", message: "Gateway Timeout")))
    #expect(Delivery.Outcome.unanswered(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "cut off"))))
    #expect(!Delivery.Outcome.unanswered(URLError(.notConnectedToInternet)))
    #expect(!Delivery.Outcome.unanswered(APIError(status: 503, code: "unavailable", message: "Our moderator couldn’t look just now.")))
    #expect(!Delivery.Outcome.unanswered(APIError(status: 400, code: "bad_request", message: "no")))

    // Offline for days never stops a post: it never left the phone.
    let fake = Fake()
    fake.failPosts([URLError(.notConnectedToInternet)])
    let first = await Delivery.attempt(item, photo: Data([1]), sender: fake.sender, now: { [start] in start })
    #expect(first.unsureSince == nil)
  }

  @Test func theFolderKeepsPostsAndPhotos() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    let folder = OutboxFolder(url: url)
    #expect(folder.load().isEmpty)
    var held = item
    held.state = .held(PostedSign(id: "1", slug: "s", title: "S", url: URL(string: "https://roadsignmath.xyz/signs/s")!), note: "Looking")
    try folder.save([item, held])
    try folder.savePhoto(Data([9, 9]), for: item.id)
    let again = OutboxFolder(url: url)
    #expect(again.load() == [item, held])
    #expect(again.photo(item.id) == Data([9, 9]))
    again.removePhoto(item.id)
    #expect(again.photo(item.id) == nil)
  }
}

/// A sender that answers as told: uploads get ids `01up1`, `01up2`…, and
/// posts make the sign "Ames Math"; queued errors are thrown first.
final class Fake: Sendable {
  private struct Log {
    var uploads: [Data] = []
    var posts: [(SignPost, String)] = []
    var uploadErrors: [any Error] = []
    var postErrors: [any Error] = []
    var lookErrors: [any Error] = []
    var looks: [(String, String)] = []
    /// Photos whose post the server made, though its answer may never have come.
    var made: [String: SignPost] = [:]
  }

  private let log = Mutex(Log())
  let visibility: String
  let note: String?
  /// The post answer's `unlocked`, as JSON.
  let unlocked: String

  init(visibility: String = "shown", note: String? = nil, unlocked: String = "[]") {
    self.visibility = visibility
    self.note = note
    self.unlocked = unlocked
  }

  var uploads: [Data] { log.withLock { $0.uploads } }
  var posts: [(SignPost, String)] { log.withLock { $0.posts } }
  func failUploads(_ errors: [any Error]) { log.withLock { $0.uploadErrors = errors } }
  func failPosts(_ errors: [any Error]) { log.withLock { $0.postErrors = errors } }
  func failLooks(_ errors: [any Error]) { log.withLock { $0.lookErrors = errors } }
  var looks: [(String, String)] { log.withLock { $0.looks } }
  /// Says the last post with this photo made its sign on the server.
  func madeOnServer(_ photoId: String) {
    log.withLock { log in log.made[photoId] = log.posts.last { $0.0.photoIds.contains(photoId) }?.0 }
  }

  var sender: OutboxSender {
    OutboxSender(
      upload: { data in
        try self.log.withLock { log in
          if !log.uploadErrors.isEmpty { throw log.uploadErrors.removeFirst() }
          log.uploads.append(data)
          return Upload(id: "01up\(log.uploads.count)", width: 2048, height: 1536)
        }
      },
      post: { post, key in
        try self.log.withLock { log in
          log.posts.append((post, key))
          if !log.postErrors.isEmpty { throw log.postErrors.removeFirst() }
        }
        return try self.detail(post, unlocked: self.unlocked)
      },
      find: { handle, photoId in
        let post = try self.log.withLock { log in
          log.looks.append((handle, photoId))
          if !log.lookErrors.isEmpty { throw log.lookErrors.removeFirst() }
          return log.made[photoId]
        }
        return try post.map { try self.detail($0).sign }
      })
  }

  func detail(_ post: SignPost, unlocked: String = "[]") throws -> SignDetail {
    let note = note.map { "\"\($0)\"" } ?? "null"
    let json = """
      {"id":"01sign","slug":"ames-math","title":"\(post.title)","url":"https://roadsignmath.xyz/signs/ames-math",
       "caption":null,"found_on":"\(post.foundOn)","posted_at":"2026-10-30T12:00:00.000Z","posted_by":"zoe",
       "place":{"label":"Ames, IA","state":"IA","lat":null,"lng":null,"approximate":true},
       "photos":[],"numbers":[{"value":"7"}],"finders":[{"name":"Zoë","handle":"zoe","role":"found"}],
       "first_way":null,"way_count":0,"visibility":"\(visibility)","moderation_note":\(note),"ways":[],
       "unlocked":\(unlocked)}
      """
    return try APIClient.decoder.decode(SignDetail.self, from: Data(json.utf8))
  }
}
