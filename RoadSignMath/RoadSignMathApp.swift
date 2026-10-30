import SwiftUI

@main
struct RoadSignMathApp: App {
  @State private var store = Store()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(store)
        .tint(.greenInk)
        // A sign's page on roadsignmath.xyz opens the sign here, once the
        // site serves its apple-app-site-association.
        .onOpenURL { store.open($0) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
          if let url = activity.webpageURL { store.open(url) }
        }
    }
  }
}
