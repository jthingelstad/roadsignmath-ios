import SwiftUI

extension View {
  /// "Sign in to post", for Check and Solve: the question, then sign-in
  /// over the screen (upright, as everywhere), then on to posting once
  /// signed in. `waiting` says what waits on the screen meanwhile.
  func signInToPost(_ asking: Binding<Bool>, waiting: String, then post: @escaping () -> Void) -> some View {
    modifier(SignInToPost(asking: asking, waiting: waiting, post: post))
  }
}

private struct SignInToPost: ViewModifier {
  @Environment(Account.self) private var account
  @Binding var asking: Bool
  let waiting: String
  let post: () -> Void
  @State private var signingIn = false
  /// The turns allowed before sign-in, put back after: Capture's own, or
  /// upright for "Find another way".
  @State private var turnsBefore: UIInterfaceOrientationMask?

  func body(content: Content) -> some View {
    content
      .alert("Sign in to post", isPresented: $asking) {
        Button("Sign in") {
          if account.prepareSignIn() { signingIn = true }
        }
        Button("Not now", role: .cancel) {}
      } message: {
        Text(waiting)
      }
      .fullScreenCover(isPresented: $signingIn) {
        // "Not now" on the email step comes back here; a finished sign-in
        // ends on its own (the welcome moment resets the step), seen below.
        SignInView { leave() }
      }
      .onChange(of: account.step) { _, step in
        if signingIn, step == .email, account.signedIn { leave() }
      }
      .onChange(of: signingIn) { _, now in
        if now {
          turnsBefore = Orientation.allowed
          Orientation.allow(.portrait)
        } else {
          Orientation.allow(turnsBefore ?? .portrait)
          turnsBefore = nil
        }
      }
  }

  /// Closes sign-in and, once signed in, goes on to posting.
  private func leave() {
    account.finishSignIn()
    signingIn = false
    if account.signedIn { post() }
  }
}
