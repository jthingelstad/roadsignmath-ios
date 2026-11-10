import Foundation

/// Work given the short while the system allows after the app leaves the
/// screen: views still to send, a post on its way. The system is asked for
/// the time as the work starts, and it's handed back exactly once, when
/// the work finishes or the time runs out, whichever is first (an app that
/// keeps it past then is ended, not suspended).
///
/// When the time runs out the work is cancelled. Work that mustn't be cut
/// short (a post already on the wire) should be a wait for it, so the
/// cancel only ends the waiting.
///
/// The app passes `UIApplication`'s `beginBackgroundTask` and
/// `endBackgroundTask`; the tests pass their own, so this needs no UIKit.
@MainActor
public final class BackgroundTime<Token: Sendable> {
  private var token: Token?
  private var end: (@MainActor (Token) -> Void)?
  private var work: Task<Void, Never>?

  public init() {}

  /// Whether the system's time is still held.
  public var holding: Bool { token != nil }

  /// - Parameters:
  ///   - begin: Asks the system for time and gives it what to run when the
  ///     time is up. Nil when the system has none to give: the work still
  ///     runs, for as long as the app does.
  ///   - end: Hands the time back.
  public func start(
    begin: (_ expired: @escaping @MainActor @Sendable () -> Void) -> Token?,
    end: @escaping @MainActor (Token) -> Void,
    work job: @escaping @MainActor () async -> Void
  ) {
    self.end = end
    token = begin { [self] in
      work?.cancel()
      finish()
    }
    work = Task { [self] in
      await job()
      finish()
    }
  }

  private func finish() {
    guard let token, let end else { return }
    self.token = nil
    self.end = nil
    end(token)
  }
}
