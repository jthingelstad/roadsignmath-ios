import Foundation
import Testing

@testable import Equation

/// `Resources/equation-vectors.json` is the server's
/// `contracts/equation-vectors.json`, copied byte for byte. The server runs
/// every case too, so the app and the server agree on what is true.
struct Vectors: Decodable {
  struct Check: Decodable {
    var text: String
    var ok: Bool
    var error: String?
    var canonical: String?
    var value: String?
    var numbers: [String]?
    var tex: String?
    var note: String
  }

  struct NumbersOnSign: Decodable {
    var used: [String]
    var sign: [String]
    var missing: [String]
    var note: String
  }

  var checks: [Check]
  var numbers_on_sign: [NumbersOnSign]

  static let shared: Vectors = {
    let url = Bundle.module.url(forResource: "equation-vectors", withExtension: "json")!
    return try! JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
  }()
}

extension Vectors.Check: CustomTestStringConvertible {
  var testDescription: String { "\(note): \(text)" }
}

extension Vectors.NumbersOnSign: CustomTestStringConvertible {
  var testDescription: String { note }
}

@Suite struct VectorTests {
  @Test func thereAreVectors() {
    #expect(Vectors.shared.checks.count >= 40)
    #expect(Vectors.shared.checks.contains { $0.ok })
    #expect(Vectors.shared.checks.contains { !$0.ok })
  }

  @Test(arguments: Vectors.shared.checks)
  func check(_ vector: Vectors.Check) throws {
    let result = EquationChecker.check(vector.text)
    if vector.ok {
      guard case .solved(let solved) = result else {
        Issue.record("expected true, got \(result)")
        return
      }
      #expect(solved.canonical == vector.canonical)
      #expect(solved.value == vector.value)
      #expect(solved.numbers == vector.numbers)
      let tex = try #require(vector.tex)
      #expect(solved.sides.map(EquationChecker.tex).joined(separator: " = ") == tex)
      #expect(EquationChecker.tex(of: vector.text) == tex)
      // The canonical text parses to the same tree, so drawing from either
      // the player's text or the server's canonical text looks the same.
      #expect(EquationChecker.parse(solved.canonical) == solved.sides)
    } else {
      guard case .failed(let failure) = result else {
        Issue.record("expected \(vector.error ?? "?"), got \(result)")
        return
      }
      #expect(failure.error.rawValue == vector.error)
      #expect(!failure.message.isEmpty)
    }
  }

  @Test(arguments: Vectors.shared.numbers_on_sign)
  func numbersOnSign(_ vector: Vectors.NumbersOnSign) {
    #expect(EquationChecker.numbersNotOnSign(used: vector.used, onSign: vector.sign) == vector.missing)
  }

  /// Every error code the server can answer is one the vectors exercise.
  @Test func everyErrorHasAVector() {
    let seen = Set(Vectors.shared.checks.compactMap(\.error))
    #expect(seen == Set(EquationError.allCases.map(\.rawValue)))
  }

  /// When the server's repo is beside this one (set ROADSIGNMATH_SERVER to
  /// its folder), the copy must be byte for byte the same. CI checks the
  /// same thing against GitHub with scripts/check-vectors.sh.
  @Test func copyMatchesTheServer() throws {
    guard let server = ProcessInfo.processInfo.environment["ROADSIGNMATH_SERVER"] else { return }
    let theirs = try Data(contentsOf: URL(filePath: server).appending(path: "contracts/equation-vectors.json"))
    let ours = try Data(contentsOf: Bundle.module.url(forResource: "equation-vectors", withExtension: "json")!)
    #expect(ours == theirs, "RoadSignMathKit's equation-vectors.json differs from the server's")
  }
}
