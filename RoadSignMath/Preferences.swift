import Foundation

/// The build, as `scripts/version.sh` stamps it into Info.plist, for a
/// tester to name when something's off.
enum BuildInfo {
  static var version: String { info("CFBundleShortVersionString") ?? "?" }
  static var build: String { info("CFBundleVersion") ?? "?" }
  static var commit: String? { info("RoadSignMathCommit").flatMap { $0.isEmpty ? nil : String($0.prefix(7)) } }

  /// "Road Sign Math 0.9.0 · build 52 · 1a2b3c4"
  static var line: String {
    ["Road Sign Math \(version)", "build \(build)", commit].compactMap { $0 }.joined(separator: .dot)
  }

  private static func info(_ key: String) -> String? {
    Bundle.main.object(forInfoDictionaryKey: key) as? String
  }
}
