import CoreLocation
import Foundation
import Observation
import RoadSignMathAPI

/// What the screens show, read from the server. Read only: nothing here
/// posts, solves, reports or signs in.
@MainActor @Observable
final class Store {
  enum Tab: Hashable { case home, capture, map }

  enum Load: Equatable {
    case idle, loading, loaded
    case failed(String)
  }

  let client: APIClient
  var tab: Tab = .home
  /// The pin the Map should show next ("Show on the map" from a sign).
  var mapFocus: String?
  /// Each tab's open signs, by id or slug, so a link or a second tap on
  /// the tab can move them.
  var homePath: [String] = []
  var mapPath: [String] = []
  /// Bumped when Home is tapped while showing: back to the newest sign.
  var homeToTop = 0

  // Latest: the newest signs, a page at a time.
  private(set) var latest: [Sign] = []
  private(set) var latestLoad: Load = .idle
  private var nextCursor: String?
  /// Bumped each time the feed is read afresh.
  private var feedGeneration = 0
  private(set) var loadingMore = false

  // Near you.
  private(set) var near: [Sign] = []
  private(set) var nearLoad: Load = .idle
  private(set) var locationDenied = false

  private(set) var pins: [Pin] = []
  private(set) var years: [Int] = []
  private(set) var mapLoad: Load = .idle

  private(set) var players: [String: Player] = [:]
  private(set) var details: [String: SignDetail] = [:]

  /// Every sign, for the Map's search, read once the first time someone
  /// searches: pins carry only a title and a state, so places, finders and
  /// numbers come from here.
  private(set) var everySign: [String: Sign] = [:]
  private var everySignLoad: Load = .idle

  init(client: APIClient = APIClient(base: Store.server)) {
    self.client = client
    #if DEBUG
      // For screenshots and UI checks: `-RSMTab map`, `-RSMOpen /signs/<slug>`,
      // `-RSMFocus <sign id>` as launch arguments.
      let defaults = UserDefaults.standard
      if defaults.string(forKey: "RSMTab") == "map" { tab = .map }
      if let path = defaults.string(forKey: "RSMOpen"), let url = URL(string: "https://roadsignmath.xyz" + path) { open(url) }
      if let id = defaults.string(forKey: "RSMFocus") { mapFocus = id; tab = .map }
    #endif
  }

  /// Release builds read the live server. A Debug build in the simulator
  /// reads `npm run dev` on this Mac; on a phone, the live server. The
  /// scheme's RSM_API environment variable picks any other, as does an
  /// `RSM_API` default (a launch argument, or `defaults write`, which also
  /// holds when a link opens the app cold).
  static var server: URL {
    #if DEBUG
      let named = ProcessInfo.processInfo.environment["RSM_API"] ?? UserDefaults.standard.string(forKey: "RSM_API")
      if let named, let url = URL(string: named) { return url }
      #if targetEnvironment(simulator)
        return APIClient.local
      #else
        return APIClient.live
      #endif
    #else
      return APIClient.live
    #endif
  }

  var hasMore: Bool { nextCursor != nil }

  func loadLatest() async {
    if latestLoad == .loading { return }
    if latest.isEmpty { latestLoad = .loading }
    do {
      let page = try await client.signs(limit: 20)
      latest = page.signs
      nextCursor = page.nextCursor
      // A later page still being read belongs to the feed this replaced.
      feedGeneration += 1
      latestLoad = .loaded
    } catch {
      latestLoad = Self.cancelled(error) ? (latest.isEmpty ? .idle : .loaded) : (latest.isEmpty ? .failed(Self.say(error)) : .loaded)
    }
    if players.isEmpty { await loadPlayers() }
  }

  func loadMore() async {
    guard let cursor = nextCursor, !loadingMore else { return }
    let generation = feedGeneration
    loadingMore = true
    defer { loadingMore = false }
    if let page = try? await client.signs(cursor: cursor, limit: 20), generation == feedGeneration {
      let seen = Set(latest.map(\.id))
      latest += page.signs.filter { !seen.contains($0.id) }
      nextCursor = page.nextCursor
    }
  }

  func loadNear() async {
    if nearLoad == .loading { return }
    nearLoad = .loading
    switch await Here.find() {
    case .denied:
      locationDenied = true
      nearLoad = .loaded
    case .unavailable:
      nearLoad = .failed("Couldn’t tell where you are just now.")
    case .found(let place):
      locationDenied = false
      do {
        near = try await client.signs(nearLatitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        nearLoad = .loaded
      } catch {
        nearLoad = Self.cancelled(error) ? .idle : .failed(Self.say(error))
      }
    }
  }

  func loadMap() async {
    if mapLoad == .loading { return }
    if pins.isEmpty { mapLoad = .loading }
    do {
      let map = try await client.map()
      pins = map.pins
      years = map.years
      mapLoad = .loaded
    } catch {
      mapLoad = !pins.isEmpty ? .loaded : Self.cancelled(error) ? .idle : .failed(Self.say(error))
    }
  }

  func loadPlayers() async {
    if let list = try? await client.players() {
      players = Dictionary(list.map { ($0.handle, $0) }, uniquingKeysWith: { a, _ in a })
    }
  }

  /// Reads every sign, a full page at a time, for the Map's search. Once
  /// is enough; a failure lets the next search try again.
  func loadEverySign() async {
    guard everySignLoad == .idle else { return }
    everySignLoad = .loading
    var cursor: String?
    var found: [String: Sign] = [:]
    do {
      // A ceiling, so a server that keeps handing back a cursor can't keep
      // this reading forever: 200 pages of 50.
      for _ in 0..<200 {
        let page = try await client.signs(cursor: cursor, limit: 50)
        for sign in page.signs { found[sign.id] = sign }
        guard let next = page.nextCursor, next != cursor else { break }
        cursor = next
      }
      everySign = found
      everySignLoad = .loaded
    } catch {
      everySign.merge(found) { _, new in new }
      everySignLoad = .idle
    }
  }

  /// A sign with its ways, kept once read.
  func detail(_ id: String, fresh: Bool = false) async throws -> SignDetail {
    if !fresh, let kept = details[id] { return kept }
    let detail = try await client.sign(id)
    details[id] = detail
    return detail
  }

  /// A sign already in hand, by id or slug, from either feed or a detail read.
  func knownSign(_ id: String) -> Sign? {
    details[id]?.sign ?? latest.first { $0.id == id || $0.slug == id } ?? near.first { $0.id == id || $0.slug == id }
      ?? details.values.first { $0.sign.slug == id }?.sign ?? everySign[id]
  }

  /// A tab chosen from the bar: a second tap on Home goes back to the top.
  func choose(_ next: Tab) {
    if next == tab, next == .home {
      if homePath.isEmpty { homeToTop += 1 } else { homePath.removeAll() }
    } else if next == tab, next == .map {
      mapPath.removeAll()
    }
    tab = next
  }

  /// A roadsignmath.xyz link the app was opened with: a sign's page opens
  /// that sign; anything else opens Home.
  func open(_ url: URL) {
    let parts = url.pathComponents.filter { $0 != "/" }
    tab = .home
    if parts.count == 2, parts[0] == "signs", !parts[1].isEmpty {
      homePath = [parts[1]]
    }
  }

  func showOnMap(_ sign: Sign) {
    mapFocus = sign.id
    mapPath.removeAll()
    tab = .map
  }

  /// A read the screen gave up on (it went away), not one that failed.
  static func cancelled(_ error: any Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
  }

  static func say(_ error: any Error) -> String {
    if let error = error as? APIError { return error.message }
    if let error = error as? URLError {
      switch error.code {
      case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
        return "You’re offline. The signs will be here when you’re back."
      case .cannotConnectToHost, .cannotFindHost, .timedOut:
        return "Road Sign Math isn’t answering just now."
      default: break
      }
    }
    return "Something went wrong reading the signs."
  }
}

/// Where the phone is, once, for Near you.
enum Here {
  enum Answer { case found(CLLocation), denied, unavailable }

  @MainActor static func find() async -> Answer {
    let session = CLServiceSession(authorization: .whenInUse)
    defer { session.invalidate() }
    do {
      for try await update in CLLocationUpdate.liveUpdates() {
        if let location = update.location { return .found(location) }
        if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
          return .denied
        }
      }
    } catch {}
    return .unavailable
  }
}
