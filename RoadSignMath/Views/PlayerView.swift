import RoadSignMathAPI
import SwiftUI

/// Another player's page, as the boards' profile draws it: who they are,
/// their signs, states and first year, the badges they've earned (never a
/// count, and nothing about the ones they haven't, as on the website),
/// then their signs as Home's timeline or a grid of photos.
struct PlayerView: View {
  let handle: String

  @Environment(Store.self) private var store
  @Environment(\.opener) private var opener
  @State private var player: Player?
  @State private var failed: String?
  @State private var look = ProfileSigns.Look.timeline
  @State private var badge: EarnedBadge?
  @Namespace private var zoom

  var body: some View {
    Group {
      if let player {
        page(player)
      } else if let failed {
        Notice(symbol: "person.crop.circle.badge.exclamationmark", title: "Can’t open this player", message: failed,
               action: ("Try again", { Task { await load() } }))
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(Color.ground)
    .navigationTitle(player?.name ?? "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(Color.ground, for: .navigationBar)
    .toolbar {
      if let player {
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: player.url, subject: Text(player.name)) {
            Image(systemName: "square.and.arrow.up")
          }
          .accessibilityLabel("Share \(player.name)’s page")
        }
      }
    }
    .sheet(item: $badge) { badge in
      BadgeSheet(slot: BadgeSlot(badge)) { id in
        self.badge = nil
        opener?.sign(id)
      }
    }
    .task { if player == nil { await load() } }
    .refreshable { await load() }
    .sensoryFeedback(.selection, trigger: look)
  }

  private func load() async {
    do {
      player = try await store.client.player(handle)
      failed = nil
      #if DEBUG
        if Script.value("RSMLook") == "photos" { look = .photos }
      #endif
    } catch {
      if !Store.cancelled(error) { failed = Store.say(error) }
    }
  }

  private func page(_ player: Player) -> some View {
    ScrollView {
      VStack(spacing: 20) {
        ProfileHeader(name: player.name, avatarColor: player.avatarColor, avatarUrl: player.avatarUrl, page: player.url, linked: true,
                      pageWords: "\(player.name)’s page", bio: player.bio,
                      signCount: player.signCount, states: player.states, firstYear: player.firstYear)
        if let badges = player.badges, !badges.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            Text("Badges")
              .face(.section)
              .foregroundStyle(Color.ink)
              .accessibilityAddTraits(.isHeader)
              .padding(.horizontal, 16)
              .frame(maxWidth: .infinity, alignment: .leading)
            BadgeRow(badges: Badges.newest(badges)) { badge = $0 }
          }
        }
        let signs = ProfileSigns.newestFirst(player.signs ?? [])
        if !signs.isEmpty {
          ProfileSigns(signs: signs, look: $look, zoom: zoom, whose: "\(player.name)’s") { opener?.sign($0.id) }
        }
      }
      .padding(.top, 8)
      .padding(.bottom, 32)
    }
  }
}
