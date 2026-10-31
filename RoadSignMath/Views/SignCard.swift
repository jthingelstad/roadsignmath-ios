import RoadSignMathAPI
import SwiftUI

/// One sign in the feed: who found it and where, the photo, the math on
/// its green plate, then the title and caption.
struct SignCard: View {
  let sign: Sign
  var showMiles = false
  let zoom: Namespace.ID
  let open: () -> Void

  @Environment(Store.self) private var store
  @Environment(\.findWay) private var findWay
  @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 15

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button(action: open) {
        VStack(alignment: .leading, spacing: 0) {
          byline
          photo
          if let way = sign.firstWay {
            SignPlate(text: way.text, tex: way.tex)
              .padding(.horizontal, 16)
              .padding(.top, 10)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(CardPress())
      .accessibilityElement(children: .combine)
      .accessibilityHint("Opens the sign")

      actions
      words
    }
    .background(Color.card)
    .overlay(alignment: .top) { Color.rule.frame(height: 1) }
    .overlay(alignment: .bottom) { Color.rule.frame(height: 1) }
  }

  private var byline: some View {
    HStack(spacing: 10) {
      Avatar(name: sign.leadFinder?.name ?? "?", color: store.color(for: sign.leadFinder?.handle))
      VStack(alignment: .leading, spacing: 1) {
        Text(sign.finderNames).face(.name).foregroundStyle(Color.ink)
        Text(sign.place.label).face(.meta).foregroundStyle(Color.ink3).lineLimit(1)
      }
      Spacer(minLength: 8)
      Text(showMiles ? (sign.milesText ?? sign.foundShort) : sign.foundShort)
        .face(showMiles ? .miles : .meta)
        .foregroundStyle(Color.ink3)
        .lineLimit(1)
        .fixedSize()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  @ViewBuilder private var photo: some View {
    if let first = sign.photos.first {
      PhotoView(url: first.url, alt: first.alt)
        .frame(height: 270)
        .frame(maxWidth: .infinity)
        .clipped()
        .matchedTransitionSource(id: sign.id, in: zoom)
    }
  }

  private var actions: some View {
    HStack(spacing: 4) {
      if sign.visibility == .shown, let findWay {
        Button { findWay.open(sign) } label: {
          Label(sign.wayCount == 0 ? "Find a way" : "Find another way", systemImage: "pencil")
            .face(.pill)
            .foregroundStyle(Color.greenInk)
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityValue(sign.waysSoFar)
        .padding(.leading, 8)
      } else {
        Text(sign.waysSoFar)
          .face(.metaBold)
          .foregroundStyle(Color.greenInk)
          .padding(.leading, 16)
      }
      Spacer()
      // A held or hidden sign has no public page and no pin: nothing to show or share.
      if sign.visibility == .shown {
        publicActions
      }
    }
    .frame(minHeight: 44)
    .foregroundStyle(Color.ink2)
    .buttonStyle(.plain)
    .padding(.trailing, 8)
    .padding(.top, 2)
  }

  @ViewBuilder private var publicActions: some View {
    if sign.place.lat != nil {
      Button { store.showOnMap(sign) } label: {
        Image(systemName: "mappin.and.ellipse")
          .font(.system(size: 19, weight: .medium))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Show \(sign.title) on the map")
    }
    ShareLink(item: sign.url, subject: Text(sign.title), message: Text(shareLine)) {
      Image(systemName: "square.and.arrow.up")
        .font(.system(size: 19, weight: .medium))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .accessibilityLabel("Share \(sign.title)")
  }

  private var words: some View {
    (Text(sign.title).font(Face.bodyBold.font(size: bodySize)).foregroundStyle(Color.ink)
      + Text(sign.caption.map { "  " + $0 } ?? "").font(Face.body.font(size: bodySize)).foregroundStyle(Color.ink2))
      .lineSpacing(3)
      .padding(.horizontal, 16)
      .padding(.bottom, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var shareLine: String {
    sign.firstWay.map { "\($0.text) on a sign in \(sign.place.label)" } ?? sign.title
  }
}

/// A card dims a touch while pressed, and springs back.
struct CardPress: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.85 : 1)
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .animation(.snappy(duration: 0.18), value: configuration.isPressed)
  }
}
