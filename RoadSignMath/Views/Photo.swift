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
  /// For a held or hidden sign's photo (`/api/v1/me/photos/…`), which the
  /// server gives only to its poster, with their token.
  weak var account: Account?

  init() { kept.countLimit = 120 }

  #if DEBUG
    private var failedOnce: Set<String> = []
  #endif

  func kept(_ url: URL, pixels: Int) -> UIImage? { kept.object(forKey: Self.key(url, pixels) as NSString) }

  func image(_ url: URL, pixels: Int) async -> UIImage? {
    let key = Self.key(url, pixels)
    if let image = kept.object(forKey: key as NSString) { return image }
    if let task = reading[key] { return await task.value }
    var request = URLRequest(url: url)
    if url.path.contains("/api/v1/me/photos/") {
      guard let token = account?.readToken else { return nil }
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let task = Task.detached(priority: .userInitiated) { [request] () -> UIImage? in
      guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200
      else { return nil }
      return Photos.decode(data, pixels: pixels)
    }
    reading[key] = task
    var image = await task.value
    #if DEBUG
      // `-RSMPhotoFails YES`: every photo's first read fails, for the retry.
      if Script.flag("RSMPhotoFails"), !failedOnce.contains(key) {
        failedOnce.insert(key)
        image = nil
      }
    #endif
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

  /// The photo read for a URL. Kept with its URL, so a view reused for
  /// another photo never shows the last one's.
  @State private var read: (url: URL, image: UIImage)?
  /// The photo at this URL didn't load: it says so, and a tap tries again.
  @State private var failed: URL?
  @State private var tries = 0

  var body: some View {
    Color.photoGround
      .overlay {
        if let shown = Photos.shared.kept(url, pixels: pixels) ?? (read?.url == url ? read?.image : nil) {
          Image(uiImage: shown)
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .transition(.opacity)
        } else if failed == url {
          Button {
            failed = nil
            tries += 1
          } label: {
            VStack(spacing: 4) {
              Image(systemName: "arrow.clockwise").font(.system(size: 20, weight: .semibold))
              Text("Tap to load the photo").face(.meta)
            }
            .foregroundStyle(Color.ink3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      .clipped()
      .task(id: "\(tries) \(url.absoluteString)") {
        guard Photos.shared.kept(url, pixels: pixels) == nil else { return }
        guard let image = await Photos.shared.image(url, pixels: pixels) else {
          if !Task.isCancelled { failed = url }
          return
        }
        failed = nil
        withAnimation(.easeOut(duration: 0.25)) { read = (url, image) }
      }
      .accessibilityElement()
      .accessibilityLabel(failed == url ? alt + ". It didn’t load." : alt)
      .accessibilityAddTraits(.isImage)
      .accessibilityAction(named: "Load the photo again") {
        failed = nil
        tries += 1
      }
  }
}
