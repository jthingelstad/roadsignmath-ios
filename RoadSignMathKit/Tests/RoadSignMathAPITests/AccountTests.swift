import Foundation
import Synchronization
import Testing

@testable import RoadSignMathAPI

/// Signing in and the account: the JSON, the requests the client sends,
/// the link in the email, the handle preview and the token stores. The
/// requests go to a stub, never a server.
@Suite struct AccountTests {
  func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources")))
  }

  @Test func readsASignIn() throws {
    let done: SignedIn = try APIClient.answer(fixture("signed-in"), status: 200)
    #expect(done.token.hasPrefix("rsm_"))
    #expect(done.newPlayer)
    #expect(done.me.needsName)
    #expect(done.me.name.isEmpty)
    #expect(done.me.firstYear == nil)
    #expect(done.me.email == "player@example.com")
  }

  @Test func readsMe() throws {
    let me: Me = try APIClient.answer(fixture("me"), status: 200)
    #expect(me.handle == "zoe-quinn")
    #expect(me.name == "Zoë Quinn")
    #expect(!me.needsName)
    #expect(me.signCount == 3)
    #expect(me.states == ["MN", "IA"])
    #expect(me.bio == "Driving + Math = Fun.")
  }

  @Test func aWrongCodeIsUnauthorized() throws {
    let error = #expect(throws: APIError.self) {
      let _: SignedIn = try APIClient.answer(fixture("wrong-code"), status: 401)
    }
    #expect(error?.isUnauthorized == true)
    #expect(error?.message == "That code isn't right.")
  }

  // MARK: Requests

  @Test func startsASignIn() async throws {
    let stub = Stub(status: 202, body: #"{"login_id":"01ABC","expires_in":900}"#)
    let started = try await stub.client.startSignIn(email: "player@example.com")
    #expect(started == SignInStarted(loginId: "01ABC", expiresIn: 900))
    let sent = try #require(stub.requests.first)
    #expect(sent.method == "POST")
    #expect(sent.path == "/api/v1/auth/start")
    #expect(sent.body == ["email": "player@example.com"])
    #expect(sent.authorization == nil)
  }

  @Test func finishesWithTheCodeOrTheLink() async throws {
    let stub = Stub(status: 200, body: String(decoding: try fixture("signed-in"), as: UTF8.self))
    _ = try await stub.client.finishSignIn(loginId: "01ABC", code: "012345")
    _ = try await stub.client.finishSignIn(SignInLink(loginId: "01ABC", token: "tok-en_"))
    #expect(stub.requests.map(\.path) == ["/api/v1/auth/verify", "/api/v1/auth/verify"])
    #expect(stub.requests[0].body == ["login_id": "01ABC", "code": "012345"])
    #expect(stub.requests[1].body == ["login_id": "01ABC", "token": "tok-en_"])
  }

  @Test func sendsTheTokenForTheAccount() async throws {
    let stub = Stub(status: 200, body: String(decoding: try fixture("me"), as: UTF8.self))
    _ = try await stub.client.me(token: "rsm_x")
    _ = try await stub.client.updateMe(token: "rsm_x", name: "Zoë")
    #expect(stub.requests.map(\.method) == ["GET", "PATCH"])
    #expect(stub.requests.allSatisfy { $0.path == "/api/v1/me" && $0.authorization == "Bearer rsm_x" })
    #expect(stub.requests[1].body == ["name": "Zoë"])
  }

  @Test func deletesAndSignsOutWithNoBody() async throws {
    let stub = Stub(status: 204, body: "")
    try await stub.client.deleteMe(token: "rsm_x")
    try await stub.client.signOut(token: "rsm_x")
    #expect(stub.requests.map(\.method) == ["DELETE", "POST"])
    #expect(stub.requests.map(\.path) == ["/api/v1/me", "/api/v1/auth/signout"])
  }

  @Test func anEndedTokenThrows() async throws {
    let stub = Stub(status: 401, body: #"{"error":{"code":"unauthorized","message":"That token has ended. Sign in again."}}"#)
    let error = await #expect(throws: APIError.self) { try await stub.client.deleteMe(token: "rsm_x") }
    #expect(error?.isUnauthorized == true)
  }

  // MARK: The link

  @Test func readsTheEmailsLink() throws {
    let live = try #require(URL(string: "https://roadsignmath.xyz/signin?l=01M67J6519K2ZH5R0MEREBFE2E&t=MeZk-Fi5_vun"))
    #expect(SignInLink(live) == SignInLink(loginId: "01M67J6519K2ZH5R0MEREBFE2E", token: "MeZk-Fi5_vun"))
    let app = try #require(URL(string: "roadsignmath://signin?l=01A&t=b"))
    #expect(SignInLink(app) == SignInLink(loginId: "01A", token: "b"))
    let dev = try #require(URL(string: "http://localhost:8787/signin?l=01A&t=b"))
    #expect(SignInLink(dev) == nil)
    #expect(SignInLink(dev, hosts: ["localhost"]) == SignInLink(loginId: "01A", token: "b"))
  }

  @Test func ignoresOtherLinks() throws {
    for text in [
      "https://roadsignmath.xyz/signs/genesis",
      "https://roadsignmath.xyz/signin?l=01A",
      "https://roadsignmath.xyz/signin?t=b",
      "https://roadsignmath.xyz/signin?l=&t=b",
      "http://roadsignmath.xyz/signin?l=01A&t=b",
      "https://example.com/signin?l=01A&t=b",
      "https://roadsignmath.xyz.example.com/signin?l=01A&t=b",
      "roadsignmath://signs?l=01A&t=b",
    ] {
      #expect(SignInLink(try #require(URL(string: text))) == nil, "\(text)")
    }
  }

  // MARK: The handle a name makes

  @Test func previewsTheHandleAsTheServerMakesIt() {
    #expect(Handle.preview(for: "Jamie") == "jamie")
    #expect(Handle.preview(for: "Zoë Quinn-Test") == "zoe-quinn-test")
    #expect(Handle.preview(for: "  The Math   Car!! ") == "the-math-car")
    #expect(Handle.preview(for: "José Álvarez") == "jose-alvarez")
    #expect(Handle.preview(for: "Sign") == nil)
    #expect(Handle.preview(for: "李") == nil)
    #expect(Handle.preview(for: "---") == nil)
    // At most 30 characters, never ending in a hyphen.
    #expect(Handle.preview(for: "abcdefghij abcdefghij abcdefghij") == "abcdefghij-abcdefghij-abcdefgh")
    #expect(Handle.preview(for: "abcdefghij abcdefghij abcdefgh ij") == "abcdefghij-abcdefghij-abcdefgh")
    #expect(Handle.preview(for: "abcdefghij abcdefghij abcdefg hij") == "abcdefghij-abcdefghij-abcdefg")
  }

  // MARK: Token stores

  @Test func keepsATokenInMemory() throws {
    let store = MemoryTokenStore()
    #expect(try store.read() == nil)
    try store.save("rsm_a")
    try store.save("rsm_b")
    #expect(try store.read() == "rsm_b")
    try store.clear()
    #expect(try store.read() == nil)
  }

  /// The Keychain needs an app's entitlements on a Mac; a plain test run
  /// has none, so this runs where the Keychain answers (the simulator).
  @Test(.enabled(if: KeychainProbe.works)) func keepsATokenInTheKeychain() throws {
    let store = KeychainTokenStore(service: "xyz.roadsignmath.tests", account: UUID().uuidString)
    defer { try? store.clear() }
    #expect(try store.read() == nil)
    try store.save("rsm_a")
    try store.save("rsm_b")
    #expect(try store.read() == "rsm_b")
    try store.clear()
    #expect(try store.read() == nil)
    try store.clear()
  }
}

enum KeychainProbe {
  static let works: Bool = {
    let store = KeychainTokenStore(service: "xyz.roadsignmath.tests", account: "probe-\(UUID().uuidString)")
    defer { try? store.clear() }
    return (try? store.save("probe")) != nil
  }()
}

// MARK: A stub server

/// A client whose requests are answered with one canned answer and kept
/// for checking. Each stub has its own host, so tests run side by side.
final class Stub: Sendable {
  struct Sent: Sendable {
    var method: String
    var path: String
    var authorization: String?
    var body: [String: String]?
  }

  let host = "stub-\(UUID().uuidString.lowercased()).invalid"
  let client: APIClient

  init(status: Int, body: String) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    client = APIClient(base: URL(string: "https://\(host)/api/v1")!, session: URLSession(configuration: config))
    StubProtocol.answers.withLock { $0[host] = (status, Data(body.utf8)) }
  }

  var requests: [Sent] { StubProtocol.sent.withLock { $0[host] ?? [] } }
}

final class StubProtocol: URLProtocol {
  static let answers = Mutex<[String: (Int, Data)]>([:])
  static let sent = Mutex<[String: [Stub.Sent]]>([:])

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let host = request.url?.host ?? ""
    var bodyData = request.httpBody
    if bodyData == nil, let stream = request.httpBodyStream {
      stream.open()
      var data = Data()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
      }
      stream.close()
      bodyData = data
    }
    let body = bodyData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
    let sent = Stub.Sent(method: request.httpMethod ?? "GET", path: request.url?.path ?? "",
                         authorization: request.value(forHTTPHeaderField: "Authorization"), body: body)
    Self.sent.withLock { $0[host, default: []].append(sent) }
    let (status, data) = Self.answers.withLock { $0[host] } ?? (500, Data())
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
