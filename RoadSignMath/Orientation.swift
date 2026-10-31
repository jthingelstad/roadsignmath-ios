import UIKit

/// Which ways the screen may turn. The app stands upright, except Capture,
/// which turns with the phone: a passenger holds it sideways to frame a sign
/// out the window, as the Capture board is drawn.
@MainActor
enum Orientation {
  private(set) static var allowed: UIInterfaceOrientationMask = .portrait

  /// Lets the screen turn `mask` ways, and turns it now if it must.
  static func allow(_ mask: UIInterfaceOrientationMask) {
    allowed = mask
    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
      for window in scene.windows {
        var controller = window.rootViewController
        while let shown = controller {
          shown.setNeedsUpdateOfSupportedInterfaceOrientations()
          controller = shown.presentedViewController
        }
      }
      if mask == .portrait, scene.effectiveGeometry.interfaceOrientation != .portrait {
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
      }
    }
  }

  /// Turns the screen to landscape now, for a screenshot of Capture
  /// sideways (`-RSMLandscape YES`), since a simulator run from the command
  /// line can't be turned by hand.
  static func turnSideways() {
    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
      scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { error in
        print("Orientation: couldn't turn sideways: \(error)")
      }
    }
  }
}

/// Only here to answer which ways the screen may turn.
final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    Orientation.allowed
  }
}
