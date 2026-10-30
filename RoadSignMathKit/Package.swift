// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RoadSignMathKit",
  platforms: [.iOS("26.0"), .macOS("15.0")],
  products: [
    .library(name: "SignReading", targets: ["SignReading"]),
    .library(name: "Equation", targets: ["Equation"]),
    .library(name: "MathArt", targets: ["MathArt"]),
    .library(name: "RoadSignMathAPI", targets: ["RoadSignMathAPI"]),
  ],
  dependencies: [
    // The one package from outside Apple: it typesets the math's LaTeX the
    // way TeX does (Jamie, 2026-10-30: "Use SwiftMath instead. I made those
    // rules."). Pinned to an exact release; add nothing else without Jamie.
    .package(url: "https://github.com/mgriebling/SwiftMath.git", exact: "1.7.3"),
  ],
  targets: [
    // The equation checker, a port of the server's src/domain/equation.ts.
    .target(name: "Equation"),
    // The vectors are the server's contracts/equation-vectors.json, copied
    // byte for byte; scripts/check-vectors.sh (in CI) keeps them the same.
    .testTarget(name: "EquationTests", dependencies: ["Equation"], resources: [.copy("Resources/equation-vectors.json")]),
    // Drawing the math: the LaTeX `Equation.tex` writes, typeset by SwiftMath.
    .target(name: "MathArt", dependencies: ["Equation", .product(name: "SwiftMath", package: "SwiftMath")]),
    .testTarget(name: "MathArtTests", dependencies: ["MathArt", "Equation"]),
    // The server's read routes (GET /api/v1/...) and their JSON.
    .target(name: "RoadSignMathAPI"),
    .testTarget(name: "RoadSignMathAPITests", dependencies: ["RoadSignMathAPI"], resources: [.copy("Resources")]),
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
