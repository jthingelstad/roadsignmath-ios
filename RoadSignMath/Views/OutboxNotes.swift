import Posting
import RoadSignMathAPI
import SwiftUI

/// Home's word about your posts in the outbox: one waiting for a
/// connection, one posted while you were elsewhere (with any badge it
/// earned), one held, or one the server said no to: with its draft kept,
/// "Fix the post" opens Post it again as it was, with the server's words,
/// and Delete asks first. Nothing when the outbox is empty, unless the
/// phone couldn't write the list of posts, which it says.
struct OutboxNotes: View {
  @Environment(Outbox.self) private var outbox
  @Environment(Store.self) private var store
  @Environment(CaptureFlow.self) private var flow
  /// The refused post Delete is asking about.
  @State private var deleting: OutboxItem?

  var body: some View {
    let items = outbox.unseen
    if !items.isEmpty || outbox.unsaved {
      VStack(spacing: 8) {
        if outbox.unsaved {
          ProblemLine(text: "Your phone couldn’t save your posts’ progress. Free up some space so they aren’t lost if the app closes.")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        ForEach(items) { item in note(item) }
      }
      .padding(.horizontal, 16)
      .padding(.top, 6)
      .animation(.snappy, value: items)
      .confirmationDialog(
        "Delete this post?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
        titleVisibility: .visible, presenting: deleting
      ) { item in
        Button("Delete", role: .destructive) { delete(item) }
        Button("Cancel", role: .cancel) {}
      } message: { _ in
        Text("Its photo, numbers and math go from this phone. It hasn’t posted, so nothing changes on the map.")
      }
      #if DEBUG
        .task {
          if Script.value("RSMRefused") == "delete", let first = items.first { deleting = first }
        }
      #endif
    }
  }

  /// Gone from the outbox, and the draft kept for it with it.
  private func delete(_ item: OutboxItem) {
    if let draft = flow.drafts.draft(for: item) { flow.drafts.remove(draft.id) }
    outbox.remove(item.id)
  }

  private func note(_ item: OutboxItem) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Group {
        if let picture = outbox.picture(item.id) {
          Image(uiImage: picture).resizable().aspectRatio(contentMode: .fill)
        } else {
          Image(systemName: "signpost.right.fill").font(.system(size: 20)).foregroundStyle(Color.greenInk)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.wayGround)
        }
      }
      .frame(width: 52, height: 52)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(headline(item)).face(.name).foregroundStyle(Color.ink)
        if let detail = detail(item) {
          Text(detail).face(.meta).foregroundStyle(Color.ink2).fixedSize(horizontal: false, vertical: true)
        }
        actions(item)
      }
      .accessibilityElement(children: .contain)
      Spacer(minLength: 0)
      if item.posted != nil {
        Button {
          outbox.acknowledge(item.id)
        } label: {
          Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.ink3)
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
      } else if outbox.sending == item.id {
        ProgressView().frame(width: 44, height: 44)
      }
    }
    .padding(10)
    .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(edge(item), lineWidth: 1.5)
    }
  }

  private func headline(_ item: OutboxItem) -> String {
    let title = "\u{201C}\(item.post.title)\u{201D}"
    switch item.state {
    case .waiting: return outbox.sending == item.id ? "Posting \(title)…" : "\(title) is waiting to post"
    case .needsSignIn: return "\(title) is waiting for you to sign in"
    case .posted: return "\(title) is posted"
    case .held: return "\(title) is held for a look"
    case .refused: return "\(title) didn’t post"
    }
  }

  private func detail(_ item: OutboxItem) -> String? {
    switch item.state {
    case .waiting(let problem): problem
    case .needsSignIn: "It goes once you’re signed in."
    case .posted(let sign):
      // What the post earned, said here when it went while you were away.
      (sign.unlocked ?? []).isEmpty ? "It’s on the map." : "It’s on the map. " + NewBadgesCard.words(sign.unlocked ?? []) + "."
    case .held(_, let note): [note, "Only you can see it until then."].compactMap { $0 }.joined(separator: " ")
    case .refused(let message): message
    }
  }

  @ViewBuilder private func actions(_ item: OutboxItem) -> some View {
    let choices = item.choices(sending: outbox.sending == item.id, canFix: flow.drafts.draft(for: item) != nil)
    if !choices.isEmpty {
      // Three fit across a phone; at large text sizes they wrap.
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 16) { buttons(item, choices) }
        VStack(alignment: .leading, spacing: 0) { buttons(item, choices) }
      }
    }
  }

  @ViewBuilder private func buttons(_ item: OutboxItem, _ choices: [OutboxChoice]) -> some View {
    ForEach(choices, id: \.self) { choice in
      switch choice {
      case .seeIt:
        link(choice.label) {
          outbox.acknowledge(item.id)
          if let sign = item.posted { store.homePath.append(sign.slug) }
        }
      case .fixThePost:
        link(choice.label) { flow.fix(item) }
      case .tryAgain, .tryNow:
        link(choice.label) { outbox.retry(item.id) }
      case .delete:
        link(choice.label, role: .destructive) { deleting = item }
      }
    }
  }

  private func link(_ label: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
    Button(label, role: role, action: action)
      .face(.metaBold)
      .foregroundStyle(role == .destructive ? Color.warn : Color.greenInk)
      .frame(minHeight: 32)
      .buttonStyle(.plain)
  }

  private func edge(_ item: OutboxItem) -> Color {
    switch item.state {
    case .posted: .signGreen
    case .refused: .warn
    default: .signYellow
    }
  }
}
