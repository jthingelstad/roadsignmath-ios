import SignCapture
import SwiftUI

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
