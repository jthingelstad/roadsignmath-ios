import Foundation
import Testing

@testable import Posting
@testable import RoadSignMathAPI
@testable import SignCapture

/// A refused post's choices on Home, and the drafts kept for posts on
/// their way.
@Suite struct OutboxDraftsTests {
  let item = OutboxItem(
    handle: "zoe",
    post: SignPost(
      title: "Ames Math", numbers: [PostNumber(value: "7")], place: PostPlace(label: "Ames, IA", approximate: true),
      foundOn: "2026-10-30"))
  let sign = PostedSign(id: "01sign", slug: "ames-math", title: "Ames Math", url: URL(string: "https://roadsignmath.xyz/signs/ames-math")!)

  func with(_ state: OutboxItem.State) -> OutboxItem {
    var item = item
    item.state = state
    return item
  }

  @Test func aRefusedPostWithItsDraftCanBeFixed() {
    let refused = with(.refused("Use every number on the sign: 7 is left out"))
    #expect(refused.choices(sending: false, canFix: true) == [.fixThePost, .tryAgain, .delete])
    #expect(refused.refusal == "Use every number on the sign: 7 is left out")
    #expect(OutboxChoice.fixThePost.label == "Fix the post")
  }

  @Test func aRefusedPostFromBeforeDraftsWereKeptCanBeTriedOrDeleted() {
    #expect(with(.refused("No.")).choices(sending: false, canFix: false) == [.tryAgain, .delete])
  }

  @Test func theOtherStates() {
    #expect(with(.posted(sign)).choices(sending: false, canFix: true) == [.seeIt])
    #expect(with(.held(sign, note: nil)).choices(sending: false, canFix: true) == [])
    #expect(with(.needsSignIn).choices(sending: false, canFix: true) == [])
    #expect(with(.waiting(problem: nil)).choices(sending: false, canFix: true) == [])
    #expect(with(.waiting(problem: Delivery.offline)).choices(sending: false, canFix: true) == [.tryNow])
    #expect(with(.waiting(problem: Delivery.offline)).choices(sending: true, canFix: true) == [])
    #expect(with(.posted(sign)).refusal == nil)
  }

  func draft(for id: UUID?) -> Draft {
    Draft(source: .sample, takenAt: nil, numbers: nil, way: nil, post: DraftPost(title: "Ames Math", onPost: true, outbox: id))
  }

  @Test func aDraftGoesOnceItsPostIsUpAndStaysWhileRefused() {
    let refused = with(.refused("No."))
    let posted = OutboxItem(handle: "zoe", post: item.post, id: UUID())
    var up = posted
    up.state = .posted(sign)
    let mine = draft(for: refused.id)
    let gone = draft(for: up.id)
    let plain = Draft(source: .camera, takenAt: nil, numbers: nil, way: nil)
    let orphan = draft(for: UUID())
    let drafts = [mine, gone, plain, orphan]
    #expect(OutboxDrafts.done(drafts, items: [refused, up]) == [gone.id])
    #expect(OutboxDrafts.draft(for: refused, in: drafts) == mine)
    let waiting = OutboxDrafts.waiting([refused, up])
    #expect(waiting == [refused.id])
    // Out of the Drafts list while its post is in the outbox; back in it
    // when its post isn't there at all (set aside by an older build).
    #expect(!mine.isListed(inOutbox: waiting))
    #expect(plain.isListed(inOutbox: waiting))
    #expect(orphan.isListed(inOutbox: waiting))
  }

  @Test func aPickedTownKeepsThePhotosOwnSpot() {
    let town = PostPlace(label: "Twin Lakes, MN", state: "MN", lat: 43.5, lng: -93.4, approximate: true)
    let kept = PostParts.place(picked: town, photoLatitude: 43.56, longitude: -93.42)
    #expect(kept == PostPlace(label: "Twin Lakes, MN", state: "MN", lat: 43.56, lng: -93.42, approximate: false))
    #expect(PostParts.place(picked: town, photoLatitude: nil, longitude: nil) == town)
  }

  @Test func aPlaceRoundTripsThroughADraft() {
    let place = PostPlace(label: "Ames, IA", state: "IA", lat: 42.03, lng: -93.62, approximate: false)
    #expect(PostPlace(DraftPlace(place)) == place)
  }
}
