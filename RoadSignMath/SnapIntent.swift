import AppIntents
import SwiftUI

/// "Snap a road sign": the app opens on the camera, from the Action
/// button, Siri, Shortcuts, Spotlight or a Home Screen shortcut, since a
/// sign goes by in seconds. Nothing is taken or sent on its own: the
/// passenger still takes the photo.
struct SnapRoadSign: AppIntent {
  static let title: LocalizedStringResource = "Snap a road sign"
  static let description = IntentDescription("Opens Road Sign Math on the camera, ready for the next sign.")
  static let openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    Snap.shared.ask()
    return .result()
  }
}

/// The intent's phrases for Siri and its place in Shortcuts and on the
/// Action button.
struct RoadSignMathShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: SnapRoadSign(),
      phrases: [
        "Snap a road sign with \(.applicationName)",
        "Snap a sign in \(.applicationName)",
        "Open the \(.applicationName) camera",
      ],
      shortTitle: "Snap a road sign",
      systemImageName: "camera.fill"
    )
  }

  static let shortcutTileColor: ShortcutTileColor = .teal
}

/// Asks for Capture from outside the app's screens. `RootView` opens it
/// once nothing is in the way: a sheet like You closes first (`clearing`),
/// and a sign-in under way is left to finish.
@MainActor @Observable
final class Snap {
  static let shared = Snap()

  /// Bumped for each ask; `RootView` keeps how many it has answered.
  private(set) var asked = 0
  /// Bumped to close the sheets in Capture's way.
  private(set) var clearing = 0

  func ask() { asked += 1 }
  func clear() { clearing += 1 }
}

extension View {
  /// Closes this sheet when "Snap a road sign" needs the screen for
  /// Capture. Sheets opened from inside it close with it.
  func closesForSnap() -> some View { modifier(ClosesForSnap()) }
}

private struct ClosesForSnap: ViewModifier {
  @Environment(\.dismiss) private var dismiss

  func body(content: Content) -> some View {
    content.onChange(of: Snap.shared.clearing) { dismiss() }
  }
}
