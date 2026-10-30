import Foundation

/// The server's read routes. Nothing here writes: posting, solving,
/// reporting and signing in come later, each with its own review.
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
  public func signs(cursor: String? = nil, limit: Int? = nil) async throws -> SignPage {
    var query: [URLQueryItem] = []
    if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
    if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
    return try await get(["signs"], query)
  }

  /// One sign, by id or slug, with every way found so far.
  public func sign(_ idOrSlug: String) async throws -> SignDetail {
    try await get(["signs", idOrSlug])
  }

  /// Signs nearest a place, nearest first, each with its `miles`.
  public func signs(nearLatitude lat: Double, longitude lng: Double) async throws -> [Sign] {
    let near: NearSigns = try await get(["signs", "near"], [
      URLQueryItem(name: "lat", value: String(lat)), URLQueryItem(name: "lng", value: String(lng)),
    ])
    return near.signs
  }

  /// Every sign's pin, and the years they were found in.
  public func map() async throws -> MapPins { try await get(["map"]) }

  public func players() async throws -> [Player] {
    let players: Players = try await get(["players"])
    return players.players
  }

  /// One player, with their signs.
  public func player(_ handle: String) async throws -> Player { try await get(["players", handle]) }

  public func index() async throws -> APIIndex { try await get([]) }

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

  private func get<T: Decodable>(_ path: [String], _ query: [URLQueryItem] = []) async throws -> T {
    var request = URLRequest(url: url(path, query))
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: request)
    return try APIClient.answer(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
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

private struct NearSigns: Decodable { var signs: [Sign] }
private struct Players: Decodable { var players: [Player] }
private struct ErrorBody: Decodable {
  struct Body: Decodable { var code: String; var message: String }
  var error: Body
}
