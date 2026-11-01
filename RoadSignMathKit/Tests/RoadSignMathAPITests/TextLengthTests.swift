import Testing

@testable import RoadSignMathAPI

@Suite struct TextLengthTests {
  @Test func countsAsTheServerDoes() {
    #expect("Ames Math".serverLength == 9)
    #expect("🥧".serverLength == 2)
    #expect("🇺🇸".serverLength == 4)
    #expect("👨‍👩‍👧".serverLength == 8)
    #expect("√(5 − 1) = 2".serverLength == 12)
    #expect("مرحبا".serverLength == 5)
  }

  @Test func clipsBetweenCharactersNeverThroughOne() {
    #expect("Ames Math".clipped(to: 4) == "Ames")
    #expect("Ames Math".clipped(to: 60) == "Ames Math")
    // Three units left: the pie (2) fits, the flag (4) doesn't, and isn't cut in half.
    #expect("a🥧🇺🇸".clipped(to: 3) == "a🥧")
    #expect("a🥧🇺🇸".clipped(to: 6) == "a🥧")
    #expect("a🥧🇺🇸".clipped(to: 7) == "a🥧🇺🇸")
    #expect("👨‍👩‍👧".clipped(to: 7) == "")
    #expect("".clipped(to: 5) == "")
  }

  @Test func aCaptionOfEmojiFitsTheServersCap() {
    let caption = String(repeating: "Grandma’s 🥧🚙 ", count: 60)
    let clipped = caption.clipped(to: APIClient.captionMax)
    #expect(clipped.serverLength <= APIClient.captionMax)
    #expect(clipped.serverLength > APIClient.captionMax - 2)
    #expect(clipped.count < APIClient.captionMax)
  }
}
