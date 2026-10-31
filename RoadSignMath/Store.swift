import CoreLocation
import Foundation
import Observation
import RoadSignMathAPI

/// What the screens show, read from the server. Nothing here posts,
/// solves, reports or signs in; signed in, the reads carry your token so
/// they say which signs you hearted, and hearts go through `Account`.
@MainActor @Observable
final class Store {
  enum Tab: Hashable { case home, capture, map }

  enum Load: Equatable {
    case idle, loading, loaded
    case failed(String)
  }

  let client: APIClient
  /// Who's signed in, for reads that say which signs you hearted, and for
  /// hearting. Set once at launch.
  var account: Account?
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

  // Popular: the most hearted signs.
  private(set) var popular: [Sign] = []
  private(set) var popularLoad: Load = .idle

  private(set) var pins: [Pin] = []
  private(set) var years: [Int] = []
  private(set) var mapLoad: Load = .idle

  private(set) var players: [String: Player] = [:]
  private(set) var details: [String: SignDetail] = [:]


  /// The app's screen views on their way to the site's analytics.
  let views: ViewCounter

  init(client: APIClient = APIClient(base: Store.server)) {
    self.client = client
    views = ViewCounter { paths in try await client.countViews(paths) }
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
    let started = Date()
    do {
      let page = try await read { try await self.client.signs(limit: 20, token: $0) }
      latest = page.signs
      settleHearts(page.signs, readAt: started)
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
    let started = Date()
    if let page = try? await read({ try await self.client.signs(cursor: cursor, limit: 20, token: $0) }), generation == feedGeneration {
      settleHearts(page.signs, readAt: started)
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
      let started = Date()
      do {
        near = try await read {
          try await self.client.signs(nearLatitude: place.coordinate.latitude, longitude: place.coordinate.longitude, token: $0)
        }
        settleHearts(near, readAt: started)
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

  /// Your new (or removed) profile photo, on your cards at once: the
  /// players list may be cached a while yet.
  func showPhoto(of me: Me) {
    guard var player = players[me.handle] else { return }
    player.avatarUrl = me.avatarUrl
    player.avatarThumbUrl = me.avatarThumbUrl
    players[me.handle] = player
  }

  /// A sign with its ways, kept once read.
  func detail(_ id: String, fresh: Bool = false) async throws -> SignDetail {
    if !fresh, let kept = details[id] { return kept }
    let started = Date()
    let detail = try await read { try await self.client.sign(id, token: $0) }
    details[id] = detail
    settleHearts([detail.sign], readAt: started)
    if withNewWays[detail.sign.id] != nil { withNewWays[detail.sign.id] = detail.sign }
    return detail
  }

  func loadPopular() async {
    if popularLoad == .loading { return }
    popularLoad = .loading
    let started = Date()
    do {
      popular = try await read { try await self.client.popularSigns(token: $0) }
      settleHearts(popular, readAt: started)
      popularLoad = .loaded
    } catch {
      popularLoad = Self.cancelled(error) ? (popular.isEmpty ? .idle : .loaded) : (popular.isEmpty ? .failed(Self.say(error)) : .loaded)
    }
  }

  /// Signs a way was just added to, as the server answered (or read again
  /// since), for the lists the store doesn't hold (You's and a player's
  /// timelines).
  private(set) var withNewWays: [String: Sign] = [:]

  /// A way just added: the sign as the server now has it, everywhere it's
  /// shown, so its page lists the new way and the feeds count it.
  func wayAdded(_ detail: SignDetail) {
    let sign = detail.sign
    withNewWays[sign.id] = sign
    for key in details.keys where details[key]?.sign.id == sign.id { details[key] = detail }
    details[sign.id] = detail
    if let at = latest.firstIndex(where: { $0.id == sign.id }) { latest[at] = sign.keepingMiles(of: latest[at]) }
    if let at = near.firstIndex(where: { $0.id == sign.id }) { near[at] = sign.keepingMiles(of: near[at]) }
    if let at = popular.firstIndex(where: { $0.id == sign.id }) { popular[at] = sign.keepingMiles(of: popular[at]) }
  }

  /// A sign from a list read before a way was added to it, or a heart
  /// given, as it is now. A list read since, with as many ways or more,
  /// is newer and wins. Hearts always come from `heartsGiven`, which
  /// holds the newest word on each sign you've hearted on this phone.
  func current(_ sign: Sign) -> Sign {
    var now = sign
    if let added = withNewWays[sign.id], added.wayCount > sign.wayCount {
      now = added
      now.miles = sign.miles
    }
    if let given = heartsGiven[sign.id] {
      now.hearted = given.state.hearted
      now.hearts = given.state.hearts ?? now.hearts
    }
    return now
  }

  /// One player and their signs; signed in, it says which you hearted.
  func player(_ handle: String) async throws -> Player {
    let started = Date()
    let player = try await read { try await self.client.player(handle, token: $0) }
    settleHearts(player.signs ?? [], readAt: started)
    return player
  }

  // MARK: Hearts

  struct GivenHeart: Equatable {
    var state: HeartState
    /// When this was known: the heart's answer, or a read begun later.
    var at: Date
    var sending: Bool
  }

  /// Signs you've hearted or taken back on this phone, as last known,
  /// laid over every copy of them: Home's list, a sign page kept from
  /// before and a player's timeline all show the same. Kept until you sign
  /// in or out.
  private(set) var heartsGiven: [String: GivenHeart] = [:]

  func isSendingHeart(_ id: String) -> Bool { heartsGiven[id]?.sending == true }

  /// Gives your heart to a sign or takes it back: shown at once, then put
  /// back as it was if the server says no.
  func heart(_ sign: Sign, _ on: Bool) async throws {
    guard let account, !isSendingHeart(sign.id) else { return }
    let before = current(sign)
    let kept = heartsGiven[sign.id]
    let count = before.hearted == on ? before.hearts : before.hearts.map { max(0, $0 + (on ? 1 : -1)) }
    heartsGiven[sign.id] = GivenHeart(state: HeartState(hearted: on, hearts: count), at: Date(), sending: true)
    do {
      let state = try await account.heart(sign.id, on)
      heartsGiven[sign.id] = GivenHeart(state: state, at: Date(), sending: false)
    } catch {
      heartsGiven[sign.id] = kept
      throw error
    }
  }

  /// Signs read afresh: a read begun after a heart's answer is newer, so
  /// its word (others' hearts too) becomes the one every copy shows.
  private func settleHearts(_ signs: [Sign], readAt started: Date) {
    for sign in signs {
      guard var given = heartsGiven[sign.id], !given.sending, given.at < started,
        let hearted = sign.hearted
      else { continue }
      given.state = HeartState(hearted: hearted, hearts: sign.hearts ?? given.state.hearts)
      given.at = started
      heartsGiven[sign.id] = given
    }
  }

  /// Signed in, out, or as someone else: whose hearts the signs show has
  /// changed, so the kept reads go and Home reads again.
  func signedInChanged() {
    heartsGiven = [:]
    details = [:]
    Task {
      await loadLatest()
      if nearLoad == .loaded, !locationDenied { await loadNear() }
      if popularLoad == .loaded { await loadPopular() }
    }
  }

  /// A read with your token when signed in. A 401 tells `Account`, which
  /// checks and signs out if the token has ended, and reads again without.
  /// An answer read as someone who has since signed out (or in) would show
  /// their hearts, so it's read again as whoever is signed in now.
  private func read<T>(_ work: (String?) async throws -> T) async throws -> T {
    for _ in 0..<3 {
      let token = account?.readToken
      let answer: T
      if let token {
        do {
          answer = try await work(token)
        } catch let error as APIError where error.isUnauthorized {
          account?.readRefused(token)
          return try await work(nil)
        }
      } else {
        answer = try await work(nil)
      }
      if account?.readToken == token { return answer }
    }
    throw CancellationError()
  }

  /// A screen came into view: counted with the app's others, a batch at
  /// a time.
  func saw(_ path: String) {
    Task { await views.saw(path) }
  }

  /// The screen at the root of the tab showing, when nothing is pushed
  /// on it: Home or the Map.
  var rootScreen: String? {
    switch tab {
    case .home: homePath.isEmpty ? ViewPath.home : nil
    case .map: mapPath.isEmpty ? ViewPath.map : nil
    case .capture: nil
    }
  }

  /// A sign already in hand, by id or slug, from either feed or a detail read.
  func knownSign(_ id: String) -> Sign? {
    details[id]?.sign ?? latest.first { $0.id == id || $0.slug == id } ?? near.first { $0.id == id || $0.slug == id }
      ?? popular.first { $0.id == id || $0.slug == id }
      ?? details.values.first { $0.sign.slug == id }?.sign
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
  /// that sign, a player's page that player; anything else opens Home.
  func open(_ url: URL) {
    let parts = url.pathComponents.filter { $0 != "/" }
    tab = .home
    if parts.count == 2, parts[0] == "signs", !parts[1].isEmpty {
      homePath = [parts[1]]
    } else if parts.count == 2, parts[0] == "players", !parts[1].isEmpty {
      homePath = [PlayerPath.of(parts[1])]
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

private extension Sign {
  /// A sign read afresh keeps how far away it was, which only Near you knows.
  func keepingMiles(of old: Sign) -> Sign {
    var sign = self
    sign.miles = sign.miles ?? old.miles
    return sign
  }
}
