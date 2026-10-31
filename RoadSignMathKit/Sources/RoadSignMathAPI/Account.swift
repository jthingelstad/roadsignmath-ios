import Foundation

// Signing in and the account: the JSON of `/auth/start`, `/auth/verify`
// and `/me`, the sign-in link in the email, and the handle a first name
// makes.

/// `POST /auth/start`'s answer: the sign-in to finish with the email's
/// code or link.
public struct SignInStarted: Codable, Sendable, Hashable {
  public var loginId: String
  /// Seconds the link and code work for (15 minutes).
  public var expiresIn: Int

  public init(loginId: String, expiresIn: Int) {
    self.loginId = loginId
    self.expiresIn = expiresIn
  }
}

/// `POST /auth/verify`'s answer.
public struct SignedIn: Codable, Sendable, Hashable {
  /// `rsm_<playerId>_<secret>`, sent as `Authorization: Bearer` from now on.
  public var token: String
  /// This sign-in made the account.
  public var newPlayer: Bool
  public var me: Me
}

/// You, as only you see yourself: your public profile, your email and
/// whether you still need to give a name.
public struct Me: Codable, Sendable, Hashable {
  /// Your page's address on roadsignmath.xyz. A random one until you give
  /// a name; the first name sets it for good.
  public var handle: String
  /// Empty until you give one.
  public var name: String
  /// "#006348"
  public var avatarColor: String
  public var bio: String?
  public var url: URL
  public var signCount: Int
  public var states: [String]
  public var firstYear: Int?
  /// Only ever sent to you.
  public var email: String
  public var needsName: Bool

  public init(handle: String, name: String, avatarColor: String, bio: String? = nil, url: URL, signCount: Int = 0,
              states: [String] = [], firstYear: Int? = nil, email: String, needsName: Bool) {
    self.handle = handle
    self.name = name
    self.avatarColor = avatarColor
    self.bio = bio
    self.url = url
    self.signCount = signCount
    self.states = states
    self.firstYear = firstYear
    self.email = email
    self.needsName = needsName
  }
}

extension APIError {
  /// The token is gone or has ended (or a sign-in code was wrong): the
  /// server answered 401.
  public var isUnauthorized: Bool { status == 401 }
}

/// The link in a sign-in email, `https://roadsignmath.xyz/signin?l=<login>&t=<token>`.
public struct SignInLink: Sendable, Hashable {
  public var loginId: String
  public var token: String

  public init(loginId: String, token: String) {
    self.loginId = loginId
    self.token = token
  }

  /// The link's sign-in, when `url` is one: the `/signin` path on one of
  /// `hosts` (https, or any scheme for a host with a port, as `npm run dev`
  /// serves), or `roadsignmath://signin?…`, with both `l` and `t`.
  public init?(_ url: URL, hosts: Set<String> = ["roadsignmath.xyz", "www.roadsignmath.xyz"]) {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    let scheme = parts.scheme?.lowercased()
    let host = parts.host?.lowercased()
    let path = parts.path.hasSuffix("/") ? String(parts.path.dropLast()) : parts.path
    let web = (scheme == "https" || (scheme == "http" && parts.port != nil)) && host.map(hosts.contains) == true && path == "/signin"
    let app = scheme == "roadsignmath" && host == "signin" && (path.isEmpty || path == "/")
    guard web || app else { return nil }
    let items = parts.queryItems ?? []
    guard let login = items.first(where: { $0.name == "l" })?.value, !login.isEmpty,
      let token = items.first(where: { $0.name == "t" })?.value, !token.isEmpty
    else { return nil }
    loginId = login
    self.token = token
  }
}

/// The handle a name makes, as the server's `reserveHandle` does: the
/// name's slug, at most 30 characters. Nil when the name has no letters or
/// digits it can use (the server then keeps the random one). The server
/// adds -2, -3 and so on when the handle is taken.
public enum Handle {
  public static func preview(for name: String) -> String? {
    let folded = name.decomposedStringWithCompatibilityMapping.unicodeScalars
      .filter { !(0x300...0x36F).contains($0.value) }
    var slug = String(String.UnicodeScalarView(folded)).lowercased()
    slug = slug.replacing(/[^a-z0-9]+/, with: "-")
    slug = String(slug.trimmingPrefix(/-+/)).replacing(/-+$/, with: "")
    slug = String(String(slug.prefix(60)).replacing(/-+$/, with: "").prefix(30)).replacing(/-+$/, with: "")
    return slug.isEmpty || slug == "sign" ? nil : slug
  }
}
