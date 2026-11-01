import RoadSignMathAPI
import SwiftUI

/// Who posted a sign, for "Block Sam".
struct Poster: Hashable {
  var handle: String
  var name: String

  /// The sign's poster, named as the sign names them; nil for a sign
  /// nobody playing posted (the seeded ones).
  init?(of sign: Sign, players: [String: Player]) {
    guard let handle = sign.postedBy, !handle.isEmpty else { return nil }
    self.handle = handle
    let name = sign.finders.first { $0.handle == handle }?.name ?? players[handle]?.name ?? ""
    self.name = name.isEmpty ? handle : name
  }
}

/// Reporting a sign: one reason, inappropriate, with a note if you like.
/// The moderator looks again and says what it decided; then you can block
/// whoever posted it too.
struct ReportSheet: View {
  let sign: Sign
  let poster: Poster?
  /// The moderator's answer, as it arrives.
  let reported: (ReportOutcome) -> Void
  /// The poster blocked from here.
  let blocked: () -> Void

  @Environment(Account.self) private var account
  @Environment(Store.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var note = ""
  @State private var sending = false
  @State private var outcome: ReportOutcome?
  @State private var problem: String?
  @State private var blocking = false
  @State private var didBlock = false
  @FocusState private var typing: Bool

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if let outcome { answer(outcome) } else { form }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(Color.ground)
      .navigationTitle("Report this sign")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if outcome == nil {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(sending) }
        } else {
          ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.face(.action) }
        }
      }
    }
    .tint(.greenInk)
    .interactiveDismissDisabled(sending || blocking)
    .sensoryFeedback(.success, trigger: outcome)
    #if DEBUG
      // `-RSMReportNote <words>` writes the note; `-RSMReportSend YES` sends
      // it (only ever against `npm run dev`).
      .task {
        if let words = Script.text("RSMReportNote") { note = words }
        if Script.flag("RSMReportSend") { send() }
      }
    #endif
  }

  @ViewBuilder private var form: some View {
    Text("Is this sign inappropriate? The moderator takes another look, and if it agrees, the sign comes down for everyone.")
      .face(.body)
      .foregroundStyle(Color.ink2)
      .fixedSize(horizontal: false, vertical: true)
    VStack(alignment: .leading, spacing: 6) {
      Text("Anything to add?").face(.label).foregroundStyle(Color.ink)
      TextField("Optional", text: $note, axis: .vertical)
        .face(.field)
        .lineLimit(3...6)
        .focused($typing)
        .padding(12)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(typing ? Color.greenInk : Color.ruleStrong, lineWidth: typing ? 2 : 1.5)
        }
        .onChange(of: note) { _, now in
          if now.count > Account.reportNoteMax { note = String(now.prefix(Account.reportNoteMax)) }
        }
    }
    if let problem { ProblemLine(text: problem) }
    Button(action: send) {
      HStack(spacing: 8) {
        if sending { ProgressView().tint(.white) }
        Text(sending ? "The moderator is looking…" : "Report as inappropriate")
      }
      .face(.button)
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, minHeight: 50)
      .background(Color.warn, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(CardPress())
    .disabled(sending)
    .padding(.top, 4)
  }

  @ViewBuilder private func answer(_ outcome: ReportOutcome) -> some View {
    let down = outcome.outcome == .hidden
    Image(systemName: down ? "checkmark.circle.fill" : "eye.circle.fill")
      .font(.system(size: 44, weight: .semibold))
      .foregroundStyle(down ? Color.greenInk : Color.ink3)
      .accessibilityHidden(true)
    Text(down ? "It’s down" : "It stays up")
      .face(.title)
      .foregroundStyle(Color.ink)
      .accessibilityAddTraits(.isHeader)
    Text(down ? "Thanks for telling us. It’s off the feed, the map and the website." : "The moderator looked again and kept it. Thanks for telling us.")
      .face(.body)
      .foregroundStyle(Color.ink2)
      .fixedSize(horizontal: false, vertical: true)
    if !outcome.note.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        Text("The moderator’s note").face(.metaBold).foregroundStyle(Color.ink3)
        Text(outcome.note.replacingOccurrences(of: "'", with: "’"))
          .face(.body)
          .foregroundStyle(Color.ink)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.rule) }
      .accessibilityElement(children: .combine)
    }
    if let poster {
      if didBlock {
        Label("\(poster.name) is blocked. Unblock them in Settings whenever you like.", systemImage: "hand.raised.fill")
          .face(.metaBold)
          .foregroundStyle(Color.ink2)
          .padding(.top, 6)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Button(action: block) {
            HStack(spacing: 8) {
              if blocking { ProgressView() } else { Image(systemName: "hand.raised") }
              Text("Block \(poster.name) too")
            }
            .face(.action)
            .foregroundStyle(Color.warn)
            .frame(maxWidth: .infinity, minHeight: 46)
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.ruleStrong, lineWidth: 1.5) }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(blocking)
          Text(BlockWords.what).face(.meta).foregroundStyle(Color.ink3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
      }
    }
    if let problem { ProblemLine(text: problem) }
  }

  private func send() {
    guard !sending else { return }
    sending = true
    problem = nil
    typing = false
    Task {
      do {
        let outcome = try await account.report(sign.id, note: note)
        withAnimation(.smooth) { self.outcome = outcome }
        reported(outcome)
      } catch {
        problem = Account.say(error)
      }
      sending = false
    }
  }

  private func block() {
    guard let poster, !blocking else { return }
    blocking = true
    problem = nil
    Task {
      do {
        try await account.block(poster.handle)
        withAnimation(.smooth) { didBlock = true }
        blocked()
      } catch {
        problem = Account.say(error)
      }
      blocking = false
    }
  }
}

/// What blocking does, said the same everywhere.
enum BlockWords {
  static let what = "You won’t see their signs or the ways they find. They aren’t told."
}

/// Settings' list of the players you blocked, each with Unblock.
struct BlockedPlayersView: View {
  @Environment(Account.self) private var account
  @Environment(Store.self) private var store
  @State private var players: [BlockedPlayer]?
  @State private var problem: String?
  @State private var unblocking: String?

  var body: some View {
    List {
      if let players {
        if players.isEmpty {
          Section {
            Text("Nobody. To block a player, open one of their signs and choose Block from its ⋯ menu.")
              .face(.body)
              .foregroundStyle(Color.ink2)
              .fixedSize(horizontal: false, vertical: true)
          }
        } else {
          Section {
            ForEach(players) { player in row(player) }
          } footer: {
            Text("Unblocked, their signs and ways come back. They aren’t told either way.").face(.meta)
          }
        }
        if let problem { Section { ProblemLine(text: problem) } }
      } else if let problem {
        Section {
          ProblemLine(text: problem)
          Button("Try again") { Task { await load() } }.face(.bodyBold)
        }
      } else {
        HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
      }
    }
    .scrollContentBackground(.hidden)
    .background(Color.ground)
    .navigationTitle("Blocked players")
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .refreshable { await load() }
  }

  private func row(_ player: BlockedPlayer) -> some View {
    let name = player.name.isEmpty ? player.handle : player.name
    return HStack(spacing: 12) {
      Avatar(name: name, color: store.color(for: player.handle), size: 34, photo: store.photo(for: player.handle))
        .accessibilityHidden(true)
      Text(name).face(.bodyBold).foregroundStyle(Color.ink).lineLimit(1)
      Spacer(minLength: 8)
      if unblocking == player.handle {
        ProgressView()
      } else {
        Button("Unblock") { unblock(player) }
          .face(.action)
          .foregroundStyle(Color.greenInk)
          .buttonStyle(.borderless)
          .disabled(unblocking != nil)
          .accessibilityLabel("Unblock \(name)")
      }
    }
    .frame(minHeight: 40)
  }

  private func load() async {
    do {
      players = try await account.blockedPlayers()
      problem = nil
    } catch {
      if !Store.cancelled(error) { problem = Account.say(error) }
    }
  }

  private func unblock(_ player: BlockedPlayer) {
    unblocking = player.handle
    problem = nil
    Task {
      do {
        try await account.unblock(player.handle)
        withAnimation { players?.removeAll { $0.handle == player.handle } }
        store.unblocked()
      } catch {
        problem = Account.say(error)
      }
      unblocking = nil
    }
  }
}
