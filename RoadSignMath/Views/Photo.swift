import ImageIO
import SwiftUI
import UIKit

/// Sign photos, read from the server and decoded off the main thread at the
/// size they're shown, so the feed scrolls without a hitch. Kept in memory
/// (and in URLCache on disk) once read.
@MainActor
final class Photos {
  static let shared = Photos()

  private let kept = NSCache<NSString, UIImage>()
  private var reading: [String: Task<UIImage?, Never>] = [:]

  init() { kept.countLimit = 120 }

  func kept(_ url: URL, pixels: Int) -> UIImage? { kept.object(forKey: Self.key(url, pixels) as NSString) }

  func image(_ url: URL, pixels: Int) async -> UIImage? {
    let key = Self.key(url, pixels)
    if let image = kept.object(forKey: key as NSString) { return image }
    if let task = reading[key] { return await task.value }
    let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
      guard let (data, response) = try? await URLSession.shared.data(from: url),
            (response as? HTTPURLResponse)?.statusCode == 200
      else { return nil }
      return Photos.decode(data, pixels: pixels)
    }
    reading[key] = task
    let image = await task.value
    reading[key] = nil
    if let image { kept.setObject(image, forKey: key as NSString) }
    return image
  }

  private static func key(_ url: URL, _ pixels: Int) -> String { "\(pixels)|\(url.absoluteString)" }

  /// The photo no larger than `pixels` on its long side, decoded now.
  nonisolated static func decode(_ data: Data, pixels: Int) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: pixels,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return UIImage(cgImage: image)
  }
}

/// A sign's photo filling its frame, fading in once read.
struct PhotoView: View {
  let url: URL
  let alt: String
  /// The long side to decode at, in pixels.
  var pixels = 1200
  var contentMode: ContentMode = .fill

  @State private var image: UIImage?

  var body: some View {
    Color.photoGround
      .overlay {
        if let shown = image ?? Photos.shared.kept(url, pixels: pixels) {
          Image(uiImage: shown)
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .transition(.opacity)
        }
      }
      .clipped()
      .task(id: url) {
        guard Photos.shared.kept(url, pixels: pixels) == nil else { return }
        let read = await Photos.shared.image(url, pixels: pixels)
        withAnimation(.easeOut(duration: 0.25)) { image = read }
      }
      .accessibilityElement()
      .accessibilityLabel(alt)
      .accessibilityAddTraits(.isImage)
  }
}
