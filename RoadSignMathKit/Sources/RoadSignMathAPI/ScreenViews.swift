import Foundation

/// A screen's path for the site's analytics: the website page it matches
/// (`/`, `/map`, `/signs/<slug>`, `/players/<handle>`) or a short one of the
/// app's own (`/capture`, `/you`). Lowercase letters, digits and hyphens,
/// at most two parts and 100 characters, as the server checks.
public enum ViewPath {
  public static let home = "/"
  public static let map = "/map"
  public static let capture = "/capture"
  public static let you = "/you"

  public static func sign(_ slug: String) -> String? { checked("/signs/\(slug)") }
  public static func player(_ handle: String) -> String? { checked("/players/\(handle)") }

  /// The server's `VIEW_PATH`: `/`, or one or two parts of 1 to 80
  /// lowercase letters, digits and hyphens.
  public static func isValid(_ path: String) -> Bool {
    guard path.count <= 100, path.first == "/" else { return false }
    if path == "/" { return true }
    let parts = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
    return (1...2).contains(parts.count) && parts.allSatisfy { part in
      (1...80).contains(part.count) && part.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }
  }

  private static func checked(_ path: String) -> String? { isValid(path) ? path : nil }
}

extension APIClient {
  public static let viewsMax = 20

  /// `POST /app/views`: counts screen views in the site's analytics as the
  /// app's. Never with a token: who looked is no part of it. Answers with
  /// how many were taken.
  @discardableResult
  public func countViews(_ paths: [String]) async throws -> Int {
    var request = request("POST", ["app", "views"])
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(AppViews(views: paths.map { .init(path: $0) }))
    let accepted: Accepted = try await answer(to: request)
    return accepted.accepted
  }
}

private struct AppViews: Encodable {
  struct View: Encodable { var path: String }
  var views: [View]
}

private struct Accepted: Decodable { var accepted: Int }

/// Screen views on their way, sent a batch at a time: the first a few
/// seconds after a view, then at most one batch every `every` (30 s
/// keeps a phone well under the server's 120 batches an hour), each of
/// at most 20. Nothing about who looked goes with them, and they never
/// leave the phone's memory: views not sent when the app is closed are
/// lost, which is fine for a count.
public actor ViewCounter {
  public typealias Send = @Sendable ([String]) async throws -> Void

  /// Views kept while the server can't be reached; the oldest go first.
  public static let keptMax = 100

  private let send: Send
  private let first: Duration
  private let every: Duration
  private let rest: Duration
  private let clock = ContinuousClock()

  private var waiting: [String] = []
  private var lastSent: ContinuousClock.Instant?
  private var restingUntil: ContinuousClock.Instant?
  private var sending = false
  private var scheduled: Task<Void, Never>?

  public init(first: Duration = .seconds(5), every: Duration = .seconds(30), rest: Duration = .seconds(3600), send: @escaping Send) {
    self.send = send
    self.first = first
    self.every = every
    self.rest = rest
  }

  /// A screen seen. A path the server wouldn't take is dropped here.
  public func saw(_ path: String) {
    guard ViewPath.isValid(path) else { return }
    waiting.append(path)
    if waiting.count > Self.keptMax { waiting.removeFirst(waiting.count - Self.keptMax) }
    schedule()
  }

  /// The app going to the background: one batch now, if one may go.
  public func sendNow() async {
    scheduled?.cancel()
    scheduled = nil
    await sendBatch()
    if !waiting.isEmpty { schedule() }
  }

  /// What's waiting, for tests.
  public var pending: [String] { waiting }

  private func schedule() {
    guard scheduled == nil, !waiting.isEmpty else { return }
    let now = clock.now
    var at = now + first
    if let lastSent { at = max(at, lastSent + every) }
    if let restingUntil { at = max(at, restingUntil) }
    scheduled = Task { [weak self] in
      do { try await Task.sleep(until: at, clock: .continuous) } catch { return }
      await self?.fire()
    }
  }

  private func fire() async {
    scheduled = nil
    await sendBatch()
    schedule()
  }

  private func sendBatch() async {
    guard !sending, !waiting.isEmpty else { return }
    if let restingUntil, clock.now < restingUntil { return }
    if let lastSent, clock.now < lastSent + every { return }
    sending = true
    defer { sending = false }
    let batch = Array(waiting.prefix(APIClient.viewsMax))
    waiting.removeFirst(batch.count)
    lastSent = clock.now
    do {
      try await send(batch)
    } catch let error as APIError where error.status == 429 {
      // Too many from this network: wait an hour, and these are dropped.
      restingUntil = clock.now + rest
    } catch let error as APIError where (400..<500).contains(error.status) {
      // The server won't take them; sending them again won't change that.
    } catch {
      // Offline or the server busy: they go again with the next batch.
      waiting.insert(contentsOf: batch, at: 0)
      if waiting.count > Self.keptMax { waiting.removeFirst(waiting.count - Self.keptMax) }
    }
  }
}
