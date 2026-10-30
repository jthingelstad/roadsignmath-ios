import Foundation
import Observation
import RoadSignMathAPI

/// Who's signed in, and the sign-in in progress.
///
/// The token lives in the Keychain (`KeychainTokenStore`), one per server.
/// What the app last knew about you (`Me`, nothing secret) is kept in
/// UserDefaults so your avatar shows the moment the app opens; the server
/// is asked again in the background. Any signed-in call the server answers
/// with 401 signs you out, quietly, with a word about why.
@MainActor @Observable
final class Account {
  /// The sign-in screen's steps.
  enum Step: Equatable {
    case email
    case code
    /// Signed in for the first time: give a name.
    case name
    /// The moment you're in.
    case welcome
  }

  /// A sign-in waiting for its code: each email sent this time, newest
  /// first, since a code from an earlier email still works.
  struct Pending: Codable, Equatable {
    var email: String
    var logins: [String]
    var expires: Date
  }

  let client: APIClient
  private let tokens: any TokenStore
  private let defaults: UserDefaults
  private let key: String

  private(set) var me: Me?
  private var token: String?
  var signedIn: Bool { token != nil }

  /// The sign-in screen is showing, and on which step.
  var signingIn = false
  var step: Step = .email
  private(set) var pending: Pending?
  /// Bumped whenever the sign-in in progress is over or replaced (signed
  /// in, another email, signed out), so a late answer to an email sent
  /// before then is dropped.
  private var attempt = 0
  /// A word for the person after something happened on its own: signed
  /// out by the server, account deleted.
  var notice: String?

  init(client: APIClient, tokens: (any TokenStore)? = nil, defaults: UserDefaults = .standard) {
    self.client = client
    self.tokens = tokens ?? KeychainTokenStore(server: client.base)
    self.defaults = defaults
    key = "account:" + client.base.absoluteString
    // The Keychain outlives the app: a token left from before it was
    // deleted and installed again is forgotten, so deleting the app signs
    // you out, as people expect.
    if !defaults.bool(forKey: key + ":installed") {
      try? self.tokens.clear()
      defaults.set(true, forKey: key + ":installed")
    }
    token = try? self.tokens.read()
    if token != nil, let saved = defaults.data(forKey: key + ":me") {
      me = try? JSONDecoder().decode(Me.self, from: saved)
    }
    if let saved = defaults.data(forKey: key + ":pending"),
      let pending = try? JSONDecoder().decode(Pending.self, from: saved), pending.expires > .now
    {
      self.pending = pending
    }
  }

  // MARK: Signing in

  /// Signed in, but the app closed before you gave a name (and you didn't
  /// say "Not now"): back to the name.
  func resumeNaming() {
    guard signedIn, me?.needsName == true, !defaults.bool(forKey: key + ":nameLater") else { return }
    step = .name
    signingIn = true
  }

  /// "Not now" on the name: Me asks again, the launch doesn't.
  func nameLater() {
    defaults.set(true, forKey: key + ":nameLater")
    step = .welcome
  }

  /// Opens the sign-in screen, at the code when an email is still waiting.
  func beginSignIn() {
    guard !signedIn else { return }
    if let pending, pending.expires > .now { step = .code } else { step = .email; pending = nil }
    signingIn = true
  }

  /// Emails a link and a code. `again` keeps the earlier emails' codes
  /// working alongside the new one.
  func start(email raw: String, again: Bool = false) async throws {
    let email = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let sent = attempt
    let started = try await client.startSignIn(email: email)
    // Signed in by a code or the link meanwhile, or gone back for another
    // email: this answer is no longer wanted.
    guard sent == attempt, !signedIn else { return }
    let expires = Date.now.addingTimeInterval(TimeInterval(started.expiresIn))
    var logins = again && pending?.email == email ? pending?.logins ?? [] : []
    logins.insert(started.loginId, at: 0)
    setPending(Pending(email: email, logins: Array(logins.prefix(5)), expires: expires))
    step = .code
  }

  /// The code from any email sent this time. A wrong code says so; when
  /// every sign-in has said no, the newest one's answer is the one shown.
  func verify(code: String) async throws {
    guard let pending else { throw SignInProblem.noEmail }
    let typed = attempt
    var first: (any Error)?
    for login in pending.logins {
      do {
        accept(try await client.finishSignIn(loginId: login, code: code), from: typed)
        return
      } catch let error as APIError where error.isUnauthorized {
        first = first ?? error
        // Only an older email's sign-in is worth a try after a no.
        if typed != attempt { break }
        continue
      }
    }
    throw first ?? SignInProblem.noEmail
  }

  /// The link in the email, opened on this phone.
  func open(_ link: SignInLink) async {
    if signedIn {
      notice = "You’re already signed in" + (me.map { $0.name.isEmpty ? "." : " as \($0.name)." } ?? ".")
      return
    }
    signingIn = true
    let tapped = attempt
    do {
      accept(try await client.finishSignIn(link), from: tapped)
    } catch {
      // Signed in by a code meanwhile: the link's no doesn't matter.
      guard !signedIn else { return }
      linkProblem = Account.say(error, link: true)
      if pending != nil { step = .code } else { step = .email }
    }
  }

  /// What went wrong with a link, shown on the sign-in screen.
  var linkProblem: String?

  /// A sign-in the server said yes to, kept only if it still answers the
  /// sign-in in progress: gone back for another email, or signed in some
  /// other way meanwhile, it's let go and its session ended on the server.
  private func accept(_ done: SignedIn, from started: Int) {
    guard started == attempt, !signedIn else {
      Task { [client] in try? await client.signOut(token: done.token) }
      return
    }
    signedIn(done)
  }

  private func signedIn(_ done: SignedIn) {
    do { try tokens.save(done.token) } catch {
      // Still signed in for now; the next launch asks again.
    }
    attempt += 1
    token = done.token
    remember(done.me)
    setPending(nil)
    linkProblem = nil
    step = done.me.needsName ? .name : .welcome
  }

  /// Gives a name. The first one also makes your page's address for good.
  func setName(_ name: String) async throws {
    let me = try await authorized { try await client.updateMe(token: $0, name: name) }
    remember(me)
  }

  func finishSignIn() {
    signingIn = false
    step = .email
  }

  /// Back to the email field, forgetting the emails sent.
  func useAnotherEmail() {
    attempt += 1
    linkProblem = nil
    setPending(nil)
    step = .email
  }

  // MARK: Signed in

  /// Asks the server who you are, now and then; a 401 signs you out.
  func refresh() async {
    guard signedIn else { return }
    if let me = try? await authorized({ try await client.me(token: $0) }) { remember(me) }
  }

  func signOut() async {
    if let token { try? await client.signOut(token: token) }
    forget()
  }

  /// Deletes the account and everything it made, then signs out.
  func deleteAccount() async throws {
    try await authorized { try await client.deleteMe(token: $0) }
    forget()
    notice = "Your account is deleted. Thanks for playing."
  }

  /// A call with the token. A 401 means the token has ended: sign out and
  /// say so, then pass the error on. An answer that arrives after a sign
  /// out (or a sign-in as someone else) is for a session that's over, so
  /// it's dropped the same way.
  private func authorized<T>(_ call: (String) async throws -> T) async throws -> T {
    guard let token else { throw SignInProblem.signedOut }
    do {
      let answer = try await call(token)
      guard self.token == token else { throw SignInProblem.signedOut }
      return answer
    } catch let error as APIError where error.isUnauthorized {
      if self.token == token {
        forget()
        notice = "You’ve been signed out. Sign in again whenever you like."
      }
      throw SignInProblem.signedOut
    }
  }

  private func remember(_ me: Me) {
    self.me = me
    defaults.set(try? JSONEncoder().encode(me), forKey: key + ":me")
  }

  private func forget() {
    attempt += 1
    defaults.removeObject(forKey: key + ":nameLater")
    try? tokens.clear()
    token = nil
    me = nil
    defaults.removeObject(forKey: key + ":me")
  }

  private func setPending(_ pending: Pending?) {
    self.pending = pending
    if let pending {
      defaults.set(try? JSONEncoder().encode(pending), forKey: key + ":pending")
    } else {
      defaults.removeObject(forKey: key + ":pending")
    }
  }

  // MARK: Words

  enum SignInProblem: Error {
    case noEmail, signedOut
  }

  /// A friendly sentence for what went wrong. The server's own messages
  /// are written for people ("That code isn't right."), so they're used
  /// as they are; the rest is said here.
  static func say(_ error: any Error, link: Bool = false) -> String {
    switch error {
    case SignInProblem.noEmail: return "That sign-in has ended. Ask for a new code."
    case SignInProblem.signedOut: return "You’ve been signed out. Sign in again whenever you like."
    case let error as APIError:
      switch error.code {
      case "internal", "unavailable": return "Road Sign Math isn’t answering just now. Try again in a minute."
      case "unauthorized" where link: return "That link has ended or was already used. Ask for a new code."
      // The server writes straight apostrophes; the app sets curly ones.
      default: return error.message.replacingOccurrences(of: "'", with: "’")
      }
    case let error as URLError:
      switch error.code {
      case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
        return "You’re offline. Try again when you have a signal."
      default: return "Road Sign Math isn’t answering just now. Try again in a minute."
      }
    default: return "Something went wrong. Try again."
    }
  }
}

extension Account {
  /// Where a sign-in link may come from: the live site, and in a Debug
  /// build the server it reads (`npm run dev` mails links to localhost).
  var linkHosts: Set<String> {
    var hosts: Set<String> = ["roadsignmath.xyz", "www.roadsignmath.xyz"]
    #if DEBUG
      if let host = client.base.host() { hosts.insert(host.lowercased()) }
    #endif
    return hosts
  }
}

/// Debug builds' launch arguments for screenshots and checks against
/// `npm run dev`: `-RSMSignIn <email>` opens sign-in and sends the email,
/// `-RSMCode <digits>` types into the code boxes, `-RSMName <name>` into
/// the name field (`-RSMNameSave YES` saves it), and `-RSMMe YES` opens Me. Release builds ignore them.
enum Script {
  static func value(_ key: String) -> String? {
    #if DEBUG
      return UserDefaults.standard.string(forKey: key)
    #else
      return nil
    #endif
  }

  /// Any launch argument that sets up a screen, so the first-run sign-in
  /// stays out of the way.
  /// A YES/NO launch argument.
  static func flag(_ key: String) -> Bool {
    #if DEBUG
      return UserDefaults.standard.bool(forKey: key)
    #else
      return false
    #endif
  }

  static var scripted: Bool {
    ["RSMTab", "RSMOpen", "RSMFocus", "RSMSearch"].contains { value($0) != nil } || flag("RSMMe")
  }
}

extension Me {
  /// The name to show, or a stand-in until there is one.
  var shownName: String { name.isEmpty ? "New player" : name }
}
