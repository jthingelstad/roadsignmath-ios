import Foundation
import Testing

@testable import SignCapture
import SignReading

/// A number read at a spot, as `SignReader` would give it.
func read(_ text: String, x: Double, y: Double, from source: String? = nil, height: Double = 0.05) -> ReadNumber {
  let found = NumberExtractor().numbers(inText: source ?? text)
  let number = found.first { $0.text == text } ?? found[0]
  var placed = number
  placed.box = NormalizedBox(x: x, y: y, width: 0.06, height: height)
  return placed
}

@Suite struct NumberListTests {
  /// The I-35W gantry's numbers, roughly where they are on the photo.
  var gantry: [ReadNumber] {
    [
      read("90", x: 0.62, y: 0.31, from: "90th"),
      read("7", x: 0.75, y: 0.18, from: "EXIT 7B"),
      read("8", x: 0.58, y: 0.185, from: "EXIT 8"),
      read("82", x: 0.48, y: 0.28, from: "82nd"),
      read("1", x: 0.5, y: 0.36, from: "1 MILE"),
    ]
  }

  @Test func readsInReadingOrderAllKept() {
    let list = NumberList(read: gantry)
    // 8 and 7 share a row though 7's box sits a little higher; 82 and 90
    // the next; 1 below.
    #expect(list.numbers.map(\.text) == ["8", "7", "82", "90", "1"])
    #expect(list.kept.count == 5)
    #expect(list.values == ["8", "7", "82", "90", "1"])
    #expect(list.problem == nil)
  }

  @Test func eachNumberSaysWhy() {
    let list = NumberList(read: gantry)
    let why = Dictionary(uniqueKeysWithValues: list.numbers.map { ($0.text, $0.why) })
    #expect(why["7"] == "Read as 7")
    #expect(why["82"] == "Letters dropped")
    #expect(why["1"] == "Read from the photo")
    #expect(list.numbers.first { $0.text == "7" }?.sourceText == "7B")
  }

  @Test func untickingLeavesANumberOutButInTheList() throws {
    var list = NumberList(read: gantry)
    let one = try #require(list.numbers.last)
    list.toggle(one.id)
    #expect(list.numbers.count == 5)
    #expect(list.values == ["8", "7", "82", "90"])
    list.setKept(true, for: one.id)
    #expect(list.values.count == 5)
  }

  @Test func nothingKeptCantGoOn() {
    var list = NumberList(read: gantry)
    for number in list.numbers { list.setKept(false, for: number.id) }
    #expect(list.problem == .nothingKept)
    #expect(NumberList().problem == .nothingKept)
  }

  @Test func tooManyNumbersSaysHowManyToUntick() {
    let many = (0..<33).map { read("\($0 + 1)", x: Double($0) / 40, y: 0.1) }
    let list = NumberList(read: many)
    #expect(list.problem == .tooMany(33))
    #expect(list.problem?.message.contains("Untick 3") == true)
  }

  @Test func fixingChangesTheValueAndSaysSo() throws {
    var list = NumberList(read: gantry)
    let ninety = try #require(list.numbers.first { $0.text == "90" })
    list.setKept(false, for: ninety.id)
    let fixed = try #require(try list.fix(ninety.id, to: "98"))
    #expect(fixed.value == 98)
    #expect(fixed.kept)
    #expect(fixed.isFixed)
    #expect(fixed.why == "You fixed it (we read 90)")
    #expect(fixed.box == ninety.box)
    #expect(list.values == ["8", "7", "82", "98", "1"])
  }

  @Test func fixingBackToTheReadingIsAsRead() throws {
    var list = NumberList(read: gantry)
    let seven = try #require(list.numbers.first { $0.text == "7" })
    try list.fix(seven.id, to: "1")
    try list.fix(seven.id, to: "7B")
    let again = try #require(list[seven.id])
    #expect(!again.isFixed)
    #expect(again.why == "Read as 7")
    try list.fix(seven.id, to: "4")
    list.restore(seven.id)
    #expect(list[seven.id]?.text == "7")
  }

  @Test func aBadFixChangesNothing() throws {
    var list = NumberList(read: gantry)
    let eight = try #require(list.numbers.first)
    #expect(throws: NumberEntry.Problem.notANumber) { try list.fix(eight.id, to: "eight") }
    #expect(list[eight.id]?.text == "8")
  }

  @Test func addedNumbersTakeTheirPlace() throws {
    var list = NumberList(read: gantry)
    // A 2 the reading missed, between 7 and 82 on the photo's second row.
    let two = try list.add("2", at: NormalizedBox(x: 0.3, y: 0.29, width: 0.04, height: 0.05))
    #expect(two.isAdded)
    #expect(two.why == "Added by you")
    #expect(two.sourceText == nil)
    #expect(list.numbers.map(\.text) == ["8", "7", "2", "82", "90", "1"])
    // Typed with no spot, it goes last.
    try list.add("10")
    #expect(list.numbers.last?.text == "10")
    #expect(Set(list.numbers.map(\.id)).count == list.numbers.count)
  }

  @Test func removingTakesItOff() throws {
    var list = NumberList(read: gantry)
    let added = try list.add("6")
    list.remove(added.id)
    let first = try #require(list.numbers.first)
    list.remove(first.id)
    #expect(list.numbers.map(\.text) == ["7", "82", "90", "1"])
    // Ids are never reused, so a stale id can't touch a new number.
    let next = try list.add("3")
    #expect(next.id != added.id && next.id != first.id)
  }

  @Test func theSameNumberTwiceIsTwoNumbers() {
    let list = NumberList(read: [read("7", x: 0.1, y: 0.1), read("7", x: 0.5, y: 0.1)])
    #expect(list.values == ["7", "7"])
  }

  @Test func valuesAreAsTheCheckerWritesThem() throws {
    var list = NumberList()
    try list.add("1/2")
    try list.add("12,000")
    try list.add("007")
    #expect(list.numbers.map(\.text) == ["1/2", "12,000", "7"])
    #expect(list.values == ["0.5", "12000", "7"])
  }

  @Test func aTapPicksTheNumberUnderIt() {
    let list = NumberList(read: gantry)
    #expect(list.number(at: 0.63, 0.33)?.text == "90")
    #expect(list.number(at: 0.2, 0.9) == nil)
  }

  @Test func readingOrderKeepsVisionsOrderOnATie() {
    let box = NormalizedBox(x: 0.1, y: 0.1, width: 0.1, height: 0.1)
    #expect(NumberList.inReadingOrder(["a", "b", "c"]) { _ in box } == ["a", "b", "c"])
  }
}

@Suite struct NumberEntryTests {
  @Test func readsWhatASignShows() throws {
    #expect(try NumberEntry.parse("7").text == "7")
    #expect(try NumberEntry.parse(" 82nd ").value == 82)
    #expect(try NumberEntry.parse("7B").value == 7)
    #expect(try NumberEntry.parse("2.5").value == Decimal(string: "2.5"))
    #expect(try NumberEntry.parse("½").value == Decimal(string: "0.5"))
    #expect(try NumberEntry.parse("12,000").value == 12000)
  }

  @Test func saysWhatIsWrong() {
    #expect(throws: NumberEntry.Problem.empty) { try NumberEntry.parse("  ") }
    #expect(throws: NumberEntry.Problem.notANumber) { try NumberEntry.parse("MILE") }
    #expect(throws: NumberEntry.Problem.moreThanOne) { try NumberEntry.parse("7:30") }
    #expect(throws: NumberEntry.Problem.moreThanOne) { try NumberEntry.parse("1 1/2") }
    #expect(throws: NumberEntry.Problem.tooLong) { try NumberEntry.parse("12345678901234567") }
    #expect(!NumberEntry.Problem.moreThanOne.message.isEmpty)
  }
}

@Suite struct SpotReadingTests {
  @Test func theRegionStaysOnThePhoto() {
    let corner = SpotReading.region(around: 0.98, 0.02)
    #expect(corner.x >= 0 && corner.maxX <= 1 + 1e-9)
    #expect(corner.y == 0)
    let middle = SpotReading.region(around: 0.5, 0.5)
    #expect(abs(middle.x + middle.width / 2 - 0.5) < 1e-9)
  }

  @Test func offersTheNumberUnderOrNearestTheTap() {
    let numbers = [read("12", x: 0.1, y: 0.1), read("4", x: 0.4, y: 0.1), read("9", x: 0.45, y: 0.3)]
    #expect(SpotReading.nearest(numbers, to: 0.42, 0.12)?.text == "4")
    #expect(SpotReading.nearest(numbers, to: 0.47, 0.25)?.text == "9")
  }

  @Test func leavesOutNumbersAlreadyOnTheList() {
    let numbers = [read("12", x: 0.1, y: 0.1), read("4", x: 0.4, y: 0.1)]
    let taken = [NormalizedBox(x: 0.4, y: 0.1, width: 0.06, height: 0.05)]
    #expect(SpotReading.nearest(numbers, to: 0.42, 0.12, excluding: taken)?.text == "12")
    #expect(SpotReading.nearest([], to: 0.5, 0.5) == nil)
  }
}
