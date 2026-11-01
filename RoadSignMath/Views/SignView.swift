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
  @Environment(\.opener) private var opener
  @Environment(\.findWay) private var findWay
  @Environment(Account.self) private var account
  @Environment(\.dismiss) private var dismiss
  /// The ⋯ menu's report sheet, block and delete confirms.
  @State private var reporting = false
  @State private var confirmBlock: Poster?
  @State private var confirmDelete = false
  @State private var deleting = false
  @State private var problem: String?
  /// Signed out, Report or Block asks you to sign in first.
  @State private var askSignIn = false
  @State private var afterSignIn: AfterSignIn?
  /// The page closes once the report sheet does: the sign came down, or
  /// its poster is blocked.
  @State private var leaveAfterReport = false

  enum AfterSignIn { case report, block }

  private var sign: Sign? { (detail?.sign ?? store.knownSign(id)).map(store.current) }

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
        // The whole title, on two lines and smaller before it's cut short:
        // a 60-letter title doesn't fit the bar's one line, and the page
        // shows it nowhere else.
        ToolbarItem(placement: .principal) {
          Text(sign.title)
            .font(sign.title.count > 28 ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(Color.ink)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        }
        ToolbarItem(placement: .topBarTrailing) { menu(sign) }
      }
    }
    .sheet(isPresented: $reporting, onDismiss: { if leaveAfterReport { dismiss() } }) {
      if let sign {
        ReportSheet(sign: sign, poster: Poster(of: sign, players: store.players)) { outcome in
          if outcome.outcome == .hidden {
            store.signGone(sign.id)
            leaveOnceReported()
          }
        } blocked: {
          if let poster = Poster(of: sign, players: store.players) { store.blocked(poster.handle) }
          leaveOnceReported()
        }
        .presentationDetents([.medium, .large])
        .closesForSnap()
      }
    }
    .confirmationDialog(confirmBlock.map { "Block \($0.name)?" } ?? "", isPresented: Binding(get: { confirmBlock != nil }, set: { if !$0 { confirmBlock = nil } }),
                        titleVisibility: .visible, presenting: confirmBlock) { poster in
      Button("Block \(poster.name)", role: .destructive) { block(poster) }
    } message: { _ in
      Text(BlockWords.what + " Unblock them in Settings whenever you like.")
    }
    // "Snap a road sign" closes the ⋯ menu's questions, as it does the sheets.
    .onChange(of: Snap.shared.clearing) {
      confirmBlock = nil
      confirmDelete = false
    }
    .alert("Delete this sign?", isPresented: $confirmDelete, presenting: sign) { sign in
      Button("Delete this sign", role: .destructive) { delete(sign) }
      Button("Keep it", role: .cancel) {}
    } message: { sign in
      Text(deleteWords(sign))
    }
    .alert("That didn’t work", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } }), presenting: problem) { _ in
      Button("OK", role: .cancel) {}
    } message: { problem in
      Text(problem)
    }
    .signInFirst($askSignIn, title: afterSignIn == .block ? "Sign in to block" : "Sign in to report it",
                 waiting: afterSignIn == .block ? "Blocking is for players. Sign in, then block whoever posted this sign."
                   : "Reports come from players. Sign in, then tell us what’s wrong with this sign.") {
      switch afterSignIn {
      case .report: reporting = true
      case .block: if let sign, let poster = Poster(of: sign, players: store.players), !isMine(sign) { confirmBlock = poster }
      case nil: break
      }
      afterSignIn = nil
    }
    .task { await load() }
    .refreshable { await load(fresh: true) }
    .countsView(sign.flatMap { ViewPath.sign($0.slug) })
    // A way just added from here goes on the list at once.
    .onChange(of: store.details[id]) { _, now in if let now { detail = now } }
  }

  // MARK: The ⋯ menu

  /// Share, then for someone else's sign Report and Block, for yours Delete.
  private func menu(_ sign: Sign) -> some View {
    Menu {
      ShareLink(item: sign.url, subject: Text(sign.title)) {
        Label("Share this sign", systemImage: "square.and.arrow.up")
      }
      if isMine(sign) {
        Section {
          Button(role: .destructive) { confirmDelete = true } label: {
            Label("Delete this sign", systemImage: "trash")
          }
          .disabled(deleting)
        }
      } else if sign.visibility == .shown {
        Section {
          Button { ask(.report) } label: { Label("Report this sign", systemImage: "flag") }
          if let poster = Poster(of: sign, players: store.players) {
            Button { ask(.block, poster) } label: { Label("Block \(poster.name)", systemImage: "hand.raised") }
          }
        }
      }
    } label: {
      if deleting { ProgressView() } else { Image(systemName: "ellipsis.circle") }
    }
    .accessibilityLabel("More")
  }

  /// You posted it: yours to delete, not to report.
  private func isMine(_ sign: Sign) -> Bool {
    guard let handle = account.me?.handle, let poster = sign.postedBy else { return false }
    return account.signedIn && handle == poster
  }

  private func ask(_ next: AfterSignIn, _ poster: Poster? = nil) {
    guard account.signedIn else {
      afterSignIn = next
      askSignIn = true
      return
    }
    switch next {
    case .report: reporting = true
    case .block: confirmBlock = poster
    }
  }

  private func block(_ poster: Poster) {
    Task {
      do {
        try await account.block(poster.handle)
        store.blocked(poster.handle)
        account.notice = "\(poster.name) is blocked. Unblock them in Settings whenever you like."
        dismiss()
      } catch {
        problem = Account.say(error)
      }
    }
  }

  /// What deleting takes: the photos, the hearts, and every way, other
  /// players' too, counted when the ways are in hand.
  private func deleteWords(_ sign: Sign) -> String {
    let photos = sign.photos.count > 1 ? "its photos" : "its photo"
    let others = detail?.ways.filter { $0.by != nil && $0.by?.handle != account.me?.handle }.count ?? 0
    let ways: String
    switch others {
    case 0: ways = "every way found on it"
    case 1: ways = "every way found on it, including one way another player found"
    default: ways = "every way found on it, including \(others) ways other players found"
    }
    return "This takes down the sign, \(photos), its hearts and \(ways). It can’t be undone."
  }

  /// The sign is gone for you: leave it once the sheet has closed, or now
  /// if it already has ("Snap a road sign" can close it mid-send).
  private func leaveOnceReported() {
    if reporting { leaveAfterReport = true } else { dismiss() }
  }

  private func delete(_ sign: Sign) {
    deleting = true
    Task {
      do {
        try await account.deleteSign(sign.id)
        store.signGone(sign.id)
        dismiss()
      } catch {
        problem = Account.say(error)
      }
      deleting = false
    }
  }

  private func load(fresh: Bool = false) async {
    do {
      detail = try await store.detail(id, fresh: fresh)
      failed = nil
      // The poster's name for "Block Sam", when they aren't a finder; a
      // link can open a sign before Home has read the players.
      if store.players.isEmpty { await store.loadPlayers() }
      #if DEBUG
        if !fresh, Script.flag("RSMFindWay"), let findWay, let sign = detail?.sign { findWay.open(sign) }
        // `-RSMReport YES`, `-RSMBlock YES`, `-RSMDelete YES`: the ⋯ menu's
        // sheet and confirms, as if chosen (`-RSMBlock send` blocks the
        // poster, only ever against `npm run dev`).
        if !fresh, let sign = detail?.sign {
          if Script.flag("RSMReport") { ask(.report) }
          if Script.value("RSMBlock") == "send", let poster = Poster(of: sign, players: store.players) {
            block(poster)
          } else if Script.flag("RSMBlock") {
            ask(.block, Poster(of: sign, players: store.players))
          }
          if Script.flag("RSMDelete"), isMine(sign) { confirmDelete = true }
        }
      #endif
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
          HStack(alignment: .center, spacing: 10) {
            finder(sign)
            if sign.visibility == .shown { HeartButton(sign: sign, large: true) }
          }
          if let caption = sign.caption, !caption.isEmpty {
            Text(caption).face(.body).foregroundStyle(Color.ink2).lineSpacing(3)
          }
          ways(sign)
          wayAndNumbers(sign)
          if sign.place.lat != nil, sign.place.lng != nil { MiniMap(sign: sign) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 32)
      }
    }
  }

  /// Who found it; a tap opens the page of a finder who plays (a menu of
  /// them when there are several).
  @ViewBuilder private func finder(_ sign: Sign) -> some View {
    let players = opener == nil ? [] : sign.foundBy.filter { $0.handle != nil }
    if players.count == 1, let handle = players[0].handle {
      Button { opener?.player(handle) } label: { byline(sign) }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(players[0].name)’s page")
    } else if players.count > 1 {
      Menu {
        ForEach(players, id: \.self) { finder in
          Button(finder.name) { if let handle = finder.handle { opener?.player(handle) } }
        }
      } label: {
        byline(sign)
      }
      .buttonStyle(.plain)
      .accessibilityHint("Opens a finder’s page")
    } else {
      byline(sign)
    }
  }

  private func byline(_ sign: Sign) -> some View {
    HStack(spacing: 10) {
      Avatar(name: sign.leadFinder?.name ?? "?", color: store.color(for: sign.leadFinder?.handle), size: 38, photo: store.photo(for: sign.leadFinder?.handle))
      VStack(alignment: .leading, spacing: 2) {
        Text(sign.finderNames).face(.nameLarge).foregroundStyle(Color.ink)
        Text("\(sign.foundLong)\(String.dot)\(sign.place.label)")
          .face(.meta)
          .foregroundStyle(Color.ink3)
      }
      Spacer(minLength: 0)
    }
    .contentShape(Rectangle())
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
      } else {
        if let way = sign.firstWay {
          MathLine(text: way.text, tex: way.tex, size: 19, light: 0x1F3A2E, dark: 0xCDE8DA, fallback: .bodyBold, leading: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.wayGround, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .redacted(reason: failed == nil ? .placeholder : [])
        }
        if let failed {
          // The page came from a feed; only the rest of its ways are missing.
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Couldn’t load the other ways. \(failed)")
              .face(.meta)
              .foregroundStyle(Color.ink2)
              .frame(maxWidth: .infinity, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
            Button("Try again") { Task { await load() } }
              .face(.name)
              .foregroundStyle(Color.greenInk)
          }
          .padding(.top, 2)
        }
      }
    }
  }

  /// The boards' pair under the ways: "Find another way", and the
  /// numbers on the sign, shown on a tap.
  @ViewBuilder private func wayAndNumbers(_ sign: Sign) -> some View {
    let numbers = sign.numbers ?? []
    let canFind = sign.visibility == .shown && findWay != nil && !numbers.isEmpty
    if canFind || !numbers.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          if canFind, let findWay {
            Button { findWay.open(sign) } label: {
              Label(sign.wayCount == 0 ? "Find a way" : "Find another way", systemImage: "pencil")
                .face(.action)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Color.signGreen, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(CardPress())
          }
          if !numbers.isEmpty {
            Button {
              withAnimation(.snappy) { showNumbers.toggle() }
            } label: {
              HStack(spacing: 6) {
                Text(canFind ? "The numbers" : "The numbers on the sign").face(.action)
                if !canFind { Spacer() }
                Image(systemName: "chevron.down")
                  .font(.system(size: 13, weight: .bold))
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
            .accessibilityLabel("The numbers on the sign")
            .accessibilityValue(showNumbers ? "Shown" : "Hidden")
          }
        }
        .fixedSize(horizontal: false, vertical: true)

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
