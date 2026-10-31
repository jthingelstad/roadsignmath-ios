import Foundation
import Network
import Observation
import Posting
import RoadSignMathAPI
import UIKit

/// Posts on their way to the server, kept on disk (`OutboxFolder`, in
/// Application Support) so a post made with no connection, or with the app
/// closed before it went, still goes. Each one uploads its photo, then
/// posts with its own Idempotency-Key, so a retry never makes a second
/// sign. A post waits for a connection (the network coming back tries at
/// once), backs off while the server is busy, waits for its poster to be
/// signed in, and says a refusal in the server's words.
///
/// A post stays listed after it goes, until the player has seen it posted
/// (the done screen, or Home's word about it).
@MainActor @Observable
final class Outbox {
  private(set) var items: [OutboxItem] = []
  /// The post being sent right now.
  private(set) var sending: UUID?
  /// Bumped when a post goes up, so Home and the Map read the signs again.
  private(set) var postedCount = 0

  @ObservationIgnored private let folder: OutboxFolder?
  @ObservationIgnored private let account: Account
  @ObservationIgnored private var pictures: [UUID: UIImage] = [:]
  @ObservationIgnored private var running = false
  @ObservationIgnored private var again = false
  @ObservationIgnored private var wake: Task<Void, Never>?
  @ObservationIgnored private let monitor = NWPathMonitor()
  @ObservationIgnored private var online = true

  init(account: Account) {
    self.account = account
    folder = try? OutboxFolder.standard()
    items = folder?.load() ?? []
    monitor.pathUpdateHandler = { [weak self] path in
      let satisfied = path.status == .satisfied
      Task { @MainActor in self?.connection(satisfied) }
    }
    monitor.start(queue: DispatchQueue(label: "xyz.roadsignmath.outbox.network"))
    wakeUp()
  }

  // MARK: What the screens show

  func item(_ id: UUID) -> OutboxItem? { items.first { $0.id == id } }

  /// The posts Home has a word about: still going, held, refused, or
  /// posted while the player was elsewhere. Only the signed-in player's.
  var unseen: [OutboxItem] {
    guard let handle = account.me?.handle else { return [] }
    return items.filter { $0.handle == handle }
  }

  /// The photo a post carries, small, to show beside it.
  func picture(_ id: UUID) -> UIImage? {
    if let picture = pictures[id] { return picture }
    guard let data = folder?.photo(id), let picture = UIImage(data: data) else { return nil }
    pictures[id] = picture
    return picture
  }

  // MARK: Posting

  /// Puts a post in the outbox and starts sending it. Throws, leaving the
  /// outbox as it was, when the post can't be kept on the phone (its photo
  /// or the list), since the screens after promise it's kept.
  func add(_ post: SignPost, photo: Data, picture: UIImage?, handle: String) throws -> UUID {
    let item = OutboxItem(handle: handle, post: post)
    if let folder {
      try folder.savePhoto(photo, for: item.id)
      do {
        try folder.save(items + [item])
      } catch {
        folder.removePhoto(item.id)
        throw error
      }
    }
    pictures[item.id] = picture
    items.append(item)
    kick()
    return item.id
  }

  /// Seen by the player: a posted or held post leaves the list.
  func acknowledge(_ id: UUID) {
    guard let item = item(id), item.posted != nil else { return }
    remove(id)
  }

  /// Forget a post that hasn't gone (a refusal the player won't fix).
  func remove(_ id: UUID) {
    items.removeAll { $0.id == id }
    folder?.removePhoto(id)
    pictures[id] = nil
    save()
  }

  /// Try a refused or waiting post again, now.
  func retry(_ id: UUID) {
    guard let index = items.firstIndex(where: { $0.id == id }), items[index].posted == nil else { return }
    // The player's own call: after "This one may have posted already",
    // they've looked and it isn't there.
    items[index].unsureSince = nil
    items[index].retry()
    save()
    kick()
  }

  /// Someone signed in (or out): their waiting posts go at once.
  func signedInChanged() {
    guard let handle = account.me?.handle, account.signedIn else { return }
    for index in items.indices where items[index].handle == handle && items[index].state == .needsSignIn {
      items[index].retry()
    }
    save()
    kick()
  }

  /// The app opened or came to the front: anything due goes, and so does
  /// whatever was waiting for a connection, which may well be back.
  func wakeUp() {
    tryOffline()
    kick()
  }

  // MARK: Sending

  private func connection(_ satisfied: Bool) {
    let back = satisfied && !online
    online = satisfied
    guard back else { return }
    tryOffline()
    kick()
  }

  /// What was waiting for a connection goes now, not at the end of its
  /// backoff.
  private func tryOffline() {
    for index in items.indices {
      if case .waiting(let problem) = items[index].state, problem == Delivery.offline {
        items[index].nextTry = .now
      }
    }
  }

  /// Sends whatever is due, one post at a time, then sleeps until the next
  /// is due.
  private func kick() {
    guard !running else {
      again = true
      return
    }
    running = true
    wake?.cancel()
    Task {
      await drain()
      running = false
      if again {
        again = false
        kick()
      } else {
        schedule()
      }
    }
  }

  private func drain() async {
    while let handle = account.me?.handle, account.signedIn,
      let due = items.first(where: { $0.handle == handle && $0.isDue(at: .now) })
    {
      sending = due.id
      let photo = folder?.photo(due.id)
      let done = await Delivery.attempt(due, photo: photo, sender: sender)
      sending = nil
      guard let index = items.firstIndex(where: { $0.id == due.id }) else { continue }
      items[index] = done
      if done.posted != nil {
        folder?.removePhoto(done.id)
        postedCount += 1
      }
      save()
    }
  }

  private func schedule() {
    wake?.cancel()
    guard let handle = account.me?.handle else { return }
    let next = items.filter { $0.handle == handle && $0.isDue(at: .distantFuture) }.map(\.nextTry).min()
    guard let next else { return }
    wake = Task { [weak self] in
      try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0.5)))
      guard !Task.isCancelled else { return }
      self?.kick()
    }
  }

  private var sender: OutboxSender {
    #if DEBUG
      // `-RSMOffline YES`: every try fails as if there were no connection,
      // for the waiting screens (a simulator can't drop its network).
      if Script.flag("RSMOffline") {
        return OutboxSender(
          upload: { _ in throw URLError(.notConnectedToInternet) },
          post: { _, _ in throw URLError(.notConnectedToInternet) },
          find: { _, _ in throw URLError(.notConnectedToInternet) })
      }
    #endif
    let account = account
    let client = account.client
    return OutboxSender(
      upload: { photo in try await account.call { try await client.uploadPhoto(photo, token: $0) } },
      post: { post, key in try await account.call { try await client.postSign(post, key: key, token: $0) } },
      find: { handle, photoId in
        do {
          return try await account.call { token in
            try await client.player(handle, token: token).signs?.first { $0.photos.contains { $0.id == photoId } }
          }
        } catch let error as APIError where error.status == 404 {
          // A player the server doesn't list yet has no signs, so no sign was made.
          return nil
        }
      })
  }

  #if DEBUG
    /// `-RSMUnlocked <id,id>`: a post that's just gone up having earned
    /// these badges, for the "Posted!" moment's screenshots. Shown, never
    /// sent or saved; the badges' names come from the catalog.
    func scriptPosted(unlocked ids: [String], picture: UIImage?) async -> UUID {
      let catalog = (try? await account.client.badges()) ?? []
      let sign = BadgeSign(id: "01scripted", slug: "bloomington-math", title: "Bloomington Math",
                           url: URL(string: "https://roadsignmath.xyz/signs/bloomington-math")!)
      let badges = ids.map { id in
        let known = catalog.first { $0.id == id }
        let step = known?.steps?.first
        return EarnedBadge(
          id: id, shelf: known?.shelf ?? .math, name: known?.name ?? id, how: known?.how ?? "",
          mark: step.map(String.init) ?? known?.mark ?? "?", step: step, earnedOn: "2026-10-30", sign: sign)
      }
      var item = OutboxItem(
        handle: account.me?.handle ?? "you",
        post: SignPost(
          title: sign.title, numbers: ["8", "82", "90"].map { PostNumber(value: $0) },
          place: PostPlace(label: "Bloomington, MN", state: "MN", approximate: true), foundOn: "2026-10-30", way: "90 − 82 = 8"))
      item.state = .posted(PostedSign(id: sign.id, slug: sign.slug, title: sign.title, url: sign.url, unlocked: badges))
      pictures[item.id] = picture
      items.append(item)
      return item.id
    }
  #endif

  private func save() {
    try? folder?.save(items)
  }
}
