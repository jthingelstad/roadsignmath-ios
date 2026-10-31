import Posting
import RoadSignMathAPI
import SwiftUI

/// Home's word about your posts in the outbox: one waiting for a
/// connection, one posted while you were elsewhere, one held, or one the
/// server said no to. Nothing when the outbox is empty.
struct OutboxNotes: View {
  @Environment(Outbox.self) private var outbox
  @Environment(Store.self) private var store

  var body: some View {
    let items = outbox.unseen
    if !items.isEmpty {
      VStack(spacing: 8) {
        ForEach(items) { item in note(item) }
      }
      .padding(.horizontal, 16)
      .padding(.top, 6)
      .animation(.snappy, value: items)
    }
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
    case .posted: "It’s on the map."
    case .held(_, let note): [note, "Only you can see it until then."].compactMap { $0 }.joined(separator: " ")
    case .refused(let message): message
    }
  }

  @ViewBuilder private func actions(_ item: OutboxItem) -> some View {
    switch item.state {
    case .posted(let sign):
      link("See it") {
        outbox.acknowledge(item.id)
        store.homePath.append(sign.slug)
      }
    case .refused:
      HStack(spacing: 16) {
        link("Try again") { outbox.retry(item.id) }
        link("Delete", role: .destructive) { outbox.remove(item.id) }
      }
    case .waiting(let problem) where problem != nil && outbox.sending != item.id:
      link("Try now") { outbox.retry(item.id) }
    default:
      EmptyView()
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
