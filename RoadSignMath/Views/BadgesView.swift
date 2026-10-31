import RoadSignMathAPI
import SwiftUI

/// Your badges, on their five shelves: the earned ones in full color with
/// the day and the sign that earned them (a tap opens that sign), the
/// rest faded with how to earn them, the secret ones blank until earned.
/// A stepped badge says the step reached and the next one. Only you see
/// this page; other players see your earned ones only.
struct BadgesView: View {
  let earned: [EarnedBadge]
  /// Opens the sign that earned a badge.
  let openSign: (String) -> Void

  @Environment(Account.self) private var account
  @State private var catalog: [CatalogBadge] = []
  @State private var failed: String?
  @State private var showing: BadgeSlot?
  @Environment(\.dynamicTypeSize) private var typeSize

  private var shelves: [(shelf: BadgeShelf, slots: [BadgeSlot])] { Badges.shelves(catalog: catalog, earned: earned) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        if let failed {
          Notice(symbol: "wifi.exclamationmark", title: "The other badges didn’t load", message: failed,
                 action: ("Try again", { Task { await load() } }))
        }
        if catalog.isEmpty, earned.isEmpty, failed == nil {
          ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
        }
        ForEach(shelves, id: \.shelf) { shelf in
          VStack(alignment: .leading, spacing: 12) {
            Text(shelf.shelf.title)
              .face(.section)
              .foregroundStyle(Color.ink)
              .accessibilityAddTraits(.isHeader)
              .padding(.horizontal, 16)
            // Two to a row at the accessibility sizes, so the names don't break.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 160 : 104, maximum: typeSize.isAccessibilitySize ? 400 : 160), spacing: 10, alignment: .top)], spacing: 16) {
              ForEach(shelf.slots) { slot in cell(slot) }
            }
            .padding(.horizontal, 16)
          }
        }
      }
      .padding(.top, 12)
      .padding(.bottom, 32)
    }
    .background(Color.ground)
    .navigationTitle("Badges")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $showing) { slot in
      BadgeSheet(slot: slot) { id in
        showing = nil
        openSign(id)
      }
    }
    .task {
      account.seeBadges(earned)
      await load()
      #if DEBUG
        if let id = Script.value("RSMBadge"), let slot = shelves.lazy.flatMap(\.slots).first(where: { $0.id == id }) {
          showing = slot
        }
      #endif
    }
  }

  private func load() async {
    do {
      catalog = try await account.client.badges()
      failed = nil
    } catch {
      if catalog.isEmpty { failed = Account.say(error) }
    }
  }

  private func cell(_ slot: BadgeSlot) -> some View {
    Button {
      if let earned = slot.earned { openSign(earned.sign.id) } else { showing = slot }
    } label: {
      VStack(spacing: 6) {
        BadgeArt(slot, size: 60)
        VStack(spacing: 2) {
          Text(slot.hidden ? "Secret" : slot.earned?.name ?? slot.badge.name ?? "")
            .face(.name)
            .foregroundStyle(slot.earned == nil ? Color.ink3 : Color.ink)
          ForEach(BadgesView.lines(slot), id: \.self) { line in
            Text(line).face(.meta).foregroundStyle(Color.ink3)
          }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(CardPress())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(BadgesView.spoken(slot))
    .accessibilityHint(slot.earned == nil ? "Shows how to earn it" : "Opens the sign that earned it")
    .accessibilityAddTraits(.isButton)
    .contextMenu {
      if slot.earned != nil {
        Button("About this badge", systemImage: "info.circle") { showing = slot }
      }
    }
  }

  /// The words under a badge: the day and sign it was earned with, the
  /// step reached and the next; or how to earn it.
  static func lines(_ slot: BadgeSlot) -> [String] {
    if let earned = slot.earned {
      return [steps(slot), earned.shortDay, earned.sign.title].compactMap { $0 }
    }
    if slot.hidden { return ["Keep playing."] }
    return [slot.badge.how ?? ""].filter { !$0.isEmpty }
  }

  /// "Step 5, next 10", or "Step 10, the top" at the last one; just
  /// "Step 5" when the steps aren't known (no catalog). Nil for a badge
  /// without steps.
  static func steps(_ slot: BadgeSlot) -> String? {
    guard let step = slot.earned?.step else { return nil }
    guard slot.badge.steps != nil else { return "Step \(step)" }
    return slot.nextStep.map { "Step \(step), next \($0)" } ?? "Step \(step), the top"
  }

  static func spoken(_ slot: BadgeSlot) -> String {
    if let earned = slot.earned {
      let step = steps(slot).map { " \($0)." } ?? ""
      return earned.spoken + step
    }
    if slot.hidden { return "A secret badge, not earned yet." }
    let next = slot.nextStep.map { " First step: \($0)." } ?? ""
    return "\(slot.badge.name ?? "A badge"), not earned yet. \(slot.badge.how ?? "")\(next)"
  }
}

/// One badge, big: its sign, its name, how it's earned, and when and with
/// which sign, or the step to reach next.
struct BadgeSheet: View {
  let slot: BadgeSlot
  let openSign: (String) -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 14) {
          BadgeArt(slot, size: 120)
            .padding(.top, 12)
          Text(slot.hidden ? "A secret badge" : slot.earned?.title ?? slot.badge.name ?? "")
            .face(.title)
            .foregroundStyle(Color.ink)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
          Text(slot.hidden ? "It shows itself when you earn it. Keep playing." : slot.earned?.how ?? slot.badge.how ?? "")
            .face(.lead)
            .foregroundStyle(Color.ink2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
          if let earned = slot.earned {
            VStack(spacing: 4) {
              if let steps = BadgesView.steps(slot) {
                Text(steps).face(.bodyBold).foregroundStyle(Color.ink)
              }
              Text("Earned \(earned.longDay) with \u{201C}\(earned.sign.title)\u{201D}.")
                .face(.body)
                .foregroundStyle(Color.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            BigButton(label: "See the sign", symbol: "signpost.right.fill", busy: false, enabled: true) {
              openSign(earned.sign.id)
            }
            .padding(.top, 6)
          } else if let next = slot.nextStep {
            Text("First step: \(next).").face(.bodyBold).foregroundStyle(Color.ink)
          }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
      }
      .background(Color.ground)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }.face(.action)
        }
      }
    }
    .presentationDetents([.medium, .large])
    .tint(.greenInk)
  }
}

extension BadgeSlot {
  /// A badge's own sheet, for one the You row shows.
  init(_ earned: EarnedBadge, catalog: [CatalogBadge] = []) {
    self.init(badge: catalog.first { $0.id == earned.id } ?? CatalogBadge(earned), earned: earned)
  }
}
