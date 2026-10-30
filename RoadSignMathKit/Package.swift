// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RoadSignMathKit",
  platforms: [.iOS("26.0"), .macOS("15.0")],
  products: [
    .library(name: "SignReading", targets: ["SignReading"]),
  ],
  targets: [
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
