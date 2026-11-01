import SwiftUI
import UIKit

/// The icon on the Home Screen: Highway, the default, or one of the four
/// others from the identity collection, chosen in Settings' App icon. The
/// system keeps the choice across launches; it's read back from
/// `UIApplication`, never kept here. Inside the app the brand stays
/// Highway (`Logo`), whichever one the Home Screen shows.
///
/// Each is an app icon set in the asset catalog (`AppIcon` is Highway's,
/// named in `ASSETCATALOG_COMPILER_APPICON_NAME`; the others are
/// `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`), with its dark and
/// tinted looks, made by `scripts/app-icons.swift` from `design/brand/v1`,
/// and an `Icon<Name>` picture for the picker.
enum HomeScreenIcon: String, CaseIterable, Identifiable {
  case highway, sunshine, division, factorial, fourWays

  var id: String { rawValue }

  var name: String {
    switch self {
    case .highway: "Highway"
    case .sunshine: "Sunshine"
    case .division: "Division"
    case .factorial: "Factorial"
    case .fourWays: "Four Ways"
    }
  }

  /// A line under the name.
  var about: String {
    switch self {
    case .highway: "The square root that takes the exit."
    case .sunshine: "The same sign in yellow."
    case .division: "Division takes the exit."
    case .factorial: "3! on a route shield."
    case .fourWays: "+, −, × and ÷ on a green sign."
    }
  }

  /// What VoiceOver says the icon looks like.
  var looks: String {
    switch self {
    case .highway: "A white square root that becomes an exit arrow, on green."
    case .sunshine: "The same square root and exit arrow in dark green, on yellow."
    case .division: "A division sign whose bar becomes an exit arrow, on yellow."
    case .factorial: "3 factorial on a green route shield, on yellow."
    case .fourWays: "Plus, minus, times and divide on a green sign."
    }
  }

  /// The alternate icon set's name; nil is the app's own, Highway.
  var alternate: String? {
    switch self {
    case .highway: nil
    case .sunshine: "AppIcon-Sunshine"
    case .division: "AppIcon-Division"
    case .factorial: "AppIcon-Factorial"
    case .fourWays: "AppIcon-FourWays"
    }
  }

  /// The square icon, for the picker (the system rounds the real one).
  var picture: String { "Icon" + name.replacingOccurrences(of: " ", with: "") }

  /// The one on the Home Screen now.
  @MainActor static var current: HomeScreenIcon {
    let name = UIApplication.shared.alternateIconName
    return allCases.first { $0.alternate == name } ?? .highway
  }

  /// False where the system can't change an app's icon.
  @MainActor static var changeable: Bool { UIApplication.shared.supportsAlternateIcons }

  /// Puts this one on the Home Screen. Throws when the system says no;
  /// then the icon is whatever it was (read `current` again).
  /// `-RSMAppIconFail YES` fails every change, to see what that looks like.
  @MainActor func choose() async throws {
    if Script.flag("RSMAppIconFail") { throw CocoaError(.featureUnsupported) }
    guard Self.current != self else { return }
    try await UIApplication.shared.setAlternateIconName(alternate)
  }
}
