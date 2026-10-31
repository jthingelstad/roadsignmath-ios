import Foundation
import Testing

@testable import SignCapture

@Suite struct WayDraftTests {
  /// The sample sign's numbers, all kept: 8, 7, 82, 90, 1.
  var sample: [CheckedNumber] {
    var list = NumberList()
    for n in SampleSign.numbers { try! list.add(n) }
    return list.kept
  }

  func tile(_ value: String, in tiles: [CheckedNumber]) -> CheckedNumber.ID {
    tiles.first { $0.valueText == value }!.id
  }

  @Test func aPostedSignsNumbersAreTiles() {
    let tiles = WayDraft.tiles(onSign: ["90", "82", "8", "7", "0.5", "7", "EXIT"])
    #expect(tiles.map(\.text) == ["90", "82", "8", "7", "0.5", "7"])
    #expect(tiles.map(\.valueText) == ["90", "82", "8", "7", "0.5", "7"])
    #expect(Set(tiles.map(\.id)).count == tiles.count)
    // A number the sign shows twice goes in twice.
    let draft = WayDraft(tiles: tiles, text: "(90 − 82) × 7 = 7 × 8")
    #expect(draft.usedCount == 5)
    #expect(draft.status.works)
  }

  @Test func tilesGoInOnceAndComeBackOut() {
    var draft = WayDraft(tiles: sample)
    let ninety = tile("90", in: sample)
    let first = draft.place(ninety)
    let again = draft.place(ninety)
    #expect(first)
    #expect(!again)
    #expect(draft.isUsed(ninety))
    draft.press(.subtract)
    draft.place(tile("82", in: sample))
    #expect(draft.usedCount == 2)
    draft.takeOut(ninety)
    #expect(!draft.isUsed(ninety))
    #expect(draft.text == "− 82")
  }

  @Test func aNumberTheSignShowsTwiceGoesInTwice() {
    var list = NumberList()
    for n in ["4", "4", "8"] { try! list.add(n) }
    var draft = WayDraft(tiles: list.kept, text: "4 + 4 = 8")
    #expect(draft.usedCount == 3)
    #expect(draft.status.works)
    // A third 4 has no tile, so it's left out.
    draft = WayDraft(tiles: list.kept, text: "4 + 4 + 4")
    #expect(draft.usedCount == 2)
  }

  @Test func saysHowTheMathReadsAsItIsWritten() {
    var draft = WayDraft(tiles: sample)
    #expect(draft.status == .empty)
    draft = WayDraft(tiles: sample, text: "(90 − 82) ÷")
    #expect(draft.status == .writing)
    draft = WayDraft(tiles: sample, text: "(90 − 82")
    #expect(draft.status == .writing)
    draft = WayDraft(tiles: sample, text: "90 − 82")
    #expect(draft.status == .oneSide("8"))
    draft = WayDraft(tiles: sample, text: "90 − 82 = 7")
    #expect(draft.status == .notTrue(["8", "7"]))
    draft = WayDraft(tiles: sample, text: "8 ÷ (7 − 7")
    // One 7 only: "8 ÷ (7 −" waits for more.
    #expect(draft.status == .writing)
    draft = WayDraft(tiles: sample, text: "8 )")
    #expect(draft.status == .problem("Unexpected “)”"))
  }

  @Test func itWorksWithEveryNumber() {
    let draft = WayDraft(tiles: sample, text: "(90 − 82) ÷ 8 = 1^7")
    guard case .works(let solved) = draft.status else {
      Issue.record("Expected it to work: \(draft.status)")
      return
    }
    #expect(solved.canonical == "(90 − 82) ÷ 8 = 1^7")
    #expect(draft.usesEveryNumber)
  }

  @Test func itWorksWithoutEveryNumber() {
    let draft = WayDraft(tiles: sample, text: "90 − 82 = 8")
    #expect(draft.status.works)
    #expect(!draft.usesEveryNumber)
  }

  @Test func drawsABoxWhereTheNextPieceGoes() {
    #expect(WayDraft(tiles: sample, text: "(90 − 82) ÷").tex == "\\frac{90 - 82}{\\square}")
    #expect(WayDraft(tiles: sample, text: "(90 − 82").tex == "\\left(90 - 82\\right)")
    #expect(WayDraft(tiles: sample, text: "√").tex == "\\sqrt{\\square}")
    #expect(WayDraft(tiles: sample, text: "90 =").tex == "90 = \\square")
    #expect(WayDraft(tiles: sample, text: "×").tex == nil)
    #expect(WayDraft(tiles: sample).tex == nil)
  }

  @Test func showsTheTextAsWritten() {
    let draft = WayDraft(tiles: sample, text: "(90 − 82) ÷ 8 = √1 + 7!")
    #expect(draft.shownText == "(90 − 82) ÷ 8 = √1 + 7!")
  }

  @Test func followsChangesToTheNumbers() {
    var list = NumberList()
    for n in SampleSign.numbers { try! list.add(n) }
    var draft = WayDraft(tiles: list.kept, text: "90 − 82 = 8")
    let eightyTwo = tile("82", in: list.kept)
    let eight = tile("8", in: list.kept)
    try! list.fix(eightyTwo, to: "83")
    list.toggle(eight)
    draft.retile(list.kept)
    #expect(draft.text == "90 − 83 =")
    #expect(draft.tiles.count == 4)
  }

  @Test func stopsAtTheLimit() {
    var draft = WayDraft(tiles: sample)
    for _ in 0..<WayDraft.limit { draft.press(.open) }
    let pressed = draft.press(.open)
    let placed = draft.place(tile("8", in: sample))
    #expect(!pressed)
    #expect(!placed)
  }
}
