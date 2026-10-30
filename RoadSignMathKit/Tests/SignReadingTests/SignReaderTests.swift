import Foundation
import Testing

@testable import SignReading

@Suite struct NormalizedBoxTests {
  @Test func mapsFromARegionToTheWholeImage() {
    let region = NormalizedBox(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
    let box = NormalizedBox(x: 0.5, y: 0, width: 0.5, height: 0.5).mapped(into: region)
    #expect(box == NormalizedBox(x: 0.75, y: 0.5, width: 0.25, height: 0.25))
  }

  @Test func paddingStaysOnTheImage() {
    let box = NormalizedBox(x: 0.05, y: 0.5, width: 0.9, height: 0.2).padded(dx: 0.1, dy: 0.1)
    #expect(box.x == 0)
    #expect(abs(box.maxX - 1) < 1e-9)
    #expect(abs(box.y - 0.4) < 1e-9)
    #expect(abs(box.height - 0.4) < 1e-9)
  }

  @Test func overlapIsOfTheSmallerBox() {
    let big = NormalizedBox(x: 0, y: 0, width: 0.5, height: 0.5)
    let inside = NormalizedBox(x: 0.1, y: 0.1, width: 0.1, height: 0.1)
    let apart = NormalizedBox(x: 0.6, y: 0.6, width: 0.1, height: 0.1)
    #expect(big.overlap(with: inside) == 1)
    #expect(inside.overlap(with: big) == 1)
    #expect(big.overlap(with: apart) == 0)
  }
}

@Suite struct SignReaderMergeTests {
  func line(_ text: String, x: Double) -> RecognizedLine {
    RecognizedLine(text: text, box: NormalizedBox(x: x, y: 0.4, width: 0.1, height: 0.1))
  }

  @Test func laterPassesAddOnlyNewPlaces() {
    let whole = [line("Bolivar", x: 0.1), line("83", x: 0.3)]
    // The text region read 83 again, and the 4 and 3 the whole photo missed.
    let region = [line("83", x: 0.3), line("4", x: 0.8), line("3", x: 0.9)]
    let numbers = SignReader().numbers(fromPasses: [whole, region])
    #expect(numbers.map(\.value) == [83, 4, 3])
  }

  @Test func theFirstPassWinsAPlace() {
    // Iconium: the whole photo read "12", a crop read only "2" there.
    let numbers = SignReader().numbers(fromPasses: [[line("12", x: 0.5)], [line("2", x: 0.5)]])
    #expect(numbers.map(\.value) == [12])
  }

  @Test func theSameNumberInTwoPlacesIsTwoNumbers() {
    let numbers = SignReader().numbers(fromPasses: [[line("7", x: 0.1)], [line("7", x: 0.6)]])
    #expect(numbers.map(\.value) == [7, 7])
  }

  @Test func onePassIsTheExtractorAlone() {
    let lines = [line("EXIT 7B", x: 0.1), line("1 MILE", x: 0.5)]
    #expect(SignReader().numbers(fromPasses: [lines]) == NumberExtractor().numbers(in: lines))
  }

  @Test func theTextRegionHoldsEveryLinePadded() throws {
    let region = try #require(SignReader.textRegion(of: [line("A", x: 0.2), line("B", x: 0.6)]))
    #expect(abs(region.x - 0.12) < 1e-9)
    #expect(abs(region.maxX - 0.78) < 1e-9)
    #expect(SignReader.textRegion(of: []) == nil)
  }

  @Test func theQuartersCoverThePhoto() {
    let quarters = SignReader.quarters
    #expect(quarters.count == 4)
    #expect(quarters.map(\.x).min() == 0)
    #expect(abs((quarters.map(\.maxX).max() ?? 0) - 1) < 1e-9)
    #expect(abs((quarters.map(\.maxY).max() ?? 0) - 1) < 1e-9)
  }
}
