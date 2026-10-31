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
            let asked = UIApplication.shared.beginBackgroundTask(withName: "Screen views")
            Task {
              await store.views.sendNow()
              UIApplication.shared.endBackgroundTask(asked)
            }
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
