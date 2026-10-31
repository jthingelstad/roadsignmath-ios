import RoadSignMathAPI
import SwiftUI

extension View {
  /// Counts this screen in the site's analytics each time it comes into
  /// view, once its path is known (a sign's slug arrives with the sign).
  /// Nothing about who looked goes with it.
  func countsView(_ path: String?) -> some View { modifier(CountsView(path: path)) }
}

extension EnvironmentValues {
  /// Whether this screen's tab is the one showing. Home and the Map stay
  /// mounted side by side, so a page kept on a hidden tab never
  /// disappears; this tells it when it's back in view.
  @Entry var tabShown = true
}

private struct CountsView: ViewModifier {
  @Environment(Store.self) private var store
  @Environment(\.tabShown) private var tabShown
  let path: String?
  @State private var showing = false
  @State private var counted = false

  func body(content: Content) -> some View {
    content
      .onAppear {
        showing = true
        counted = false
        count()
      }
      .onDisappear { showing = false }
      .onChange(of: path) { count() }
      .onChange(of: tabShown) { _, now in
        if now {
          counted = false
          count()
        }
      }
  }

  private func count() {
    guard showing, tabShown, !counted, let path else { return }
    counted = true
    store.saw(path)
  }
}
