import SignCapture
import SwiftUI

/// Drafts: the signs saved for later, newest first. A tap picks one up
/// where it was left; a swipe lets it go. They stay on this phone.
struct DraftsView: View {
  @Environment(CaptureFlow.self) private var flow
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(flow.drafts.all) { draft in
            Button {
              dismiss()
              flow.resume(draft)
            } label: {
              DraftRow(draft: draft, thumbnail: flow.drafts.thumbnail(of: draft.id))
            }
            .listRowBackground(Color.card)
          }
          .onDelete { offsets in
            for draft in offsets.map({ flow.drafts.all[$0] }) { flow.drafts.remove(draft.id) }
          }
        } footer: {
          Text("Drafts stay on this iPhone. Posting one takes it off the list.")
            .face(.meta)
            .foregroundStyle(Color.ink3)
        }
      }
      .scrollContentBackground(.hidden)
      .background(Color.ground)
      .overlay {
        if flow.drafts.all.isEmpty {
          ContentUnavailableView(
            "No drafts", systemImage: "tray",
            description: Text("Save a sign for later from the camera, and solve it when you like."))
        }
      }
      .navigationTitle("Drafts")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

private struct DraftRow: View {
  let draft: Draft
  let thumbnail: UIImage?

  var body: some View {
    HStack(spacing: 12) {
      Group {
        if let thumbnail {
          Image(uiImage: thumbnail).resizable().scaledToFill()
        } else {
          Color.photoGround
        }
      }
      .frame(width: 64, height: 64)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(draft.numbersText)
          .face(.name)
          .foregroundStyle(Color.ink)
          .lineLimit(1)
        Text(state)
          .face(.metaBold)
          .foregroundStyle(draft.solved ? Color.greenInk : Color.ink2)
        Text("Saved \(draft.savedAt.formatted(.relative(presentation: .named)))")
          .face(.meta)
          .foregroundStyle(Color.ink3)
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.ink3)
        .accessibilityHidden(true)
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityHint("Picks it up where you left it.")
  }

  private var state: String {
    if draft.solved { return "Solved, ready to post" }
    if draft.way != nil { return "Math begun" }
    if draft.numbers == nil { return "Numbers not read yet" }
    return "Numbers checked"
  }
}

/// The toolbar's "Save for later" on Check and Solve: the shot, its
/// numbers and the math so far go to Drafts, and the camera is back.
struct SaveForLater: ViewModifier {
  @Environment(CaptureFlow.self) private var flow
  @Environment(Account.self) private var account
  @State private var saves = 0

  func body(content: Content) -> some View {
    content
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            if flow.saveDraft() {
              saves += 1
              account.notice = "Saved to Drafts. Solve it whenever you like."
            } else {
              account.notice = "Your phone couldn’t keep this draft. Free up some space, then try again."
            }
          } label: {
            Label("Save for later", systemImage: "tray.and.arrow.down")
          }
          .accessibilityHint("Keeps this sign in Drafts to finish another time.")
        }
      }
      .sensoryFeedback(.success, trigger: saves)
  }
}

extension View {
  func savesForLater() -> some View { modifier(SaveForLater()) }
}
