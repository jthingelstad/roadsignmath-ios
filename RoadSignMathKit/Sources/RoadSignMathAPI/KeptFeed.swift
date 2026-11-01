import Foundation

/// Home's newest signs as last read, kept on the phone so Home opens with
/// signs when there's no signal, under a "No signal" bar that says when
/// they were read.
public struct KeptFeed: Codable, Sendable, Equatable {
  /// When the signs were read.
  public var readAt: Date
  /// Whose read it was: their handle, or nil when nobody was signed in. A
  /// read with your token says which signs you hearted, so only the same
  /// reader gets the signs back.
  public var reader: String?
  public var signs: [Sign]

  /// How many signs are kept: Home's first page.
  public static let most = 20

  public init(readAt: Date, reader: String?, signs: [Sign]) {
    self.readAt = readAt
    self.reader = reader
    self.signs = Array(signs.prefix(Self.most))
  }
}

/// The one small file a kept feed lives in.
public struct KeptFeedFile: Sendable {
  public let url: URL

  public init(url: URL) { self.url = url }

  /// In Caches (the system may clear it, and Home then waits for the
  /// server as it always did), named for the server, so the local server's
  /// signs never show as the live ones.
  public static func standard(server: URL) -> KeptFeedFile? {
    guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
    return KeptFeedFile(url: caches.appending(path: name(server)))
  }

  /// `latest-roadsignmath.xyz.json`, `latest-localhost-8787.json`.
  static func name(_ server: URL) -> String {
    let parts = [server.host() ?? "server", server.port.map(String.init)].compactMap { $0 }
    return "latest-" + parts.joined(separator: "-") + ".json"
  }

  /// The kept feed, if there is one and it was read by `reader`.
  public func load(reader: String?) -> KeptFeed? {
    guard let data = try? Data(contentsOf: url),
      let kept = try? JSONDecoder().decode(KeptFeed.self, from: data),
      kept.reader == reader
    else { return nil }
    return kept
  }

  public func save(_ feed: KeptFeed) {
    guard let data = try? JSONEncoder().encode(feed) else { return }
    try? data.write(to: url, options: .atomic)
  }

  public func clear() {
    try? FileManager.default.removeItem(at: url)
  }
}
