import Foundation
import Testing

@testable import RoadSignMathAPI

@Suite struct KeptFeedTests {
  func signs() throws -> [Sign] {
    let data = try Data(contentsOf: #require(Bundle.module.url(forResource: "signs", withExtension: "json", subdirectory: "Resources")))
    let page: SignPage = try APIClient.answer(data, status: 200)
    return page.signs
  }

  func file() -> KeptFeedFile {
    KeptFeedFile(url: FileManager.default.temporaryDirectory.appending(path: "kept-\(UUID().uuidString).json"))
  }

  @Test func keepsTheSignsAsTheyWereRead() throws {
    let file = file()
    defer { file.clear() }
    let signs = try signs()
    let readAt = Date(timeIntervalSince1970: 1_761_940_440)
    file.save(KeptFeed(readAt: readAt, reader: "zoe", signs: signs))
    let kept = try #require(file.load(reader: "zoe"))
    #expect(kept.signs == signs)
    #expect(kept.readAt == readAt)
  }

  @Test func onlyTheSameReaderGetsThemBack() throws {
    let file = file()
    defer { file.clear() }
    file.save(KeptFeed(readAt: .now, reader: "zoe", signs: try signs()))
    // Zoe's hearts are hers: signed out, or as someone else, there's nothing kept.
    #expect(file.load(reader: nil) == nil)
    #expect(file.load(reader: "tyler") == nil)
    file.save(KeptFeed(readAt: .now, reader: nil, signs: try signs()))
    #expect(file.load(reader: nil) != nil)
    #expect(file.load(reader: "zoe") == nil)
  }

  @Test func keepsTheFirstPageOnly() throws {
    let one = try #require(try signs().first)
    let many = (0..<30).map { n in
      var sign = one
      sign.id = "sign-\(n)"
      return sign
    }
    let kept = KeptFeed(readAt: .now, reader: nil, signs: many)
    #expect(kept.signs.count == KeptFeed.most)
    #expect(kept.signs.last?.id == "sign-19")
  }

  @Test func nothingKeptOrUnreadableIsNothing() throws {
    let file = file()
    #expect(file.load(reader: nil) == nil)
    try Data("not json".utf8).write(to: file.url)
    defer { file.clear() }
    #expect(file.load(reader: nil) == nil)
  }

  @Test func eachServerHasItsOwn() {
    #expect(KeptFeedFile.name(APIClient.live) == "latest-roadsignmath.xyz.json")
    #expect(KeptFeedFile.name(URL(string: "http://localhost:8787")!) == "latest-localhost-8787.json")
  }
}
