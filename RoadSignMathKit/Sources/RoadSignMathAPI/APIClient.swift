import Foundation

/// The server's `/api/v1`: the public reads, signing in, and your account.
/// Posting, solving and reporting come later, each with its own review.
public struct APIClient: Sendable {
  /// The live server. Release builds always use it.
  public static let live = URL(string: "https://roadsignmath.xyz/api/v1")!
  /// `npm run dev` in the server's repo.
  public static let local = URL(string: "http://localhost:8787/api/v1")!

  public var base: URL
  public var session: URLSession

  public init(base: URL = APIClient.live, session: URLSession = .shared) {
    self.base = base
    self.session = session
  }

  /// The newest signs first, a page at a time; pass the last page's
  /// `nextCursor` for the next.
  /// With your token, each sign also says whether you hearted it (and
  /// the answer is yours alone, never cached for anyone else).
  public func signs(cursor: String? = nil, limit: Int? = nil, token: String? = nil) async throws -> SignPage {
    var query: [URLQueryItem] = []
    if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
    if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
    return try await get(["signs"], query, token: token)
  }

  /// One sign, by id or slug, with every way found so far.
  public func sign(_ idOrSlug: String, token: String? = nil) async throws -> SignDetail {
    try await get(["signs", idOrSlug], token: token)
  }

  /// Signs nearest a place, nearest first, each with its `miles`.
  public func signs(nearLatitude lat: Double, longitude lng: Double, token: String? = nil) async throws -> [Sign] {
    let near: NearSigns = try await get(["signs", "near"], [
      URLQueryItem(name: "lat", value: String(lat)), URLQueryItem(name: "lng", value: String(lng)),
    ], token: token)
    return near.signs
  }

  /// The most hearted signs (API 1.8.0): most hearts first, ties and the
  /// unhearted newest first; the newest when the counts can't be read.
  public func popularSigns(token: String? = nil) async throws -> [Sign] {
    let popular: NearSigns = try await get(["signs", "popular"], [], token: token)
    return popular.signs
  }

  /// The signs with the most complex math (API 1.9.0): scored by the
  /// operators in a sign's most complex way, ties newest first, unsolved
  /// signs last. The score orders signs; it is never shown.
  public func complexSigns(token: String? = nil) async throws -> [Sign] {
    let complex: NearSigns = try await get(["signs", "complex"], [], token: token)
    return complex.signs
  }

  // MARK: Hearts

  /// Hearts a shown sign, or takes your heart back. Doing it twice changes
  /// nothing; a 503 means nothing changed and it can be tried again.
  public func heart(_ signId: String, _ on: Bool, token: String) async throws -> HeartState {
    try await send(on ? "PUT" : "DELETE", ["signs", signId, "heart"], token: token)
  }

  /// Every sign's pin, and the years they were found in. With your token
  /// it leaves out the signs of players you blocked, and is never cached
  /// for anyone else.
  public func map(token: String? = nil) async throws -> MapPins { try await get(["map"], token: token) }

  public func players() async throws -> [Player] {
    let players: Players = try await get(["players"])
    return players.players
  }

  /// One player, with their signs.
  /// One player and their signs, newest first. With your token, your own
  /// page also carries the signs only you see (held or hidden).
  public func player(_ handle: String, token: String? = nil) async throws -> Player {
    try await send("GET", ["players", handle], token: token)
  }

  public func index() async throws -> APIIndex { try await get([]) }

  // MARK: Signing in

  /// Emails a sign-in link and a 6-digit code to `email`. The answer is the
  /// same whether or not the address has an account.
  public func startSignIn(email: String) async throws -> SignInStarted {
    try await send("POST", ["auth", "start"], body: ["email": email])
  }

  /// Trades the code from the email for a token.
  public func finishSignIn(loginId: String, code: String) async throws -> SignedIn {
    try await send("POST", ["auth", "verify"], body: ["login_id": loginId, "code": code])
  }

  /// Trades the email's link for a token.
  public func finishSignIn(_ link: SignInLink) async throws -> SignedIn {
    try await send("POST", ["auth", "verify"], body: ["login_id": link.loginId, "token": link.token])
  }

  /// Ends this token; other devices stay signed in.
  public func signOut(token: String) async throws {
    try await sendEmpty("POST", ["auth", "signout"], token: token)
  }

  // MARK: Your account

  public func me(token: String) async throws -> Me { try await send("GET", ["me"], token: token) }

  /// Changes your name. The first name you give also sets your handle,
  /// which never changes after.
  public func updateMe(token: String, name: String) async throws -> Me {
    try await send("PATCH", ["me"], body: ["name": name], token: token)
  }

  /// Sets your profile photo: a JPEG, PNG or WebP of at most 4 MB, cropped
  /// square before it's sent (the server crops from the middle otherwise).
  /// The server's moderator looks first: a photo it won't show is a 422
  /// whose message says why, for you to read.
  public func setAvatar(_ photo: Data, type: String = "image/jpeg", token: String) async throws -> Me {
    var request = request("PUT", ["me", "avatar"], token: token)
    request.setValue(type, forHTTPHeaderField: "Content-Type")
    request.httpBody = photo
    let (data, status) = try await perform(request)
    return try APIClient.answer(data, status: status)
  }

  /// Takes your profile photo down; your first letter shows again.
  public func removeAvatar(token: String) async throws -> Me {
    try await send("DELETE", ["me", "avatar"], token: token)
  }

  /// Deletes your account and everything it made. It can't be undone.
  public func deleteMe(token: String) async throws {
    try await sendEmpty("DELETE", ["me"], token: token)
  }

  /// The URL for a route: each part escaped as one path segment, and each
  /// query value escaped whole (a cursor's "+" or "=" stays itself).
  public func url(_ path: [String], _ query: [URLQueryItem] = []) -> URL {
    var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
    for part in path { components.percentEncodedPath += "/" + APIClient.escape(part) }
    if !query.isEmpty {
      components.percentEncodedQueryItems = query.map { URLQueryItem(name: APIClient.escape($0.name), value: $0.value.map(APIClient.escape)) }
    }
    return components.url!
  }

  private static func escape(_ text: String) -> String {
    text.addingPercentEncoding(withAllowedCharacters: unreserved)!
  }

  private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

  func get<T: Decodable>(_ path: [String], _ query: [URLQueryItem] = [], token: String? = nil) async throws -> T {
    let (data, status) = try await perform(request("GET", path, query: query, token: token))
    return try APIClient.answer(data, status: status)
  }

  private func send<T: Decodable>(_ method: String, _ path: [String], body: [String: String]? = nil, token: String? = nil) async throws -> T {
    let (data, status) = try await perform(request(method, path, body: body, token: token))
    return try APIClient.answer(data, status: status)
  }

  /// A request whose answer has no body (204).
  private func sendEmpty(_ method: String, _ path: [String], token: String) async throws {
    let (data, status) = try await perform(request(method, path, token: token))
    let _: Empty = try APIClient.answer(status == 204 ? Data("{}".utf8) : data, status: status)
  }

  /// The request for a route: JSON both ways, and the token when there is one.
  func request(_ method: String, _ path: [String], query: [URLQueryItem] = [], body: [String: String]? = nil, token: String? = nil) -> URLRequest {
    var request = URLRequest(url: url(path, query))
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
    if let token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      // A signed-in answer is only ever for this person.
      request.cachePolicy = .reloadIgnoringLocalCacheData
    }
    return request
  }

  private func perform(_ request: URLRequest) async throws -> (Data, Int) {
    let (data, response) = try await session.data(for: request)
    return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
  }

  /// A response's body as T, or the server's error when it said no.
  static func answer<T: Decodable>(_ data: Data, status: Int) throws -> T {
    guard (200..<300).contains(status) else {
      if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
        throw APIError(status: status, code: body.error.code, message: body.error.message)
      }
      throw APIError(status: status, code: "http_\(status)", message: HTTPURLResponse.localizedString(forStatusCode: status))
    }
    return try APIClient.decoder.decode(T.self, from: data)
  }

  /// snake_case keys; times as ISO 8601, with or without milliseconds.
  public static var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom { decoder in
      let text = try decoder.singleValueContainer().decode(String.self)
      if let date = try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)) {
        return date
      }
      if let date = try? Date(text, strategy: .iso8601) { return date }
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 time: \(text)"))
    }
    return decoder
  }
}

private struct Empty: Decodable {}
private struct NearSigns: Decodable { var signs: [Sign] }
private struct Players: Decodable { var players: [Player] }
private struct ErrorBody: Decodable {
  struct Body: Decodable { var code: String; var message: String }
  var error: Body
}
