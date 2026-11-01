import Foundation
import Observation
import SignCapture
import UIKit

/// The drafts on this phone, for the screens: signs saved for later from
/// Capture, newest first. They never leave the phone (beyond its backup).
@MainActor @Observable
final class DraftShelf {
  private(set) var all: [Draft]
  @ObservationIgnored private let folder: DraftFolder
  @ObservationIgnored private var thumbnails: [UUID: UIImage] = [:]
  /// Drafts whose town has been looked for while the app is open.
  @ObservationIgnored private var looked: Set<UUID> = []

  init(folder: DraftFolder = .standard) {
    self.folder = folder
    all = folder.all()
  }

  /// Saves a draft (`photo` the first time); false when the phone couldn't.
  func save(_ draft: Draft, photo: Data?) -> Bool {
    var draft = draft
    // A town looked up after this draft was picked up again is kept.
    if draft.place == nil, let kept = all.first(where: { $0.id == draft.id })?.place { draft.place = kept }
    do {
      try folder.save(draft, photo: photo)
    } catch {
      return false
    }
    thumbnails[draft.id] = nil
    all.removeAll { $0.id == draft.id }
    all.insert(draft, at: 0)
    return true
  }

  func remove(_ id: UUID) {
    folder.remove(id)
    thumbnails[id] = nil
    all.removeAll { $0.id == id }
  }

  func photo(of id: UUID) -> Data? { folder.photo(of: id) }

  /// The town a draft's photo was taken in, once looked up. The draft
  /// keeps its place in the list, which is by when it was saved.
  func setPlace(_ place: String, for id: UUID) {
    guard let at = all.firstIndex(where: { $0.id == id }), all[at].place == nil else { return }
    var draft = all[at]
    draft.place = place
    guard (try? folder.save(draft, photo: nil)) != nil else { return }
    all[at] = draft
  }

  /// Looks up the town for drafts whose photo knows where it was taken but
  /// whose town isn't kept: saved with no signal, or before drafts kept
  /// their place. One that can't be looked up now is tried again next time.
  func findPlaces() async {
    for draft in all where draft.place == nil && draft.source != .camera && !looked.contains(draft.id) {
      looked.insert(draft.id)
      guard let data = folder.photo(of: draft.id) else { continue }
      let facts = await Task.detached(priority: .utility) { PhotoFile(data: data)?.facts }.value
      guard let latitude = facts?.latitude, let longitude = facts?.longitude else { continue }
      if let town = await Places.town(latitude: latitude, longitude: longitude) {
        setPlace(town.label, for: draft.id)
      } else {
        looked.remove(draft.id)
      }
    }
  }

  /// The small picture for the list, read once.
  func thumbnail(of id: UUID) -> UIImage? {
    if let kept = thumbnails[id] { return kept }
    let image = UIImage(contentsOfFile: folder.thumbnail(of: id).path(percentEncoded: false))
    thumbnails[id] = image
    return image
  }
}
