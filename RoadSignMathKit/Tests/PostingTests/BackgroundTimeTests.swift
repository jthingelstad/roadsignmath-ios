import Foundation
import Testing

@testable import Posting

/// The time the system allows after the app leaves the screen: asked for
/// once, and handed back once, whether the work finishes or the time runs
/// out first. The system here is a stand-in that counts.
@MainActor @Suite struct BackgroundTimeTests {
  /// What the system was asked and told.
  @MainActor final class System {
    var asked = 0
    var ended: [Int] = []
    var expire: (@MainActor @Sendable () -> Void)?
    /// Whether it has time to give.
    var gives = true

    func begin(_ expired: @escaping @MainActor @Sendable () -> Void) -> Int? {
      asked += 1
      expire = expired
      return gives ? asked : nil
    }
  }

  /// Work that waits to be told to finish, and says how it ended.
  @MainActor final class Work {
    var started = false
    var finished = false
    var cancelled = false
    var release = false

    func run() async {
      started = true
      while !release, !Task.isCancelled { await Task.yield() }
      cancelled = Task.isCancelled
      finished = true
    }
  }

  func wait(_ done: @MainActor () -> Bool) async {
    for _ in 0..<100_000 where !done() { await Task.yield() }
  }

  @Test func handsTheTimeBackWhenTheWorkFinishes() async {
    let system = System()
    let work = Work()
    let time = BackgroundTime<Int>()
    time.start(begin: system.begin, end: { system.ended.append($0) }) { await work.run() }
    #expect(system.asked == 1)
    #expect(time.holding)
    await wait { work.started }
    #expect(system.ended.isEmpty)
    work.release = true
    await wait { !time.holding }
    #expect(system.ended == [1])
    #expect(!work.cancelled)
    // The system's "time's up" after that does nothing more.
    system.expire?()
    #expect(system.ended == [1])
  }

  @Test func whenTheTimeRunsOutTheWorkIsCancelledAndTheTimeHandedBackOnce() async {
    let system = System()
    let work = Work()
    let time = BackgroundTime<Int>()
    time.start(begin: system.begin, end: { system.ended.append($0) }) { await work.run() }
    await wait { work.started }
    system.expire?()
    // Handed back before "time's up" returns: the system ends an app that
    // still holds it then.
    #expect(system.ended == [1])
    #expect(!time.holding)
    await wait { work.finished }
    #expect(work.cancelled)
    await Task.yield()
    #expect(system.ended == [1])
  }

  @Test func withNoTimeToGiveTheWorkStillRuns() async {
    let system = System()
    system.gives = false
    let work = Work()
    let time = BackgroundTime<Int>()
    time.start(begin: system.begin, end: { system.ended.append($0) }) { await work.run() }
    #expect(!time.holding)
    await wait { work.started }
    work.release = true
    await wait { work.finished }
    await Task.yield()
    #expect(system.ended.isEmpty)
  }
}
