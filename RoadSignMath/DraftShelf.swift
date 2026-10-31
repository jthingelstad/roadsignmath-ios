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

  init(folder: DraftFolder = .standard) {
    self.folder = folder
    all = folder.all()
  }

  /// Saves a draft (`photo` the first time); false when the phone couldn't.
  func save(_ draft: Draft, photo: Data?) -> Bool {
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

  /// The small picture for the list, read once.
  func thumbnail(of id: UUID) -> UIImage? {
    if let kept = thumbnails[id] { return kept }
    let image = UIImage(contentsOfFile: folder.thumbnail(of: id).path(percentEncoded: false))
    thumbnails[id] = image
    return image
  }
}
