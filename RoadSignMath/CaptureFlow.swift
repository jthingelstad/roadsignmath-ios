import Foundation
import Observation
import SignCapture
import SignReading
import UIKit

/// Capture, from the shutter to the checked numbers: the photo taken or
/// picked, its reading, and the list the player checks. Solve (step 2.4)
/// takes `numbers.values` as the numbers its math may use; posting (2.5)
/// takes `shot.file` (the photo with its own day and place) and
/// `numbers.kept`.
///
/// The last shot stays while the app is open, so closing Capture and coming
/// back finds it behind the camera's thumbnail.
@MainActor @Observable
final class CaptureFlow {
  enum Source: Hashable { case camera, library, sample }

  /// The screens after the camera.
  enum Stop: Hashable { case check, solve, post }

  enum Reading: Equatable {
    case idle, reading, read
    case failed(String)
  }

  struct Shot: Identifiable {
    let id = UUID()
    let file: PhotoFile
    /// Upright, at most 2400 pixels on its long side, to show.
    let picture: UIImage
    /// Upright, at most 4032 pixels, to read (and read again at a tap).
    let readable: CGImage
    let source: Source
    /// When it was taken: the shutter for the camera, the photo's own clock
    /// for one from the library (nil when it doesn't say).
    let takenAt: Date?

    /// The day found, `2025-09-01`: the photo's own day, else the day taken
    /// here.
    var foundOn: String? {
      if source != .camera, let day = file.facts.takenOn { return day }
      guard let takenAt else { return nil }
      // Gregorian whatever the phone's calendar, in the phone's time zone.
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = .current
      let parts = calendar.dateComponents([.year, .month, .day], from: takenAt)
      guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
      return String(format: "%04d-%02d-%02d", year, month, day)
    }
  }

  /// Capture is showing.
  var open = false
  var path: [Stop] = []
  /// The camera shows the shot with its numbers boxed, not the live view.
  var reviewing = false
  private(set) var shot: Shot?
  private(set) var reading: Reading = .idle
  var numbers = NumberList()
  /// A photo is being opened, after the shutter or the picker.
  private(set) var opening = false
  /// A photo that couldn't be opened, said on the camera.
  var problem: String?

  /// Bumped by every new photo, so a slow reading of an earlier one is
  /// dropped.
  private var generation = 0
  private var work: Task<Void, Never>?

  /// Opens Capture on the live camera.
  func begin() {
    path = []
    reviewing = false
    problem = nil
    open = true
  }

  func close() {
    open = false
  }

  /// A photo from the camera, the library or the sample: opened, shown
  /// with its numbers boxed as they're read.
  func take(_ data: Data, from source: Source, at time: Date? = nil) {
    generation += 1
    let mine = generation
    work?.cancel()
    opening = true
    problem = nil
    work = Task {
      let opened = await Task.detached(priority: .userInitiated) { () -> (PhotoFile, CGImage, CGImage)? in
        guard let file = PhotoFile(data: data), let show = file.image(maxPixels: 2400),
          let read = file.image(maxPixels: 4032)
        else { return nil }
        return (file, show, read)
      }.value
      guard mine == generation else { return }
      opening = false
      guard let (file, show, read) = opened else {
        problem = "That photo couldn’t be opened. Try another one."
        return
      }
      shot = Shot(
        file: file, picture: UIImage(cgImage: show), readable: read, source: source,
        takenAt: source == .camera ? (time ?? .now) : file.facts.takenAt)
      numbers = NumberList()
      path = []
      reviewing = true
      reading = .reading
      do {
        let found = try await Task.detached(priority: .userInitiated) {
          try await SignReader.photo.numbers(in: read)
        }.value
        guard mine == generation else { return }
        numbers = NumberList(read: found)
        reading = .read
      } catch {
        guard mine == generation, !Task.isCancelled else { return }
        reading = .failed("We couldn’t read this photo. You can still add its numbers yourself.")
      }
    }
  }

  /// Reads the part of the photo around a tap again, close up, for a
  /// number the first reading missed. Nil when nothing new is there.
  func readSpot(_ x: Double, _ y: Double) async -> ReadNumber? {
    guard let image = shot?.readable else { return nil }
    let taken = numbers.numbers.compactMap(\.box)
    return try? await Task.detached(priority: .userInitiated) {
      try await SpotReading.number(near: x, y, in: image, excluding: taken)
    }.value
  }

  /// The part of the shot around `box`, close up, for the sheet that fixes
  /// or adds a number.
  func closeUp(_ box: NormalizedBox) -> UIImage? {
    guard let image = shot?.readable else { return nil }
    let around = box.padded(dx: max(box.width * 0.6, 0.04), dy: max(box.height * 0.8, 0.03))
    let width = Double(image.width)
    let height = Double(image.height)
    let rect = CGRect(x: around.x * width, y: around.y * height, width: around.width * width, height: around.height * height)
      .integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
    guard !rect.isEmpty, let cropped = image.cropping(to: rect) else { return nil }
    return UIImage(cgImage: cropped)
  }

  /// Back to the live camera, keeping the shot behind its thumbnail.
  func retake() {
    reviewing = false
  }

  /// "Got it" while reading: how the shot's reading is going, in a few words.
  var headline: String {
    switch reading {
    case .idle, .reading: "Reading the numbers…"
    case .failed: "Couldn’t read this one"
    case .read:
      switch numbers.numbers.count {
      case 0: "No numbers read"
      case 1: "Got it. 1 number."
      default: "Got it. \(numbers.numbers.count) numbers."
      }
    }
  }

  /// Debug builds' launch arguments for screenshots, since a simulator
  /// can't tap: `-RSMCapture camera` opens the camera, `-RSMCapture sample`
  /// shoots the made-up sample sign, `-RSMCapture <file>` takes a photo
  /// file from this Mac as if picked from the library. Then `-RSMCheck YES`
  /// goes on to Check the numbers, `-RSMFix <n>` opens the nth number's
  /// sheet, `-RSMAdd YES` the sheet for a missed number, `-RSMSpot x,y`
  /// taps the photo there (0...1 each way), `-RSMSolve YES` or
  /// `-RSMPost YES` the step after, and `-RSMLandscape YES` turns sideways.
  func script() {
    #if DEBUG
      guard let what = Script.value("RSMCapture") else { return }
      begin()
      if what == "sample", let sample = SampleSign.photo() {
        take(sample.data, from: .sample)
      } else if what != "camera", let data = try? Data(contentsOf: URL(fileURLWithPath: what)) {
        take(data, from: .library)
      }
      Task {
        while reading == .reading || opening { try? await Task.sleep(for: .milliseconds(200)) }
        if Script.flag("RSMCheck") || Script.value("RSMFix") != nil || Script.flag("RSMAdd") || Script.value("RSMSpot") != nil {
          path = [.check]
        }
        if Script.flag("RSMSolve") { path = [.check, .solve] }
        if Script.flag("RSMPost") { path = [.check, .post] }
      }
    #endif
  }
}
