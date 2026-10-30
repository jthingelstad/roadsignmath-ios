import MapKit
import MathArt
import RoadSignMathAPI
import SwiftUI

/// Every sign on a map: pins that gather into clusters as you zoom out,
/// search, a year filter, and a card for the chosen sign with the signs
/// nearest it.
struct MapScreen: View {
  @Environment(Store.self) private var store
  @State private var year: Int?
  @State private var query = ""
  @State private var selected: String?
  /// Several signs at one spot, chosen from a cluster that can't split.
  @State private var together: [String] = []
  @State private var focus: MapFocus?
  @FocusState private var searching: Bool

  var body: some View {
    @Bindable var store = store
    NavigationStack(path: $store.mapPath) {
      ZStack(alignment: .top) {
        SignMap(pins: shown, selected: $selected, together: $together, focus: $focus)
          .ignoresSafeArea(edges: .top)
          .onTapGesture { searching = false }
        controls
      }
      .safeAreaInset(edge: .bottom, spacing: 0) { panel }
      .toolbar(.hidden, for: .navigationBar)
      .navigationDestination(for: String.self) { SignView(id: $0) }
      .overlay {
        if case .failed(let why) = store.mapLoad {
          Notice(symbol: "map", title: "Can’t load the map", message: why,
                 action: ("Try again", { Task { await store.loadMap() } }))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(24)
        }
      }
    }
    .task {
      if store.mapLoad == .idle { await store.loadMap() }
      if store.latest.isEmpty { await store.loadLatest() }
      takeFocus()
      #if DEBUG
        // For screenshots: `-RSMSearch <words>` as a launch argument.
        if query.isEmpty, let words = UserDefaults.standard.string(forKey: "RSMSearch") { query = words }
      #endif
    }
    .onChange(of: query.isEmpty) { _, empty in
      if !empty { Task { await store.loadEverySign() } }
    }
    .onChange(of: store.mapFocus) { takeFocus() }
    .onChange(of: store.pins) { takeFocus() }
    .onChange(of: selected) { _, id in
      if id != nil { together = [] }
    }
    .sensoryFeedback(.selection, trigger: selected)
    .sensoryFeedback(.selection, trigger: year)
  }

  /// "Show on the map" from a sign: choose its pin and fly to it.
  private func takeFocus() {
    guard let id = store.mapFocus, let pin = store.pins.first(where: { $0.id == id }) else { return }
    store.mapFocus = nil
    year = nil
    query = ""
    focus = MapFocus(id: pin.id)
  }

  // MARK: What's shown

  private var shown: [Pin] {
    store.pins.filter { pin in
      (year == nil || pin.year == year) && matches(pin)
    }
  }

  private func matches(_ pin: Pin) -> Bool {
    let words = query.split(separator: " ").map { String($0) }
    guard !words.isEmpty else { return true }
    var hay = [pin.title, pin.state ?? "", stateName(pin.state)]
    if let sign = store.knownSign(pin.id) {
      hay.append(sign.place.label)
      hay += sign.finders.map(\.name)
      hay += sign.numbers?.map(\.value) ?? []
      if let way = sign.firstWay { hay.append(way.text) }
    }
    let text = hay.joined(separator: " ")
    return words.allSatisfy { word in
      if word.allSatisfy(\.isNumber) {
        // A number matches a whole number on the sign, not any digit.
        return text.split(whereSeparator: { !$0.isNumber && $0 != "." }).contains { $0 == word }
      }
      return text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }

  // MARK: Search and filter

  private var controls: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").foregroundStyle(Color.ink3)
        TextField("A town, a number, or a person", text: $query)
          .face(.search)
          .foregroundStyle(Color.ink)
          .focused($searching)
          .submitLabel(.search)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .accessibilityLabel("Search signs")
        if !query.isEmpty {
          Button {
            withAnimation(.snappy) { query = "" }
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(Color.ink3)
              .frame(width: 32, height: 44)
          }
          .accessibilityLabel("Clear search")
        }
      }
      .padding(.horizontal, 12)
      .frame(height: 44)
      .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

      ScrollView(.horizontal) {
        HStack(spacing: 6) {
          Pill(label: store.pins.isEmpty ? "All" : "All \(store.pins.count)", chosen: year == nil, floating: true) {
            withAnimation(.snappy) { year = nil }
          }
          ForEach(store.years.sorted(by: >), id: \.self) { y in
            Pill(label: String(y), chosen: year == y, floating: true) {
              withAnimation(.snappy) { year = year == y ? nil : y }
            }
          }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
      }
      .scrollIndicators(.hidden)
      .scrollClipDisabled()
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Show signs from")
    }
    .padding(.horizontal, 12)
    .padding(.top, 8)
  }

  // MARK: The card at the bottom

  @ViewBuilder private var panel: some View {
    VStack(alignment: .leading, spacing: 10) {
      Capsule().fill(Color.rule).frame(width: 40, height: 5).frame(maxWidth: .infinity)
        .accessibilityHidden(true)
      if !query.isEmpty {
        results
      } else if let id = selected, let pin = store.pins.first(where: { $0.id == id }) {
        PinCard(pin: pin)
        nearby(pin)
      } else if !together.isEmpty {
        here
      } else {
        summary
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
    .padding(.bottom, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
        .fill(Color.card)
        .shadow(color: .black.opacity(0.12), radius: 10, y: -4)
        .ignoresSafeArea(edges: .bottom)
    }
    .animation(.snappy(duration: 0.25), value: selected)
    .animation(.snappy(duration: 0.25), value: query.isEmpty)
    .animation(.snappy(duration: 0.25), value: together)
  }

  private var summary: some View {
    VStack(alignment: .leading, spacing: 4) {
      if store.pins.isEmpty {
        Text(store.mapLoad == .loading || store.mapLoad == .idle ? "Finding the signs…" : "No signs on the map yet")
          .face(.section).foregroundStyle(Color.ink)
      } else {
        Text(countLine(shown)).face(.section).foregroundStyle(Color.ink)
        Text("Tap a pin to see its sign, or search for a town, a number or a person.")
          .face(.meta)
          .foregroundStyle(Color.ink3)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.bottom, 4)
    .accessibilityElement(children: .combine)
  }

  private var results: some View {
    let found = shown
    return VStack(alignment: .leading, spacing: 2) {
      Text(found.isEmpty ? "No signs match “\(query)”" : found.count == 1 ? "One sign" : "\(found.count) signs")
        .face(.section)
        .foregroundStyle(Color.ink)
        .padding(.bottom, 2)
      ForEach(found.prefix(4)) { pin in
        PinRow(pin: pin, trailing: pin.year.map(String.init) ?? "") {
          searching = false
          query = ""
          focus = MapFocus(id: pin.id)
        }
      }
    }
  }

  private var here: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("\(together.count) signs here").face(.section).foregroundStyle(Color.ink).padding(.bottom, 2)
      ForEach(together.compactMap { id in store.pins.first { $0.id == id } }.prefix(5)) { pin in
        PinRow(pin: pin, trailing: pin.year.map(String.init) ?? "") { selected = pin.id }
      }
    }
  }

  @ViewBuilder private func nearby(_ pin: Pin) -> some View {
    let near = nearest(to: pin)
    if !near.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        Color.rule.frame(height: 1).padding(.bottom, 8)
        Text("Nearby").face(.name).foregroundStyle(Color.ink).accessibilityAddTraits(.isHeader)
        ForEach(near, id: \.pin.id) { item in
          PinRow(pin: item.pin, trailing: miles(item.meters)) { focus = MapFocus(id: item.pin.id) }
        }
      }
    }
  }

  private func nearest(to pin: Pin) -> [(pin: Pin, meters: Double)] {
    guard let here = pin.location else { return [] }
    return store.pins
      .filter { $0.id != pin.id }
      .compactMap { other in other.location.map { (pin: other, meters: $0.distance(from: here)) } }
      .sorted { $0.meters < $1.meters }
      .prefix(3)
      .map { $0 }
  }

  private func miles(_ meters: Double) -> String {
    let miles = meters / 1609.344
    if miles < 0.1 { return "here" }
    if miles < 10 { return miles.formatted(.number.precision(.fractionLength(1))) + " mi" }
    return miles.formatted(.number.precision(.fractionLength(0))) + " mi"
  }

  private func countLine(_ pins: [Pin]) -> String {
    let states = Set(pins.compactMap(\.state)).count
    let signs = pins.count == 1 ? "One sign" : "\(pins.count) signs"
    let where_ = states == 0 ? "" : states == 1 ? " in one state" : " in \(states) states"
    return signs + where_ + (year.map { " from \($0)" } ?? "")
  }
}

/// The chosen sign: its photo, title, math and who found it. Tap to open.
private struct PinCard: View {
  let pin: Pin
  @Environment(Store.self) private var store
  @State private var sign: Sign?

  var body: some View {
    Button { store.mapPath.append(pin.id) } label: {
      HStack(spacing: 12) {
        Group {
          if let thumb = pin.thumbUrl {
            PhotoView(url: thumb, alt: "", pixels: 300)
          } else {
            Color.photoGround
          }
        }
        .frame(width: 84, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 3) {
          Text(pin.title).face(.nameLarge).foregroundStyle(Color.ink).lineLimit(1)
          if let way = (sign ?? store.knownSign(pin.id))?.firstWay {
            MathLine(text: way.text, tex: way.tex, size: 15, light: 0x006348, dark: 0x5CC29A, fallback: .bodyBold, leading: true)
          }
          Text(meta).face(.meta).foregroundStyle(Color.ink3).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.right")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Color.ink3)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(CardPress())
    .accessibilityElement(children: .combine)
    .accessibilityHint("Opens the sign")
    .task(id: pin.id) {
      sign = store.knownSign(pin.id)
      if sign == nil { sign = try? await store.detail(pin.id).sign }
    }
  }

  private var meta: String {
    let known = sign ?? store.knownSign(pin.id)
    var parts: [String] = []
    if let names = known?.finderNames { parts.append(names) }
    parts.append(known?.foundMonth ?? pin.foundOn)
    if let label = known?.place.label { parts.append(label) }
    return parts.joined(separator: String.dot)
  }
}

/// A sign in a list on the map's card: a pin, its title and a note at the end.
private struct PinRow: View {
  let pin: Pin
  let trailing: String
  let action: () -> Void
  @Environment(Store.self) private var store

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        PinDot(selected: false, size: 12)
        (Text(pin.title).font(Face.bodyBold.font(size: 15))
          + Text(by).font(Face.body.font(size: 15)).foregroundStyle(Color.ink3))
          .foregroundStyle(Color.ink)
          .lineLimit(1)
        Spacer(minLength: 8)
        Text(trailing).face(.miles).foregroundStyle(Color.ink2)
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var by: String { store.knownSign(pin.id).map { "\(String.dot)\($0.finderNames)" } ?? "" }
}

/// A sign's pin: the sign's green inside a white ring; yellow when chosen.
struct PinDot: View {
  let selected: Bool
  var size: CGFloat = 18

  var body: some View {
    Circle()
      .fill(Color.signGreen)
      .frame(width: size, height: size)
      .overlay { Circle().strokeBorder(selected ? Color.signYellow : .white, lineWidth: selected ? 3.5 : max(2, size / 7)) }
      .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
      .accessibilityHidden(true)
  }
}

struct MapFocus: Equatable {
  let id: String
  private let token = UUID()
}

extension Pin {
  var location: CLLocation? {
    guard let lat, let lng else { return nil }
    return CLLocation(latitude: lat, longitude: lng)
  }
}

/// "MN" as "Minnesota", so a search for the state's name finds its signs.
func stateName(_ code: String?) -> String {
  guard let code else { return "" }
  return usStates[code] ?? ""
}

private let usStates: [String: String] = [
  "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California", "CO": "Colorado",
  "CT": "Connecticut", "DE": "Delaware", "DC": "District of Columbia", "FL": "Florida", "GA": "Georgia",
  "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas",
  "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts",
  "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri", "MT": "Montana",
  "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
  "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
  "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
  "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
  "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
]
