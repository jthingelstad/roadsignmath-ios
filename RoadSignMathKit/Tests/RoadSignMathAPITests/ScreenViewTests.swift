import Foundation
import Synchronization
import Testing

@testable import RoadSignMathAPI

struct ScreenViewTests {
  @Test func pathsAreWhatTheServerTakes() {
    #expect(ViewPath.isValid("/"))
    #expect(ViewPath.isValid("/map"))
    #expect(ViewPath.isValid("/signs/i-35w-at-82nd-street"))
    #expect(ViewPath.sign("i-35w-at-82nd-street") == "/signs/i-35w-at-82nd-street")
    #expect(ViewPath.player("jamie") == "/players/jamie")
    #expect(!ViewPath.isValid(""))
    #expect(!ViewPath.isValid("map"))
    #expect(!ViewPath.isValid("/Map"))
    #expect(!ViewPath.isValid("/signs/"))
    #expect(!ViewPath.isValid("/a/b/c"))
    #expect(!ViewPath.isValid("/signs/a_b"))
    #expect(!ViewPath.isValid("/" + String(repeating: "a", count: 81)))
    #expect(ViewPath.sign("Not A Slug") == nil)
    // Ids are uppercase, which the server's VIEW_PATH refuses: a page
    // opened from an id link counts by its slug or handle.
    #expect(ViewPath.sign("01JS0000000000000000000001") == nil)
    #expect(ViewPath.player("01JS0000000000000000000001") == nil)
  }

  @Test func pageKeysFromLinks() {
    let id = "01JS0000000000000000000001"
    #expect(PageKey.isID(id))
    #expect(PageKey.normalized(id) == id)
    #expect(PageKey.normalized(id.lowercased()) == id)
    #expect(PageKey.normalized("i-35w-at-82nd-street") == "i-35w-at-82nd-street")
    #expect(PageKey.normalized("jamie") == "jamie")
    // Not a ULID: too short, an I, or a first character past 7.
    #expect(!PageKey.isID("01JS000000000000000000001"))
    #expect(!PageKey.isID("01JS000000000000000000000I"))
    #expect(!PageKey.isID("81JS0000000000000000000001"))
    #expect(PageKey.normalized("81js0000000000000000000001") == "81js0000000000000000000001")
  }

  @Test func sendsThePathsWithNoToken() async throws {
    let stub = Stub(status: 202, body: #"{"accepted":2}"#)
    let accepted = try await stub.client.countViews(["/", "/signs/x"])
    #expect(accepted == 2)
    let sent = try #require(stub.requests.first)
    #expect(sent.method == "POST")
    #expect(sent.path == "/api/v1/app/views")
    #expect(sent.authorization == nil)
    #expect(sent.headers["Content-Type"] == "application/json")
    let data = try #require(sent.data)
    let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(body.keys.sorted() == ["views"])
    let views = try #require(body["views"] as? [[String: String]])
    #expect(views == [["path": "/"], ["path": "/signs/x"]])
  }

  @Test func batchesAtMostTwentyAndDropsWhatTheServerWouldNot() async throws {
    let batches = Batches()
    let counter = ViewCounter(first: .milliseconds(10), every: .milliseconds(40)) { batches.add($0) }
    await counter.saw("/Not Valid")
    for n in 0..<25 { await counter.saw("/signs/s\(n)") }
    try await waitUntil { batches.count == 2 }
    #expect(batches.all[0].count == 20)
    #expect(batches.all[1] == (20..<25).map { "/signs/s\($0)" })
    #expect(await counter.pending.isEmpty)
  }

  @Test func offlineKeepsThemForTheNextBatch() async throws {
    let batches = Batches()
    let fails = Mutex(true)
    let counter = ViewCounter(first: .milliseconds(10), every: .milliseconds(30)) { paths in
      if fails.withLock({ let was = $0; $0 = false; return was }) { throw URLError(.notConnectedToInternet) }
      batches.add(paths)
    }
    await counter.saw("/map")
    try await waitUntil { batches.count == 1 }
    #expect(batches.all[0] == ["/map"])
  }

  @Test func aRefusedBatchIsDropped() async throws {
    let tries = Mutex(0)
    let counter = ViewCounter(first: .milliseconds(5), every: .milliseconds(10)) { _ in
      tries.withLock { $0 += 1 }
      throw APIError(status: 400, code: "bad_request", message: "no")
    }
    await counter.saw("/map")
    try await waitUntil { tries.withLock { $0 } == 1 }
    try await Task.sleep(for: .milliseconds(60))
    #expect(tries.withLock { $0 } == 1)
    #expect(await counter.pending.isEmpty)
  }

  @Test func aRateLimitRestsBeforeTheNext() async throws {
    let tries = Mutex(0)
    let counter = ViewCounter(first: .milliseconds(5), every: .milliseconds(10), rest: .seconds(60)) { _ in
      tries.withLock { $0 += 1 }
      throw APIError(status: 429, code: "rate_limited", message: "later")
    }
    await counter.saw("/map")
    try await waitUntil { tries.withLock { $0 } == 1 }
    await counter.saw("/")
    await counter.sendNow()
    try await Task.sleep(for: .milliseconds(60))
    #expect(tries.withLock { $0 } == 1)
    #expect(await counter.pending == ["/"])
  }

  @Test func sendNowGoesWithoutWaiting() async throws {
    let batches = Batches()
    let counter = ViewCounter(first: .seconds(60), every: .seconds(60)) { batches.add($0) }
    await counter.saw("/capture")
    await counter.sendNow()
    #expect(batches.all == [["/capture"]])
  }
}

private final class Batches: Sendable {
  private let sent = Mutex<[[String]]>([])
  func add(_ paths: [String]) { sent.withLock { $0.append(paths) } }
  var all: [[String]] { sent.withLock { $0 } }
  var count: Int { all.count }
}

private func waitUntil(_ done: @Sendable () -> Bool) async throws {
  for _ in 0..<200 where !done() { try await Task.sleep(for: .milliseconds(10)) }
  #expect(done())
}
