import Foundation
import Testing

@testable import SignReadingEval

@Suite struct LatexNumbersTests {
  /// Equations as the micro.blog posts write them.
  @Test(arguments: [
    (#"{(90-82) \over 8 } \times 1 \times 2 = {6 \over {10 - 7}}"#, [90, 82, 8, 1, 2, 6, 10, 7]),
    (#" { \left( 25 - 1 \right) \over 8 } = 4 - { 3 \over 3 } "#, [25, 1, 8, 4, 3, 3]),
    (
      #" \underbrace{\left(  \frac {35} {7} \times 10 + 12 \right) - 62}_0 + 6 + 3 + 2 = 11 "#,
      [35, 7, 10, 12, 62, 6, 3, 2, 11]
    ),
    (#" \sqrt { 5 - 1 } = 2 "#, [5, 1, 2]),
    (#" \sqrt { 83 - \sqrt 4 } = 6 + 3 "#, [83, 4, 6, 3]),
    (#" ( 70 \div ( 90 - 80 ) ) + 13 = 65 - 45 "#, [70, 90, 80, 13, 65, 45]),
    (#"\frac{1}{2} + 1.5 = 2"#, [1, 2, 1.5, 2]),
    (#"x_{12} + 3 = 4"#, [3, 4]),
  ] as [(String, [Decimal])])
  func readsTheNumbers(latex: String, expected: [Decimal]) {
    #expect(LatexNumbers.numbers(in: latex) == expected)
  }

  @Test func findsTheEquation() {
    let text = "Simple math.\n\n$$ 14 + 10 = 24 $$\n\n<img src=\"uploads/2023/a.jpg\">"
    #expect(LatexNumbers.equation(in: text) == " 14 + 10 = 24 ")
    #expect(LatexNumbers.equation(in: "no math") == nil)
  }
}

@Suite struct MicroblogTests {
  @Test func findsImagesInOrder() {
    let text = #"<img src="uploads/2023/a.jpeg" width="600"> text <img alt="" src="uploads/2023/b.jpeg">"#
    #expect(MicroblogSigns.imageSources(in: text) == ["uploads/2023/a.jpeg", "uploads/2023/b.jpeg"])
  }

  @Test func namesPosts() {
    let slug = MicroblogSigns.slug(of: "http://example.micro.blog/2023/10/21/genesis.html")
    #expect(slug == "2023/10/21/genesis")
    #expect(MicroblogSigns.untitled("2023/10/22/153816") == "Post of 2023-10-22")
  }
}

@Suite struct ArchiveTests {
  let sign = """
    ---
    title: "Three Types"
    numbers: [1, 35, 36]
    photos:
      - file: "a.gif"
        recovered: "poster-crop"
        image: "a.jpg"
      - file: "b.gif"
        image: "b.jpg"
    wiki:
      title: "Three Types"
    ---

    Body text with image: "not-this.jpg"
    """

  @Test func readsTheFields() {
    let fields = ArchiveSigns.frontMatter(of: sign)
    #expect(ArchiveSigns.title(from: fields) == "Three Types")
    #expect(ArchiveSigns.numbers(from: fields) == [1, 35, 36])
    #expect(ArchiveSigns.images(from: fields) == ["a.jpg", "b.jpg"])
  }

  @Test func readsQuotedAndBlockNumbers() {
    #expect(ArchiveSigns.numbers(from: [#"numbers: ["12 144"]"#]) == [12, 144])
    #expect(ArchiveSigns.numbers(from: ["numbers:", "  - 4", "  - 2", "photos:"]) == [4, 2])
    #expect(ArchiveSigns.numbers(from: ["numbers: []"]) == [])
    #expect(ArchiveSigns.numbers(from: ["title: x"]) == [])
  }

  @Test func noFrontMatterNoFields() {
    #expect(ArchiveSigns.frontMatter(of: "Just text").isEmpty)
  }
}

@Suite struct ScoringTests {
  @Test func countsHitsAsAMultiset() {
    let score = SignScore(expected: [7, 7, 3], read: [7, 3, 3, 9])
    #expect(score.hits == 2)
    #expect(score.extras == 2)
    #expect(abs(score.recall - 2.0 / 3.0) < 1e-9)
    #expect(!score.isFullHit)
  }

  @Test func aFullHit() {
    let score = SignScore(expected: [3, 33, 99], read: [99, 33, 3, 1])
    #expect(score.isFullHit)
    #expect(score.extras == 1)
  }

  @Test func comparesByValue() {
    let half = Decimal(string: "0.50")!
    #expect(SignScore(expected: [Decimal(1) / 2], read: [half]).isFullHit)
  }

  @Test func photosOfOneSignAreUnited() {
    // Genesis: one photo read 3 and 99, the other 33 and 99.
    #expect(Multiset.union([[3, 99], [33, 99]]) == [3, 33, 99])
    #expect(Multiset.union([[7, 7], [7, 1]]) == [1, 7, 7])
  }

  @Test func summarises() {
    let scores = [SignScore(expected: [1, 2], read: [1, 2, 5]), SignScore(expected: [3], read: [])]
    let summary = ScoreSummary(scores: scores, seconds: [0.2, 0.4])
    #expect(summary.signs == 2)
    #expect(summary.fullHits == 1)
    #expect(summary.meanRecall == 0.5)
    #expect(summary.extras == 1)
    #expect(abs(summary.meanSecondsPerImage - 0.3) < 1e-9)
  }
}
