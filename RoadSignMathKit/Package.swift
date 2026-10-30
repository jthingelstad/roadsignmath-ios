// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RoadSignMathKit",
  platforms: [.iOS("26.0"), .macOS("15.0")],
  products: [
    .library(name: "SignReading", targets: ["SignReading"]),
    .library(name: "Equation", targets: ["Equation"]),
  ],
  targets: [
    // The equation checker, a port of the server's src/domain/equation.ts.
    .target(name: "Equation"),
    // The vectors are the server's contracts/equation-vectors.json, copied
    // byte for byte; scripts/check-vectors.sh (in CI) keeps them the same.
    .testTarget(name: "EquationTests", dependencies: ["Equation"], resources: [.copy("Resources/equation-vectors.json")]),
    // Reading a sign's numbers: Vision text recognition and the number rules.
    .target(name: "SignReading"),
    // The spike's ground truth and scoring, kept apart from the command so
    // they can be tested.
    .target(name: "SignReadingEval", dependencies: ["SignReading"]),
    // `swift run sign-reading-eval --archive <dir> --microblog <dir> --out <dir>` (macOS).
    .executableTarget(name: "sign-reading-eval", dependencies: ["SignReading", "SignReadingEval"]),
    .testTarget(name: "SignReadingTests", dependencies: ["SignReading"]),
    .testTarget(name: "SignReadingEvalTests", dependencies: ["SignReadingEval"]),
  ]
)
