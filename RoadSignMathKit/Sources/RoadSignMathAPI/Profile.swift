import Foundation

// Your website and home on your page (API 1.15.0), beside the name and the
// bio (`Feedback.swift`).

extension APIClient {
  /// The longest website the server keeps.
  public static let websiteMax = 200
  /// The longest home: a town or a state, in your words.
  public static let homeMax = 60

  /// Sets your website. Without `http://` or `https://` the server makes it
  /// https; empty takes it off. A bad address is a 400 whose message says
  /// why. The moderator looks at it first: 422 `refused` says why it
  /// wouldn't show it, 503 means it couldn't look and nothing changed.
  public func updateMe(token: String, website: String) async throws -> Me {
    let text = website.trimmingCharacters(in: .whitespacesAndNewlines).clipped(to: APIClient.websiteMax)
    return try await answer(to: request("PATCH", ["me"], body: ["website": text], token: token))
  }

  /// Sets where you call home, a town or a state; empty takes it off. The
  /// moderator looks first, as for the website.
  public func updateMe(token: String, home: String) async throws -> Me {
    let text = home.trimmingCharacters(in: .whitespacesAndNewlines).clipped(to: APIClient.homeMax)
    return try await answer(to: request("PATCH", ["me"], body: ["home": text], token: token))
  }
}

/// A player's website as a page shows it.
public enum ProfileWebsite {
  /// The address to open: only an http or https one with a host, so
  /// nothing else a newer server or a damaged save might hold is opened.
  public static func url(_ website: String?) -> URL? {
    guard let website, let url = URL(string: website),
          let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
          let host = url.host(), !host.isEmpty
    else { return nil }
    return url
  }

  /// "example.com" for `https://www.example.com/me`: the host, without
  /// `www.`, as the website shows it.
  public static func label(_ website: String?) -> String? {
    guard let host = url(website)?.host()?.lowercased() else { return nil }
    return host.hasPrefix("www.") && host.count > 4 ? String(host.dropFirst(4)) : host
  }
}
