import Foundation

// Settings' Help: feedback to the person who runs Road Sign Math, and your
// bio (API 1.10.0).

extension APIClient {
  /// The longest feedback message.
  public static let feedbackMax = 2000
  /// The longest bio.
  public static let bioMax = 160

  /// Sends feedback, which the server emails to the person who runs Road
  /// Sign Math. With `replyOK`, your email goes along as its Reply-To so
  /// they can write back; otherwise it never leaves the server. `app` is
  /// the version and phone, for a problem. Answers 202; a 503 means the
  /// mail didn't go.
  public func sendFeedback(_ message: String, replyOK: Bool, app: String?, token: String) async throws {
    var request = request("POST", ["feedback"], token: token)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let text = String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(APIClient.feedbackMax))
    request.httpBody = try JSONEncoder().encode(FeedbackPost(message: text, replyOk: replyOK, app: app.map { String($0.prefix(120)) }))
    let _: FeedbackSent = try await answer(to: request)
  }

  /// Sets your bio, the line on your page; empty takes it off.
  public func updateMe(token: String, bio: String) async throws -> Me {
    let text = String(bio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(APIClient.bioMax))
    return try await answer(to: request("PATCH", ["me"], body: ["bio": text], token: token))
  }
}

private struct FeedbackPost: Encodable {
  var message: String
  var replyOk: Bool
  var app: String?

  enum CodingKeys: String, CodingKey {
    case message
    case replyOk = "reply_ok"
    case app
  }
}

private struct FeedbackSent: Decodable { var sent: Bool }
