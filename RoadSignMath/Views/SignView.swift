import MapKit
import RoadSignMathAPI
import SwiftUI

/// A sign: its photos whole, the math on the plate, who found it, when and
/// where, every way found so far, the numbers it was read as, and where it
/// is on the map.
struct SignView: View {
  let id: String

  @Environment(Store.self) private var store
  @State private var detail: SignDetail?
  @State private var failed: String?
  @State private var showNumbers = false

  private var sign: Sign? { detail?.sign ?? store.knownSign(id) }

  var body: some View {
    Group {
      if let sign {
        page(sign)
      } else if let failed {
        Notice(symbol: "signpost.right", title: "Can’t open this sign", message: failed,
               action: ("Try again", { Task { await load() } }))
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(Color.card)
    .navigationTitle(sign?.title ?? "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if let sign {
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: sign.url, subject: Text(sign.title)) {
            Image(systemName: "square.and.arrow.up")
          }
          .accessibilityLabel("Share this sign")
        }
      }
    }
    .task { await load() }
    .refreshable { await load(fresh: true) }
  }

  private func load(fresh: Bool = false) async {
    do {
      detail = try await store.detail(id, fresh: fresh)
      failed = nil
    } catch {
      if !Store.cancelled(error) { failed = Store.say(error) }
    }
  }

  private func page(_ sign: Sign) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        PhotoPager(photos: sign.photos)
        VStack(alignment: .leading, spacing: 14) {
          if let way = sign.firstWay {
            SignPlate(text: way.text, tex: way.tex, size: 26, large: true)
          }
          finder(sign)
          if let caption = sign.caption, !caption.isEmpty {
            Text(caption).face(.body).foregroundStyle(Color.ink2).lineSpacing(3)
          }
          ways(sign)
          if let numbers = sign.numbers, !numbers.isEmpty { numbersBlock(numbers) }
          if sign.place.lat != nil, sign.place.lng != nil { MiniMap(sign: sign) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 32)
      }
    }
  }

  private func finder(_ sign: Sign) -> some View {
    HStack(spacing: 10) {
      Avatar(name: sign.leadFinder?.name ?? "?", color: store.color(for: sign.leadFinder?.handle), size: 38)
      VStack(alignment: .leading, spacing: 2) {
        Text(sign.finderNames).face(.nameLarge).foregroundStyle(Color.ink)
        Text("\(sign.foundLong)\(String.dot)\(sign.place.label)")
          .face(.meta)
          .foregroundStyle(Color.ink3)
      }
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private func ways(_ sign: Sign) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(detail.map { $0.ways.count == 1 ? "One way so far" : "\($0.ways.count) ways so far" } ?? sign.waysSoFar)
        .face(.section)
        .foregroundStyle(Color.ink)
        .accessibilityAddTraits(.isHeader)
      if let detail {
        ForEach(detail.ways) { way in
          HStack(spacing: 10) {
            MathLine(text: way.text, tex: way.tex, size: 19, light: 0x1F3A2E, dark: 0xCDE8DA, fallback: .bodyBold, leading: true)
              .frame(maxWidth: .infinity, alignment: .leading)
            if let by = way.by {
              Text(by.name).face(.meta).foregroundStyle(Color.ink2)
            }
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
          .background(Color.wayGround, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          .accessibilityElement(children: .combine)
        }
      } else if let way = sign.firstWay {
        MathLine(text: way.text, tex: way.tex, size: 19, light: 0x1F3A2E, dark: 0xCDE8DA, fallback: .bodyBold, leading: true)
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
          .background(Color.wayGround, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          .redacted(reason: .placeholder)
      }
    }
  }

  private func numbersBlock(_ numbers: [SignNumber]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Button {
        withAnimation(.snappy) { showNumbers.toggle() }
      } label: {
        HStack {
          Text("The numbers on the sign").face(.action)
          Spacer()
          Image(systemName: "chevron.down")
            .rotationEffect(.degrees(showNumbers ? 180 : 0))
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.ruleStrong, lineWidth: 1.5) }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .sensoryFeedback(.selection, trigger: showNumbers)
      .accessibilityValue(showNumbers ? "Shown" : "Hidden")

      if showNumbers {
        FlowLayout(spacing: 6) {
          ForEach(Array(numbers.enumerated()), id: \.offset) { _, number in
            NumberChip(number: number)
          }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
  }
}

/// A sign's photos, whole: one fills the width at its own shape; more page
/// side to side.
private struct PhotoPager: View {
  let photos: [Photo]

  var body: some View {
    if photos.count > 1 {
      TabView {
        ForEach(photos) { photo in
          PhotoView(url: photo.url, alt: photo.alt, pixels: 2000, contentMode: .fit)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .always))
      .aspectRatio(ratio, contentMode: .fit)
    } else if let photo = photos.first {
      PhotoView(url: photo.url, alt: photo.alt, pixels: 2000, contentMode: .fit)
        .aspectRatio(ratio, contentMode: .fit)
    }
  }

  /// The tallest photo's shape, kept no taller than square.
  private var ratio: CGFloat {
    let ratios = photos.map { CGFloat($0.width) / CGFloat(max($0.height, 1)) }
    return max(ratios.min() ?? 4 / 3, 1)
  }
}

/// A number as the sign shows it, with what it was read from.
private struct NumberChip: View {
  let number: SignNumber

  var body: some View {
    VStack(spacing: 1) {
      Text(number.value).face(.number).foregroundStyle(Color.greenInk)
      if let text = number.text, text != number.value {
        Text(text).face(.meta).foregroundStyle(Color.ink3).lineLimit(1)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(minWidth: 40, minHeight: 36)
    .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.greenInk, lineWidth: 1.5) }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
  }

  private var label: String {
    var words = number.value
    if let text = number.text, text != number.value { words += ", from \(text)" }
    if let why = number.why { words += ". \(why)" }
    return words
  }
}

/// Where the sign is, small; tap for the big map.
private struct MiniMap: View {
  let sign: Sign
  @Environment(Store.self) private var store

  var body: some View {
    let spot = CLLocationCoordinate2D(latitude: sign.place.lat ?? 0, longitude: sign.place.lng ?? 0)
    Button { store.showOnMap(sign) } label: {
      Map(initialPosition: .region(MKCoordinateRegion(center: spot, latitudinalMeters: sign.place.approximate ? 60_000 : 8_000,
                                                      longitudinalMeters: sign.place.approximate ? 60_000 : 8_000)),
          interactionModes: []) {
        Annotation("", coordinate: spot) { PinDot(selected: false) }
      }
      .frame(height: 120)
      .allowsHitTesting(false)
      .overlay(alignment: .bottomLeading) {
        Text(sign.place.approximate ? "\(sign.place.label)\(String.dot)place approximate" : sign.place.label)
          .face(.metaBold)
          .foregroundStyle(Color.ink)
          .lineLimit(1)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
          .padding(8)
      }
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.rule) }
    }
    .buttonStyle(CardPress())
    .accessibilityLabel("Show on the map: \(sign.place.label)\(sign.place.approximate ? ", place approximate" : "")")
  }
}

/// Lays chips in rows, wrapping.
struct FlowLayout: Layout {
  var spacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
    return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for row in arrange(width: bounds.width, subviews: subviews) {
      var x = bounds.minX
      for index in row.items {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
    }
  }

  private struct Row { var items: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

  private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
    var rows: [Row] = []
    var row = Row()
    for (index, view) in subviews.enumerated() {
      let size = view.sizeThatFits(.unspecified)
      if !row.items.isEmpty && row.width + spacing + size.width > width {
        rows.append(row)
        row = Row(y: row.y + row.height + spacing)
      }
      row.width += (row.items.isEmpty ? 0 : spacing) + size.width
      row.height = max(row.height, size.height)
      row.items.append(index)
    }
    if !row.items.isEmpty { rows.append(row) }
    return rows
  }
}
