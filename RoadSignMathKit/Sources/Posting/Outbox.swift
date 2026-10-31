import Foundation
import RoadSignMathAPI

/// A post on its way: the sign as it will be posted, its photo (a file of
/// its own in the outbox folder) and how far it has got. It uploads the
/// photo, then posts with its own `Idempotency-Key`, so however many times
/// it's tried it makes one sign.
public struct OutboxItem: Codable, Sendable, Hashable, Identifiable {
  public enum State: Codable, Sendable, Hashable {
    /// Still to send, from `nextTry`. `problem` says why the last try
    /// didn't go (no connection, the server busy), nil before the first.
    case waiting(problem: String?)
    /// Its poster isn't signed in (or the token ended): it waits for them.
    case needsSignIn
    /// On the map.
    case posted(PostedSign)
    /// Posted, but held for a look: only its poster sees it, with the
    /// moderator's note.
    case held(PostedSign, note: String?)
    /// The server said no, in its words. Trying again (after a fix) is
    /// the player's call.
    case refused(String)
  }

  public let id: UUID
  /// The `Idempotency-Key`: one per post, kept for every try.
  public let key: String
  /// Who's posting it. It's sent only while they're signed in.
  public let handle: String
  /// The post, its `photoIds` filled in when it's sent.
  public var post: SignPost
  public var uploadId: String?
  public var uploadedAt: Date?
  public var state: State
  public var attempts: Int
  public var nextTry: Date
  public let createdAt: Date
  /// When a try first went to the server and no answer came back, so the
  /// sign may have been made. The next try looks for it on the poster's
  /// own page before sending anything.
  public var unsureSince: Date?

  public init(handle: String, post: SignPost, now: Date = .now, id: UUID = UUID()) {
    self.id = id
    key = "rsm-" + id.uuidString.lowercased()
    self.handle = handle
    self.post = post
    state = .waiting(problem: nil)
    attempts = 0
    nextTry = now
    createdAt = now
  }

  /// Still to send, now or later.
  public var isWaiting: Bool {
    switch state {
    case .waiting, .needsSignIn: true
    default: false
    }
  }

  /// Due to be tried now.
  public func isDue(at now: Date) -> Bool {
    if case .waiting = state { return nextTry <= now }
    return false
  }

  /// The sign it made, once posted (held or not).
  public var posted: PostedSign? {
    switch state {
    case .posted(let sign), .held(let sign, _): sign
    default: nil
    }
  }

  /// Back in line to send at once: after a refusal the player fixed, or
  /// after signing in again.
  public mutating func retry(now: Date = .now) {
    state = .waiting(problem: nil)
    attempts = 0
    nextTry = now
  }
}

/// The sign a post made: enough to open it and say where it went, and the
/// badges the post earned, so a post that went while the player was away
/// still shows them.
public struct PostedSign: Codable, Sendable, Hashable {
  public var id: String
  public var slug: String
  public var title: String
  public var url: URL
  /// The post answer's `unlocked`. Nil when none were earned, or the sign
  /// was found on the poster's page after a try that got no answer (the
  /// page doesn't say what that post earned).
  public var unlocked: [EarnedBadge]?

  public init(id: String, slug: String, title: String, url: URL, unlocked: [EarnedBadge]? = nil) {
    self.id = id
    self.slug = slug
    self.title = title
    self.url = url
    self.unlocked = unlocked
  }

  public init(_ sign: Sign, unlocked: [EarnedBadge] = []) {
    self.init(id: sign.id, slug: sign.slug, title: sign.title, url: sign.url, unlocked: unlocked.isEmpty ? nil : unlocked)
  }
}

/// How the outbox talks to the server. The app's sends with the signed-in
/// player's token; the tests' answer as told.
public struct OutboxSender: Sendable {
  public var upload: @Sendable (Data) async throws -> Upload
  public var post: @Sendable (SignPost, String) async throws -> SignDetail
  /// The sign on this player's own page (held and hidden ones too) whose
  /// photo is this upload, or nil when there's none: a sign keeps its
  /// upload's id as its photo's.
  public var find: @Sendable (_ handle: String, _ photoId: String) async throws -> Sign?

  public init(
    upload: @escaping @Sendable (Data) async throws -> Upload,
    post: @escaping @Sendable (SignPost, String) async throws -> SignDetail,
    find: @escaping @Sendable (_ handle: String, _ photoId: String) async throws -> Sign?
  ) {
    self.upload = upload
    self.post = post
    self.find = find
  }
}

/// Thrown by a sender with no one signed in, or whose token has ended.
public struct SignedOut: Error, Sendable {
  public init() {}
}

/// One try at sending a post: the upload (again, if the last one is too
/// old to post), then the post. What went wrong decides what's next:
/// no connection or a busy server waits and tries again by itself; a
/// signed-out player waits for them; anything else the server said no to
/// is said to the player.
public enum Delivery {
  /// Uploads older than this are sent again: the server keeps them a day,
  /// and a post can take a while to go after its upload.
  public static let uploadFresh: TimeInterval = 20 * 3600
  /// What the player is told when a post may have gone and there's no way
  /// to look for it.
  public static let unsure =
    "This one may have posted already: the connection dropped as it went. Look for it on your page, and try again only if it isn’t there."

  /// What the player is told while a post waits for a connection.
  public static let offline = "Waiting for a connection. It’ll post on its own."
  static let busy = "Road Sign Math isn’t answering just now. It’ll try again on its own."

  public static func attempt(
    _ item: OutboxItem, photo: Data?, sender: OutboxSender, now: @Sendable () -> Date = { .now }
  ) async -> OutboxItem {
    var item = item
    item.attempts += 1
    var uploadedNow = false
    var sent = false
    if item.unsureSince != nil {
      // The last try went and no answer came back: the sign may be made.
      // Look for it on the poster's page before sending again, so a post
      // is never made twice however long the phone waited.
      guard let photoId = item.uploadId else {
        item.state = .refused(unsure)
        return item
      }
      do {
        if let sign = try await sender.find(item.handle, photoId) {
          item.state = settled(sign)
          return item
        }
        // Not there: that try made no sign, so sending again is safe. (One
        // still being made answers the same key with "still being made".)
        item.unsureSince = nil
      } catch {
        switch Outcome(error) {
        case .signIn:
          item.state = .needsSignIn
        case .later(let problem, let wait):
          item.state = .waiting(problem: problem)
          item.nextTry = now().addingTimeInterval(wait ?? Backoff.delay(after: item.attempts))
        case .uploadAgain, .refused:
          item.state = .waiting(problem: busy)
          item.nextTry = now().addingTimeInterval(Backoff.delay(after: item.attempts))
        }
        return item
      }
    }
    do {
      if item.uploadId == nil || item.uploadedAt.map({ now().timeIntervalSince($0) > uploadFresh }) ?? true {
        guard let photo else {
          item.state = .refused("The photo for this post is gone. Take it again to post it.")
          return item
        }
        let upload = try await sender.upload(photo)
        item.uploadId = upload.id
        item.uploadedAt = now()
        uploadedNow = true
      }
      item.post.photoIds = [item.uploadId!]
      sent = true
      let detail = try await sender.post(item.post, item.key)
      item.state = settled(detail.sign, unlocked: detail.unlocked)
      return item
    } catch {
      if sent, item.unsureSince == nil, Outcome.unanswered(error) { item.unsureSince = now() }
      switch Outcome(error) {
      case .later(let problem, let wait):
        item.state = .waiting(problem: problem)
        item.nextTry = now().addingTimeInterval(wait ?? Backoff.delay(after: item.attempts))
      case .signIn:
        item.state = .needsSignIn
      case .uploadAgain(let message):
        // The upload ended or was taken: send the photo again, once. If a
        // fresh upload is refused the same way, say so.
        item.uploadId = nil
        item.uploadedAt = nil
        if uploadedNow {
          item.state = .refused(message)
        } else {
          item.state = .waiting(problem: nil)
          item.nextTry = now()
        }
      case .refused(let message):
        item.state = .refused(message)
      }
      return item
    }
  }

  /// Where a made sign leaves the post: on the map with what it earned,
  /// or held for a look (a held sign earns nothing until it's shown).
  static func settled(_ sign: Sign, unlocked: [EarnedBadge] = []) -> OutboxItem.State {
    sign.visibility == .shown
      ? .posted(PostedSign(sign, unlocked: unlocked)) : .held(PostedSign(sign), note: sign.moderationNote)
  }

  /// What a failed try means for the post.
  enum Outcome: Equatable {
    /// Try again by itself: after `wait`, or the backoff.
    case later(String, wait: TimeInterval?)
    case signIn
    case uploadAgain(String)
    case refused(String)

    init(_ error: any Error) {
      switch error {
      case is SignedOut:
        self = .signIn
      case let error as APIError:
        switch (error.status, error.code) {
        case (401, _), (_, "unauthorized"):
          self = .signIn
        case (429, _), (_, "rate_limited"):
          // A day's posts or photos are used up: try again in an hour, and
          // say the server's words meanwhile.
          self = .later(error.message, wait: 3600)
        case (409, _) where error.message.contains("still being made"):
          self = .later(busy, wait: 5)
        case (409, _) where error.message.hasPrefix("Photo "):
          self = .uploadAgain(error.message)
        case (400, _) where error.message.hasPrefix("Photo ") && error.message.contains("waited too long"):
          self = .uploadAgain(error.message)
        case (500..., _), (0, _), (_, "unavailable"), (_, "internal"):
          self = .later(busy, wait: nil)
        default:
          self = .refused(error.message)
        }
      case let error as URLError:
        self = error.code == .cannotFindHost || error.code == .cannotConnectToHost || error.code == .timedOut
          ? .later(busy, wait: nil) : .later(offline, wait: nil)
      default:
        // Anything else (a reply that couldn't be read) is the server's
        // trouble, not the post's: try again later.
        self = .later(busy, wait: nil)
      }
    }

    /// The request may have reached the server and made the sign, though
    /// no answer said so: the connection dropped or timed out after it
    /// went, a gateway answered for the server, or the reply couldn't be
    /// read. Not when it never left the phone, or the server itself said
    /// no (it undoes a failed post).
    static func unanswered(_ error: any Error) -> Bool {
      switch error {
      case is SignedOut:
        return false
      case let error as APIError:
        return error.status == 0 || (error.status >= 500 && error.code.hasPrefix("http_"))
      case let error as URLError:
        let neverLeft: [URLError.Code] = [
          .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
          .dataNotAllowed, .internationalRoamingOff, .callIsActive, .secureConnectionFailed, .cancelled,
        ]
        return !neverLeft.contains(error.code)
      default:
        return true
      }
    }
  }
}

/// How long a post waits between tries: quick at first, then up to half
/// an hour. A connection coming back tries at once anyway.
public enum Backoff {
  static let steps: [TimeInterval] = [5, 15, 60, 300, 900, 1800]

  public static func delay(after attempts: Int) -> TimeInterval {
    steps[min(max(attempts - 1, 0), steps.count - 1)]
  }
}

/// The outbox on disk: `outbox.json` with every post, and each post's
/// photo beside it as `<id>.jpg`. In Application Support, so it outlives a
/// relaunch and isn't cleared like a cache.
public struct OutboxFolder: Sendable {
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  /// `Application Support/Outbox`, made if it isn't there, and kept out
  /// of backups (a post is a day's work at most).
  public static func standard() throws -> OutboxFolder {
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    var url = support.appendingPathComponent("Outbox", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? url.setResourceValues(values)
    return OutboxFolder(url: url)
  }

  private var index: URL { url.appendingPathComponent("outbox.json") }

  public func load() -> [OutboxItem] {
    guard let data = try? Data(contentsOf: index) else { return [] }
    return (try? JSONDecoder().decode([OutboxItem].self, from: data)) ?? []
  }

  public func save(_ items: [OutboxItem]) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try JSONEncoder().encode(items).write(to: index, options: .atomic)
  }

  public func photoURL(_ id: UUID) -> URL { url.appendingPathComponent(id.uuidString.lowercased() + ".jpg") }

  public func savePhoto(_ data: Data, for id: UUID) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try data.write(to: photoURL(id), options: .atomic)
  }

  public func photo(_ id: UUID) -> Data? { try? Data(contentsOf: photoURL(id)) }

  public func removePhoto(_ id: UUID) {
    try? FileManager.default.removeItem(at: photoURL(id))
  }
}
