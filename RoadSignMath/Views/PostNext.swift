import SignCapture
import SwiftUI

/// Where "Post it" and "Post unsolved" go until posting (step 2.5) is
/// built: what the post will carry, so it's clear nothing is lost.
struct PostNext: View {
  @Environment(CaptureFlow.self) private var flow

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        ShotStrip()
        if let way = flow.way {
          SignPlate(text: way, tex: nil, size: 24, large: true)
        }
        VStack(alignment: .leading, spacing: 10) {
          Text("The numbers").face(.section).foregroundStyle(Color.ink)
          NumberTiles(numbers: flow.numbers.kept)
        }
        if let shot = flow.shot {
          VStack(alignment: .leading, spacing: 8) {
            Fact(symbol: "calendar", text: found(shot))
            Fact(symbol: shot.file.facts.hasPlace ? "mappin.and.ellipse" : "mappin.slash", text: place(shot))
          }
        }
        if flow.way == nil {
          Text("Posted unsolved, someone else can find the math.")
            .face(.body)
            .foregroundStyle(Color.ink2)
            .fixedSize(horizontal: false, vertical: true)
        }
        Coming(
          title: "Posting comes next",
          message: "Sending a sign to the feed and the map is the next part of the app being built. Nothing has been posted.")
      }
      .padding(16)
    }
    .background(Color.ground)
    .navigationTitle(flow.way == nil ? "Post unsolved" : "Post it")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(Color.ground, for: .navigationBar)
  }

  private func found(_ shot: CaptureFlow.Shot) -> String {
    guard let day = shot.foundOn,
      let date = try? Date(day + "T12:00:00Z", strategy: .iso8601)
    else { return "The photo doesn’t say when it was taken" }
    let shown = date.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: .gmt))
    return shot.source == .camera ? "Found today, \(shown)" : "Found \(shown), from the photo"
  }

  private func place(_ shot: CaptureFlow.Shot) -> String {
    if shot.file.facts.hasPlace { return "The place comes from the photo" }
    return shot.source == .camera ? "No place yet: you’ll say where when you post" : "The photo doesn’t say where it was taken"
  }
}

/// The shot, small, at the top of the steps after Check.
struct ShotStrip: View {
  @Environment(CaptureFlow.self) private var flow
  var height: CGFloat = 150

  var body: some View {
    if let shot = flow.shot {
      Image(uiImage: shot.picture)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("Your photo of the sign")
    }
  }
}

/// The kept numbers as tiles: white, a green edge, a tick.
struct NumberTiles: View {
  let numbers: [CheckedNumber]

  var body: some View {
    FlowLayout(spacing: 8) {
      ForEach(numbers) { number in
        HStack(spacing: 6) {
          Text(number.text).font(Face.number.font(size: 17))
          Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy))
        }
        .foregroundStyle(Color.greenInk)
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.signGreen, lineWidth: 1.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(number.text)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(numbers.count) numbers")
  }
}

private struct Fact: View {
  let symbol: String
  let text: String

  var body: some View {
    Label {
      Text(text).face(.body).foregroundStyle(Color.ink)
    } icon: {
      Image(systemName: symbol).foregroundStyle(Color.greenInk)
    }
  }
}

/// A plain card saying the next part is still being built.
private struct Coming: View {
  let title: String
  let message: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(title, systemImage: "hammer")
        .face(.name)
        .foregroundStyle(Color.ink)
      Text(message)
        .face(.meta)
        .foregroundStyle(Color.ink2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Color.ruleStrong, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
    }
  }
}
