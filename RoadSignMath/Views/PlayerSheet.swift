import RoadSignMathAPI
import SwiftUI

/// Another player, from a sign's byline: who they are, their earned
/// badges in a row (never a count, and nothing about the ones they
/// haven't earned, as on the website), and their page on the website.
struct PlayerSheet: View {
  let handle: String

  @Environment(Store.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var player: Player?
  @State private var failed: String?

  var body: some View {
    NavigationStack {
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
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }.face(.action)
        }
      }
    }
    .presentationDetents([.medium, .large])
    .tint(.greenInk)
    .task { await load() }
  }

  private func load() async {
    do {
      player = try await store.client.player(handle)
      failed = nil
    } catch {
      if !Store.cancelled(error) { failed = Store.say(error) }
    }
  }

  private func page(_ player: Player) -> some View {
    ScrollView {
      VStack(spacing: 18) {
        VStack(spacing: 8) {
          Avatar(name: player.name, color: Color(hex: player.avatarColor) ?? .signGreen, size: 72)
          Text(player.name)
            .face(.title)
            .foregroundStyle(Color.ink)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
          Text(PlayerSheet.line(player))
            .face(.meta)
            .foregroundStyle(Color.ink3)
            .multilineTextAlignment(.center)
          if let bio = player.bio, !bio.isEmpty {
            Text(bio).face(.body).foregroundStyle(Color.ink2).multilineTextAlignment(.center).padding(.horizontal, 16)
          }
        }
        .padding(.top, 8)
        if let badges = player.badges, !badges.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            Text("Badges")
              .face(.section)
              .foregroundStyle(Color.ink)
              .accessibilityAddTraits(.isHeader)
              .padding(.horizontal, 16)
            BadgeRow(badges: Badges.newest(badges))
          }
        }
        Link(destination: player.url) {
          Label("Their page on the website", systemImage: "safari")
            .face(.name)
            .foregroundStyle(Color.greenInk)
            .frame(minHeight: 44)
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.bottom, 24)
    }
  }

  /// "13 signs ∙ 6 states ∙ since 2021".
  static func line(_ player: Player) -> String {
    var bits = [player.signCount == 1 ? "1 sign" : "\(player.signCount) signs"]
    if !player.states.isEmpty { bits.append(player.states.count == 1 ? "1 state" : "\(player.states.count) states") }
    if let year = player.firstYear { bits.append("since \(year)") }
    return bits.joined(separator: String.dot)
  }
}
