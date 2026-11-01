import RoadSignMathAPI
import SwiftUI

@main
struct RoadSignMathApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @State private var store: Store
  @State private var account: Account
  @State private var outbox: Outbox
  @Environment(\.scenePhase) private var phase

  init() {
    // Room on disk for the feed's photos, so the signs Home keeps for no
    // signal show their pictures too. A shown photo never changes (the
    // server says so for a year), so a kept one is read from here.
    URLCache.shared.memoryCapacity = 16 * 1024 * 1024
    URLCache.shared.diskCapacity = 200 * 1024 * 1024
    let account = Account(client: APIClient(base: Store.server))
    let store = Store()
    store.account = account
    _store = State(initialValue: store)
    _account = State(initialValue: account)
    _outbox = State(initialValue: Outbox(account: account))
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(store)
        .environment(account)
        .environment(outbox)
        .tint(.greenInk)
        // roadsignmath.xyz links open here once the site serves its
        // apple-app-site-association: a sign's page opens the sign, and
        // the sign-in email's link signs you in. roadsignmath://signin?…
        // does the same, for the simulator and any page that can't use a
        // universal link.
        .onOpenURL { open($0) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
          if let url = activity.webpageURL { open(url) }
        }
        .onChange(of: phase) { _, now in
          if now == .active {
            Task { await account.refresh() }
            outbox.wakeUp()
          }
          // Views still waiting go before the app sleeps, given the few
          // seconds the system allows to send them.
          if now == .background {
            let store = store
            BackgroundSend().start { await store.views.sendNow() }
          }
        }
    }
  }

  private func open(_ url: URL) {
    if let link = SignInLink(url, hosts: account.linkHosts) {
      Task { await account.open(link) }
    } else {
      store.open(url)
    }
  }
}

/// Work given the few seconds the system allows after the app goes to the
/// background. When they run out first, the work is cancelled (views not
/// sent wait for the next batch) and the time is handed back, once, so
/// the system suspends the app instead of ending it.
@MainActor
private final class BackgroundSend {
  private var asked = UIBackgroundTaskIdentifier.invalid
  private var work: Task<Void, Never>?

  func start(_ job: @escaping @MainActor () async -> Void) {
    asked = UIApplication.shared.beginBackgroundTask(withName: "Screen views") { [self] in
      work?.cancel()
      end()
    }
    work = Task { [self] in
      await job()
      end()
    }
  }

  private func end() {
    guard asked != .invalid else { return }
    UIApplication.shared.endBackgroundTask(asked)
    asked = .invalid
  }
}
