// Makes the app's icon sets and icon pictures from the brand package.
//
//   swift scripts/app-icons.swift <package> <asset catalog>
//   swift scripts/app-icons.swift design/brand/v1 RoadSignMath/Assets.xcassets
//
// For each of the five icons it writes an app icon set (Highway is
// `AppIcon`, the others `AppIcon-<Name>`) holding three looks:
//
// - Any: the package's square 1024 PNG, copied byte for byte.
// - Dark: the package's foreground layer on a transparent ground, so the
//   system's dark background shows through (Apple: "Provide your dark app
//   icon with a transparent background"). A symbol that is deep green on
//   yellow turns sign yellow, the icon's own ground colour, so it shows on
//   the dark; white and the route shield's green stay as they are.
// - Tinted: grayscale (Apple: "Provide your tinted app icon as a grayscale
//   image"), the foreground in white on black, with Factorial's shield at
//   its own green's lightness so the white 3! still stands out on it.
//
// Only colour changes: every look is the package's own layer, pixel for
// pixel in shape. It also writes `Icon<Name>` image sets (the package's
// square vector icon) for the picker in Settings, and the `Logo` image set
// (Highway, whichever icon the Home Screen shows). It never reads the
// rounded previews.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Icon {
  let id: String
  let name: String
  /// What the foreground's coloured (non-white) part becomes in the dark look.
  let dark: UInt32?
  /// What it becomes in the tinted look, as a gray level.
  let tinted: UInt8?
  var set: String { id == "highway" ? "AppIcon" : "AppIcon-" + name.replacingOccurrences(of: " ", with: "") }
  var picture: String { "Icon" + name.replacingOccurrences(of: " ", with: "") }
}

let signYellow: UInt32 = 0xF2B300
let highwayGreen: UInt32 = 0x006348
/// #006348's relative luminance (0.094) as an sRGB gray: 0x56.
let shieldGray: UInt8 = 0x56

let icons = [
  Icon(id: "highway", name: "Highway", dark: nil, tinted: nil),
  Icon(id: "sunshine", name: "Sunshine", dark: signYellow, tinted: 0xFF),
  Icon(id: "division", name: "Division", dark: signYellow, tinted: 0xFF),
  Icon(id: "factorial", name: "Factorial", dark: highwayGreen, tinted: shieldGray),
  Icon(id: "four-ways", name: "Four Ways", dark: nil, tinted: nil),
]

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
  FileHandle.standardError.write("usage: swift scripts/app-icons.swift <package> <asset catalog>\n".data(using: .utf8)!)
  exit(2)
}
let package = URL(fileURLWithPath: arguments[1], isDirectory: true)
let catalog = URL(fileURLWithPath: arguments[2], isDirectory: true)
let files = FileManager.default
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func fail(_ message: String) -> Never {
  FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
  exit(1)
}

func fresh(_ folder: URL) throws {
  if files.fileExists(atPath: folder.path) { try files.removeItem(at: folder) }
  try files.createDirectory(at: folder, withIntermediateDirectories: true)
}

func write(_ json: String, to url: URL) throws {
  try json.write(to: url, atomically: true, encoding: .utf8)
}

/// A PNG's pixels as premultiplied sRGB RGBA, 8 bits each.
func pixels(of url: URL) -> (width: Int, height: Int, bytes: [UInt8]) {
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else { fail("can't read \(url.path)") }
  let width = image.width
  let height = image.height
  var bytes = [UInt8](repeating: 0, count: width * height * 4)
  bytes.withUnsafeMutableBytes { buffer in
    let context = CGContext(
      data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
  }
  return (width, height, bytes)
}

func png(_ bytes: [UInt8], width: Int, height: Int, opaque: Bool, to url: URL) {
  var bytes = bytes
  let info = opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast
  let image = bytes.withUnsafeMutableBytes { buffer -> CGImage in
    let context = CGContext(
      data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: srgb, bitmapInfo: info.rawValue)!
    return context.makeImage()!
  }
  guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { fail("can't write \(url.path)") }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fail("can't write \(url.path)") }
}

func channels(_ rgb: UInt32) -> (Double, Double, Double) {
  (Double((rgb >> 16) & 0xFF), Double((rgb >> 8) & 0xFF), Double(rgb & 0xFF))
}

/// Every foreground is white plus at most one green, and both greens
/// (#006348, #004A36) have no red. So in a premultiplied pixel, red is the
/// white part's coverage and alpha minus red the green part's: the two can
/// be recoloured apart, edges and all. `green` is the layer's own green, to
/// check that the split gives the pixel back.
func split(_ bytes: [UInt8], green: UInt32?) -> (white: [Double], colour: [Double]) {
  let count = bytes.count / 4
  var white = [Double](repeating: 0, count: count)
  var colour = [Double](repeating: 0, count: count)
  var worst = 0.0
  let (_, gG, gB) = channels(green ?? 0)
  for i in 0..<count {
    let r = Double(bytes[i * 4]), g = Double(bytes[i * 4 + 1]), b = Double(bytes[i * 4 + 2]), a = Double(bytes[i * 4 + 3])
    let w = min(r, a)
    let c = a - w
    white[i] = w
    colour[i] = c
    // Rebuild green and blue from the split and compare.
    let gBack = w + c * gG / 255
    let bBack = w + c * gB / 255
    worst = max(worst, abs(gBack - g), abs(bBack - b))
  }
  if worst > 2.5 { fail("the foreground isn't white plus one green (off by \(worst))") }
  return (white, colour)
}

/// The green a foreground layer uses besides white, if any.
func greenOf(_ svg: String) -> UInt32? {
  for hex in ["#004A36", "#006348"] where svg.uppercased().contains("FILL=\"\(hex)\"") {
    return UInt32(hex.dropFirst(), radix: 16)
  }
  return nil
}

func iconSet(_ icon: Icon) throws {
  let folder = catalog.appendingPathComponent(icon.set + ".appiconset")
  try fresh(folder)
  let flat = package.appendingPathComponent("icons/png-1024/\(icon.id).png")
  try files.copyItem(at: flat, to: folder.appendingPathComponent("icon-1024.png"))

  let layer = package.appendingPathComponent("icons/layers/\(icon.id)/foreground.png")
  let svg = try String(contentsOf: package.appendingPathComponent("icons/layers/\(icon.id)/foreground.svg"), encoding: .utf8)
  let green = greenOf(svg)
  let (width, height, bytes) = pixels(of: layer)
  guard width == 1024, height == 1024 else { fail("\(icon.id): the layer isn't 1024 square") }
  let (white, colour) = split(bytes, green: green)
  if green != nil, icon.dark == nil || icon.tinted == nil { fail("\(icon.id): say what its green becomes") }

  // Dark: transparent ground, the white as it is, the green as `dark`.
  let (dR, dG, dB) = channels(icon.dark ?? 0)
  var dark = [UInt8](repeating: 0, count: bytes.count)
  // Tinted: opaque black ground, the white as white, the green as `tinted` gray.
  let t = Double(icon.tinted ?? 0)
  var tinted = [UInt8](repeating: 0, count: bytes.count)
  for i in 0..<white.count {
    let w = white[i], c = colour[i]
    dark[i * 4] = UInt8((w + c * dR / 255).rounded())
    dark[i * 4 + 1] = UInt8((w + c * dG / 255).rounded())
    dark[i * 4 + 2] = UInt8((w + c * dB / 255).rounded())
    dark[i * 4 + 3] = UInt8((w + c).rounded())
    let gray = UInt8(min(255, (w + c * t / 255).rounded()))
    tinted[i * 4] = gray
    tinted[i * 4 + 1] = gray
    tinted[i * 4 + 2] = gray
    tinted[i * 4 + 3] = 255
  }
  png(dark, width: width, height: height, opaque: false, to: folder.appendingPathComponent("icon-1024-dark.png"))
  png(tinted, width: width, height: height, opaque: true, to: folder.appendingPathComponent("icon-1024-tinted.png"))

  try write(
    """
    {
      "images" : [
        { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
        {
          "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
          "filename" : "icon-1024-dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024"
        },
        {
          "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
          "filename" : "icon-1024-tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024"
        }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }

    """, to: folder.appendingPathComponent("Contents.json"))
}

/// The package's square vector icon as an image set the app can draw at any size.
func vectorSet(_ name: String, from icon: Icon) throws {
  let folder = catalog.appendingPathComponent(name + ".imageset")
  try fresh(folder)
  try files.copyItem(
    at: package.appendingPathComponent("icons/svg/\(icon.id).svg"), to: folder.appendingPathComponent("\(icon.id).svg"))
  try write(
    """
    {
      "images" : [ { "filename" : "\(icon.id).svg", "idiom" : "universal" } ],
      "info" : { "author" : "xcode", "version" : 1 },
      "properties" : { "preserves-vector-representation" : true }
    }

    """, to: folder.appendingPathComponent("Contents.json"))
}

do {
  for icon in icons {
    try iconSet(icon)
    try vectorSet(icon.picture, from: icon)
  }
  try vectorSet("Logo", from: icons[0])
  print("Wrote \(icons.count) icon sets, their pictures and the logo to \(catalog.path)")
} catch {
  fail("\(error)")
}
