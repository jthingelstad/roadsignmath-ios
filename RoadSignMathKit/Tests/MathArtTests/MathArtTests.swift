import Equation
import Foundation
import Testing

@testable import MathArt

/// Every LaTeX the server's vectors expect (EquationTests' copy of
/// contracts/equation-vectors.json) typesets and draws, and so do the
/// shapes the vectors don't reach: nested fractions, a radical over a
/// fraction, a factorial on brackets.
@MainActor @Suite struct MathArtTests {
  nonisolated static let texes: [String] = {
    struct Vectors: Decodable {
      struct Check: Decodable { var tex: String? }
      var checks: [Check]
    }
    let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "EquationTests/Resources/equation-vectors.json")
    let vectors = try! JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    let more = ["((1 + 2) × 3)!", "(1 ÷ 2) ÷ (3 ÷ 4) = 2 ÷ 3", "√(8 ÷ 2) = 2", "2 ^ 3 ^ 2 = 512", "(2 ^ 3)! = 40320"]
    return vectors.checks.compactMap(\.tex) + more.map { EquationChecker.tex(of: $0)! }
  }()

  @Test func thereAreMany() { #expect(Self.texes.count > 30) }

  @Test(arguments: texes)
  func draws(_ tex: String) throws {
    #expect(MathArt.typesets(tex))
    let picture = try #require(MathArt.picture(tex: tex, fontSize: 20, color: 0xFFFFFF))
    #expect(picture.size.width > 0 && picture.size.height > 0)
  }

  @Test func shrinksToFit() {
    let tex = EquationChecker.tex(of: "(35 ÷ 7 × 10 + 12) − 62 + 6 + 3 + 2 = 11")!
    let natural = MathArt.picture(tex: tex, fontSize: 24, color: 0xFFFFFF)!.size.width
    #expect(MathArt.fittingSize(tex: tex, preferred: 24, width: natural * 2) == 24)
    let fit = MathArt.fittingSize(tex: tex, preferred: 24, width: natural / 2)
    #expect(fit <= 12 && fit >= 11)
    #expect(MathArt.picture(tex: tex, fontSize: fit, color: 0xFFFFFF)!.size.width <= natural / 2 + 1)
  }

  @Test func keepsWhatItDrew() {
    let a = MathArt.picture(tex: "7 = 7", fontSize: 20, color: 0xFFFFFF)
    let b = MathArt.picture(tex: "7 = 7", fontSize: 20, color: 0xFFFFFF)
    #expect(a != nil && a === b)
  }

  @Test func prefersTheServersLaTeX() {
    #expect(MathArt.tex(for: "3 × 33 = 99", sent: "sent") == "sent")
    #expect(MathArt.tex(for: "3 × 33 = 99", sent: nil) == "3 \\times 33 = 99")
    #expect(MathArt.tex(for: "3 × = 99", sent: nil) == nil)
  }
}
