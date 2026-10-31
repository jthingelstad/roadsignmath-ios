import RoadSignMathAPI
import SwiftUI

@main
struct RoadSignMathApp: App {
  @State private var store = Store()
  @State private var account = Account(client: APIClient(base: Store.server))
  @Environment(\.scenePhase) private var phase

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(store)
        .environment(account)
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
          if now == .active { Task { await account.refresh() } }
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
