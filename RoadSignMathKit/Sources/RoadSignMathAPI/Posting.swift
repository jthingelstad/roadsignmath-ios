import Foundation

// Posting a sign: `POST /photos` takes the photo, `POST /signs` posts it
// (API 1.4.0). Both need you signed in, and a name given first. And
// `GET /signs/similar`, the signs near a spot that share its numbers, so a
// sign posted twice can be noticed before it is.

/// `POST /photos`'s answer: the upload's id for `SignPost.photoIds`. The
/// server keeps an upload a day (`APIClient.uploadLife`), with its
/// metadata stripped.
public struct Upload: Codable, Sendable, Hashable {
  public var id: String
  public var width: Int
  public var height: Int

  public init(id: String, width: Int, height: Int) {
    self.id = id
    self.width = width
    self.height = height
  }
}

/// `POST /signs`'s body. Optional fields left nil are left out, so the
/// server's defaults apply: you as the finder, and no way (posted
/// unsolved).
public struct SignPost: Codable, Sendable, Hashable {
  public var photoIds: [String]
  public var title: String
  public var numbers: [PostNumber]
  public var place: PostPlace
  /// The day it was found, `2025-09-01`, in the finder's own time.
  public var foundOn: String
  public var finders: [PostFinder]?
  /// The first way, as math text; nil posts it unsolved.
  public var way: String?
  public var caption: String?

  public init(
    photoIds: [String] = [], title: String, numbers: [PostNumber], place: PostPlace, foundOn: String,
    finders: [PostFinder]? = nil, way: String? = nil, caption: String? = nil
  ) {
    self.photoIds = photoIds
    self.title = title
    self.numbers = numbers
    self.place = place
    self.foundOn = foundOn
    self.finders = finders
    self.way = way
    self.caption = caption
  }

  enum CodingKeys: String, CodingKey {
    case photoIds = "photo_ids", title, numbers, place, foundOn = "found_on", finders, way, caption
  }
}

/// A number on the sign as its poster checked it.
public struct PostNumber: Codable, Sendable, Hashable {
  /// Plain decimal text, `7` or `1.5`.
  public var value: String
  /// What it was read from, `EXIT 7B`, at most 40 characters.
  public var text: String?
  /// Why the value differs from the text, `Read as 7`, at most 60.
  public var why: String?
  /// Where on the photo: x, y, width, height as fractions, origin top left.
  public var box: [Double]?

  public init(value: String, text: String? = nil, why: String? = nil, box: [Double]? = nil) {
    self.value = value
    self.text = text
    self.why = why
    self.box = box
  }
}

public struct PostPlace: Codable, Sendable, Hashable {
  /// `Bloomington, MN`, at most 120 characters.
  public var label: String
  /// Two-letter US state.
  public var state: String?
  public var lat: Double?
  public var lng: Double?
  /// Placed by town, not where the photo was taken.
  public var approximate: Bool

  public init(label: String, state: String? = nil, lat: Double? = nil, lng: Double? = nil, approximate: Bool) {
    self.label = label
    self.state = state
    self.lat = lat
    self.lng = lng
    self.approximate = approximate
  }
}

/// Someone who found the sign: a player by handle, or a name for someone
/// who doesn't play, never both.
public struct PostFinder: Codable, Sendable, Hashable {
  public var handle: String?
  public var name: String?
  public var role: Finder.Role

  public static func player(_ handle: String, _ role: Finder.Role) -> PostFinder {
    PostFinder(handle: handle, name: nil, role: role)
  }

  public static func named(_ name: String, _ role: Finder.Role) -> PostFinder {
    PostFinder(handle: nil, name: name, role: role)
  }
}

extension APIClient {
  /// How long the server keeps an upload waiting to be posted, and
  /// remembers an `Idempotency-Key`: a day.
  public static let uploadLife: TimeInterval = 86_400
  /// The largest photo `POST /photos` takes.
  public static let photoBytes = 4 * 1024 * 1024
  public static let titleMax = 60
  public static let placeMax = 120
  public static let findersMax = 6
  public static let finderNameMax = 40

  /// Sends a photo, as it is: a JPEG, PNG or WebP of at most 4 MB.
  public func uploadPhoto(_ photo: Data, type: String = "image/jpeg", token: String) async throws -> Upload {
    var request = request("POST", ["photos"], token: token)
    request.setValue(type, forHTTPHeaderField: "Content-Type")
    request.httpBody = photo
    return try await answer(to: request)
  }

  /// Posts a sign from your uploads. The same `key` sent again (within a
  /// day) answers with the sign it made the first time, so a post retried
  /// after a lost answer is still one sign.
  public func postSign(_ post: SignPost, key: String, token: String) async throws -> SignDetail {
    var request = request("POST", ["signs"], token: token)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    request.httpBody = try encoder.encode(post)
    return try await answer(to: request)
  }

  /// Another way to make a sign true. The server checks the math and that
  /// its numbers are the sign's, and says no to a way someone already
  /// found (409). Answers with the sign, all its ways and, in `unlocked`,
  /// the badges the way earned.
  public func addWay(_ text: String, to signId: String, token: String) async throws -> SignDetail {
    try await answer(to: request("POST", ["signs", signId, "ways"], body: ["text": text], token: token))
  }

  /// Signs within 2 miles of a spot that share at least half of `numbers`,
  /// nearest first, each with its `miles`.
  public func similarSigns(latitude lat: Double, longitude lng: Double, numbers: [String]) async throws -> [Sign] {
    let query = [
      URLQueryItem(name: "lat", value: String(lat)), URLQueryItem(name: "lng", value: String(lng)),
      URLQueryItem(name: "numbers", value: numbers.prefix(30).joined(separator: ",")),
    ]
    let similar: SimilarSigns = try await answer(to: request("GET", ["signs", "similar"], query: query))
    return similar.signs
  }

  private func answer<T: Decodable>(to request: URLRequest) async throws -> T {
    let (data, response) = try await session.data(for: request)
    return try APIClient.answer(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
  }
}

private struct SimilarSigns: Decodable { var signs: [Sign] }
