import Foundation
import Observation
import Posting
import RoadSignMathAPI
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
/// back finds it behind the camera's thumbnail. While the app is off the
/// screen, where the system may end it, a shot that isn't posted is kept in
/// Drafts (`keepSafe`), and taken back out when the player returns.
@MainActor @Observable
final class CaptureFlow {
  typealias Source = Draft.Source

  /// The screens after the camera. `posted` is the moment after Post it.
  enum Stop: Hashable { case check, solve, post, posted(UUID) }

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

  /// What's written on Post it, kept here rather than on the screen so it
  /// survives Capture stepping aside for a link, goes into a draft with
  /// "Save for later", and comes back with "Fix the post".
  struct PostForm: Equatable {
    var title = ""
    var caption = ""
    var spotters: [String] = []
    /// The day found, once the player or a draft set it.
    var foundOn: String?
    /// The town picked (or the place a refused post went with).
    var place: PostPlace?

    init() {}

    init(_ kept: DraftPost?) {
      guard let kept else { return }
      title = kept.title
      caption = kept.caption
      spotters = kept.spotters
      foundOn = kept.foundOn
      place = kept.place.map(PostPlace.init)
    }

    var isEmpty: Bool { self == PostForm() }
  }

  /// Capture is showing.
  var open = false
  var form = PostForm()
  /// The server's words about the refused post being fixed, shown on Post it.
  private(set) var refusal: String?
  /// The refused post in the outbox being fixed: posting again replaces it.
  private(set) var fixing: UUID?
  /// Where posts go. Set by `RootView`.
  @ObservationIgnored weak var outbox: Outbox?
  /// Capture stepped aside for a link: opening it again finds the shot on
  /// the step it was at.
  @ObservationIgnored private var aside = false
  var path: [Stop] = [] {
    // A way belongs to the one trip to posting it was set for: back out of
    // posting (to Solve, or to Check and "Post unsolved") and it's gone.
    didSet { if !path.contains(.post) { way = nil } }
  }
  /// The camera shows the shot with its numbers boxed, not the live view.
  var reviewing = false
  private(set) var shot: Shot?
  private(set) var reading: Reading = .idle
  var numbers = NumberList()
  /// The math being written on Solve. It stays while the player goes back
  /// to fix a number, and goes with the photo.
  var draft: WayDraft?
  /// The way to post: a working equation's canonical text, or nil to post
  /// the sign unsolved.
  var way: String?
  /// A photo is being opened, after the shutter or the picker.
  private(set) var opening = false
  /// A photo that couldn't be opened, said on the camera.
  var problem: String?
  /// Signs saved for later, on this phone.
  let drafts = DraftShelf()
  /// The draft this shot was opened from: saving again updates it, and
  /// posting it takes it off the shelf.
  private(set) var draftID: UUID?
  /// The town that draft's photo was taken in, kept as it's saved again.
  private var draftPlace: String?
  /// That town, for Post it when it can't be looked up again (no signal).
  var draftTown: String? { draftPlace }
  /// What `keepSafe` put in Drafts while the app is off the screen.
  private var safekept: Safekept?

  /// Bumped by every new photo, so a slow reading of an earlier one is
  /// dropped.
  private var generation = 0
  private var work: Task<Void, Never>?

  /// Opens Capture on the live camera, or where it was after stepping
  /// aside for a link.
  func begin() {
    if aside, shot != nil {
      aside = false
      open = true
      return
    }
    aside = false
    path = []
    reviewing = false
    problem = nil
    open = true
  }

  func close() {
    aside = false
    open = false
  }

  /// A link to a sign or a player is opening: Capture closes so its page
  /// shows, keeping the shot, the step it's at and what's written, so the
  /// camera button opens it just as it was.
  func stepAside() {
    aside = shot != nil
    open = false
  }

  /// A photo from the camera, the library or the sample: opened, shown
  /// with its numbers boxed as they're read.
  func take(_ data: Data, from source: Source, at time: Date? = nil) {
    fixing = nil
    refusal = nil
    open(data, from: source, at: time, resuming: nil)
  }

  /// A draft picked up where it was left: its photo, its numbers as
  /// checked (read again if it was saved before they were read) and its
  /// math, on the screen it had got to.
  func resume(_ saved: Draft, fixing item: OutboxItem? = nil) {
    guard let data = drafts.photo(of: saved.id) else {
      problem = "That draft’s photo couldn’t be opened."
      if item == nil { drafts.remove(saved.id) }
      return
    }
    aside = false
    begin()
    fixing = item?.id
    refusal = item?.refusal
    open(data, from: saved.source, at: saved.takenAt, resuming: saved)
  }

  /// "Fix the post" on Home's note about a refused post: Post it again
  /// with its photo, numbers, math, title, caption and spotters, and the
  /// server's words. A shot open in Capture meanwhile goes to Drafts
  /// first, so it isn't lost. False when the post's draft isn't kept.
  @discardableResult
  func fix(_ item: OutboxItem) -> Bool {
    guard let saved = drafts.draft(for: item) else { return false }
    if fixing == item.id, shot != nil {
      begin()
      return true
    }
    if shot != nil, !path.contains(where: { if case .posted = $0 { true } else { false } }) {
      takeBack()
      if let (open, photo) = asDraft(outbox: fixing) { _ = drafts.save(open, photo: photo) }
    }
    resume(saved, fixing: item)
    return true
  }

  private func open(_ data: Data, from source: Source, at time: Date?, resuming saved: Draft?) {
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
      draftID = saved?.id
      draftPlace = saved?.place
      numbers = saved?.numbers ?? NumberList()
      draft = saved?.way
      way = nil
      form = PostForm(saved?.post)
      reviewing = true
      if saved?.numbers != nil {
        reading = .read
        var stops: [Stop] = draft == nil ? [.check] : [.check, .solve]
        // Saved on Post it, or refused by the server: back to Post it,
        // with the way it was going to post (set after the path, which
        // lets a way go when posting isn't on it).
        if let post = saved?.post, post.onPost {
          stops.append(.post)
          path = stops
          way = post.way
        } else {
          path = stops
        }
        return
      }
      path = []
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

  /// The shot as a draft, as it stands, and its photo when Drafts doesn't
  /// hold it yet (a new shot, or one whose draft was deleted since it was
  /// opened). Saved before its reading finished, it's read again when it's
  /// opened.
  /// What's written on Post it goes with it; `outbox` is the post in the
  /// outbox it's kept for, if any.
  private func asDraft(outbox: UUID?, place: PostPlace? = nil) -> (draft: Draft, photo: Data?)? {
    guard let shot else { return nil }
    let kept = draftID.map { id in drafts.all.contains { $0.id == id } } ?? false
    let onPost = path.contains(.post)
    var post = DraftPost(
      title: form.title, caption: form.caption, spotters: form.spotters, foundOn: form.foundOn,
      place: (place ?? form.place).map(DraftPlace.init), way: onPost ? way : nil, onPost: onPost, outbox: outbox)
    if post.isEmpty { post = DraftPost() }
    let draft = Draft(
      id: draftID ?? UUID(), source: shot.source, takenAt: shot.takenAt, takenOn: shot.foundOn,
      numbers: reading == .reading || reading == .idle ? nil : numbers, way: draft, place: draftPlace,
      post: post.isEmpty ? nil : post)
    return (draft, kept ? nil : shot.file.data)
  }

  /// Saves the shot as it stands to Drafts, for later, and goes back to the
  /// live camera for the next sign.
  @discardableResult
  func saveDraft() -> Bool {
    takeBack()
    // Saved for later while fixing a refused post: it moves to Drafts, and
    // Home's note about the post goes.
    guard let shot, let (saved, photo) = asDraft(outbox: nil) else { return false }
    guard drafts.save(saved, photo: photo) else { return false }
    if let fixing { outbox?.remove(fixing) }
    // Drafts are known by where they were taken: the town at the photo's
    // own GPS spot, looked up now (Drafts tries again if this can't).
    if saved.place == nil, let latitude = shot.file.facts.latitude, let longitude = shot.file.facts.longitude {
      let drafts = drafts
      let id = saved.id
      Task {
        if let town = await Places.town(latitude: latitude, longitude: longitude) { drafts.setPlace(town.label, for: id) }
      }
    }
    finishPosting()
    path = []
    return true
  }

  /// The app is leaving the screen, where the system may end it without a
  /// word: a shot that's neither posted nor saved goes to Drafts as it
  /// stands, so the photo isn't lost with the app. Nothing on screen
  /// changes, and `takeBack` undoes it if the player comes back first.
  func keepSafe() {
    // Once it's posted, the outbox has it.
    let inOutbox = path.contains { if case .posted = $0 { true } else { false } }
    guard safekept == nil, !inOutbox, let (draft, photo) = asDraft(outbox: fixing) else { return }
    safekept = drafts.keepSafe(draft, photo: photo)
  }

  /// The player is back (or the shot was posted or saved meanwhile):
  /// Drafts are as they were before `keepSafe`.
  func takeBack() {
    guard let kept = safekept else { return }
    safekept = nil
    drafts.takeBack(kept)
  }

  /// Puts the post in the outbox. Its draft is kept with it (the photo as
  /// taken, the numbers, the math and what's written on Post it), off the
  /// Drafts list, until the post is up: if the server refuses it, Home's
  /// note offers "Fix the post". A refused post being fixed is replaced.
  /// Throws, with the shot still open, when the phone can't keep the post.
  func send(_ post: SignPost, photo: Data, picture: UIImage?, handle: String) throws -> UUID {
    guard let outbox else { throw CocoaError(.fileWriteUnknown) }
    takeBack()
    let id = UUID()
    drafts.inOutbox.insert(id)
    var kept: Draft?
    if let (draft, original) = asDraft(outbox: id, place: post.place), drafts.save(draft, photo: original) { kept = draft }
    do {
      _ = try outbox.add(post, photo: photo, picture: picture, handle: handle, id: id)
    } catch {
      drafts.inOutbox.remove(id)
      // Not in the outbox: the draft is as it was before (a plain draft,
      // or still the refused post's), so nothing written is lost.
      if var kept {
        kept.post?.outbox = fixing
        _ = drafts.save(kept, photo: nil)
        draftID = kept.id
      }
      throw error
    }
    if let old = fixing, old != id { outbox.remove(old) }
    fixing = nil
    refusal = nil
    draftID = nil
    return id
  }

  /// The shot is posted (or on its way, in the outbox): it leaves, so
  /// Capture opens on the camera with nothing behind its thumbnail.
  func finishPosting() {
    work?.cancel()
    shot = nil
    reading = .idle
    numbers = NumberList()
    draft = nil
    way = nil
    reviewing = false
    draftID = nil
    draftPlace = nil
    form = PostForm()
    fixing = nil
    refusal = nil
    aside = false
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
  /// `-RSMPost YES` the step after (`-RSMWay <math>` writes the math on
  /// Solve, or posts it from `-RSMPost`), and `-RSMLandscape YES` turns
  /// sideways. `-RSMSaveDraft YES` saves the shot to Drafts once it's
  /// read (with `-RSMWay`'s math, if given), `-RSMDrafts YES` opens the
  /// Drafts list and `-RSMDrafts open` picks up the newest draft.
  func script() {
    #if DEBUG
      guard let what = Script.value("RSMCapture") else { return }
      begin()
      if Script.value("RSMDrafts") == "open", let newest = drafts.listed.first {
        resume(newest)
      } else if what == "sample", let sample = SampleSign.photo() {
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
        if Script.flag("RSMSaveDraft") {
          if let scripted = Script.text("RSMWay") { draft = WayDraft(tiles: numbers.kept, text: scripted) }
          saveDraft()
        }
        if Script.flag("RSMPost") {
          // With `-RSMWay`, posted as if solved: the math must work.
          if let scripted = Script.text("RSMWay"),
            case .works(let solved) = WayDraft(tiles: numbers.kept, text: scripted).status
          {
            way = solved.canonical
          }
          path = [.check, .post]
        }
      }
    #endif
  }
}
