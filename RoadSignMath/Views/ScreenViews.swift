import RoadSignMathAPI
import SwiftUI

extension View {
  /// Counts this screen in the site's analytics each time it comes into
  /// view, once its path is known (a sign's slug arrives with the sign).
  /// Nothing about who looked goes with it.
  func countsView(_ path: String?) -> some View { modifier(CountsView(path: path)) }
}

private struct CountsView: ViewModifier {
  @Environment(Store.self) private var store
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
  }

  private func count() {
    guard showing, !counted, let path else { return }
    counted = true
    store.saw(path)
  }
}
