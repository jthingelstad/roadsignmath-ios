import Foundation
import RoadSignMathAPI
import SignCapture

/// What Home's note about a post offers, by the post's state. A refused
/// post whose draft is kept offers "Fix the post", which opens Post it
/// again with the photo, numbers, title, caption, spotters and way as they
/// were, and the server's words.
public enum OutboxChoice: String, Sendable, Hashable, CaseIterable {
  /// Posted: open the sign.
  case seeIt
  /// Refused, with its draft kept: back to Post it to change it.
  case fixThePost
  /// Refused or waiting: send it again, as it is, now.
  case tryAgain
  /// Waiting after a failed try: go now instead of at the end of the wait.
  case tryNow
  /// Refused: forget it. Asks first, since its photo and math go too.
  case delete

  /// The words on the note.
  public var label: String {
    switch self {
    case .seeIt: "See it"
    case .fixThePost: "Fix the post"
    case .tryAgain: "Try again"
    case .tryNow: "Try now"
    case .delete: "Delete"
    }
  }
}

extension OutboxItem {
  /// The choices on Home's note, in the order shown. `sending` is whether
  /// this post is on the wire now; `canFix` whether its draft is kept (a
  /// post made before drafts were kept with posts has none).
  public func choices(sending: Bool, canFix: Bool) -> [OutboxChoice] {
    switch state {
    case .posted: return [.seeIt]
    case .refused: return (canFix ? [.fixThePost] : []) + [.tryAgain, .delete]
    case .waiting(let problem): return problem != nil && !sending ? [.tryNow] : []
    case .needsSignIn, .held: return []
    }
  }

  /// The server's words when it said no.
  public var refusal: String? {
    if case .refused(let message) = state { return message }
    return nil
  }
}

/// The drafts kept for posts in the outbox: one per post, so a post the
/// server refuses can be fixed with everything it had, and one that goes
/// up leaves nothing behind.
public enum OutboxDrafts {
  /// The draft a post went from, if it's kept.
  public static func draft(for item: OutboxItem, in drafts: [Draft]) -> Draft? {
    drafts.first { $0.post?.outbox == item.id }
  }

  /// Drafts whose post is up, posted or held: done with. A draft whose post
  /// isn't in the outbox at all is left alone (and listed in Drafts again),
  /// since a post this build couldn't read is set aside, not gone.
  public static func done(_ drafts: [Draft], items: [OutboxItem]) -> [UUID] {
    let up = Set(items.filter { $0.posted != nil }.map(\.id))
    return drafts.filter { $0.post?.outbox.map(up.contains) ?? false }.map(\.id)
  }

  /// The posts still on their way or refused: their drafts stay out of the
  /// Drafts list.
  public static func waiting(_ items: [OutboxItem]) -> Set<UUID> {
    Set(items.filter { $0.posted == nil }.map(\.id))
  }
}

extension DraftPlace {
  public init(_ place: PostPlace) {
    self.init(label: place.label, state: place.state, lat: place.lat, lng: place.lng, approximate: place.approximate)
  }
}

extension PostPlace {
  public init(_ place: DraftPlace) {
    self.init(label: place.label, state: place.state, lat: place.lat, lng: place.lng, approximate: place.approximate)
  }
}

extension PostParts {
  /// The place to post from a town the player picked when the photo has a
  /// spot of its own (its town couldn't be looked up, with no signal say):
  /// the town's name and state, pinned at the photo's spot, as a place
  /// looked up from the photo would be. With no spot, the town as picked.
  public static func place(picked town: PostPlace, photoLatitude lat: Double?, longitude lng: Double?) -> PostPlace {
    guard let lat, let lng else { return town }
    return PostPlace(label: town.label, state: town.state, lat: lat, lng: lng, approximate: false)
  }
}
