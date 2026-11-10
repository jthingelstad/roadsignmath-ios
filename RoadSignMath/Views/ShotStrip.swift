import SignCapture
import SignReading
import SwiftUI

/// The shot, small, at the top of the steps after Check. A strip as wide as
/// the screen is cropped from the photo around the sign's kept numbers, so
/// a short strip still shows every number the math can use.
struct ShotStrip: View {
  @Environment(CaptureFlow.self) private var flow
  var height: CGFloat = 150
  /// The whole photo at its own shape, for a short screen, where a strip
  /// as wide as the screen would cut through the sign.
  var whole = false
  @State private var width: CGFloat = 0

  var body: some View {
    if let shot = flow.shot {
      Group {
        if whole {
          Image(uiImage: shot.picture)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
        } else {
          let numbers = Self.numbers(flow.numbers.kept)
          Color.photoGround
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            // Never so short that a number the math can use is cut off.
            .frame(height: max(height, Self.height(for: numbers, of: shot.picture.size, width: width)))
            .overlay(alignment: .topLeading) {
              GeometryReader { geometry in
                let place = Self.crop(shot.picture.size, into: geometry.size, around: numbers)
                Image(uiImage: shot.picture)
                  .resizable()
                  .frame(width: place.width, height: place.height)
                  .offset(x: place.minX, y: place.minY)
              }
            }
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Your photo of the sign")
      .accessibilityAddTraits(.isImage)
    }
  }

  /// Where the kept numbers are on the photo (0...1 across and down), all
  /// of them in one box, or nil when none has a spot.
  static func numbers(_ numbers: [CheckedNumber]) -> CGRect? {
    let boxes = numbers.compactMap(\.box).map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
    guard let first = boxes.first else { return nil }
    return boxes.dropFirst().reduce(first) { $0.union($1) }
  }

  /// How tall a strip `width` wide must be to show `numbers` with a little
  /// room around them, at most the whole photo's height.
  static func height(for numbers: CGRect?, of size: CGSize, width: CGFloat) -> CGFloat {
    guard size.width > 0, width > 0 else { return 0 }
    let whole = width * size.height / size.width
    guard let numbers else { return whole }
    return min(whole, (numbers.height + 2 * margin) * whole)
  }

  /// Where a picture of `size` sits when it fills `space`, moved so that
  /// `focus` (0...1 across and down) is as near the middle as the picture's
  /// edges allow.
  static func crop(_ size: CGSize, into space: CGSize, around focus: CGRect?) -> CGRect {
    guard size.width > 0, size.height > 0, space.width > 0, space.height > 0 else { return .zero }
    let scale = max(space.width / size.width, space.height / size.height)
    let width = size.width * scale
    let height = size.height * scale
    let middle = focus.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: 0.5, y: 0.5)
    let x = min(0, max(space.width - width, space.width / 2 - middle.x * width))
    let y = min(0, max(space.height - height, space.height / 2 - middle.y * height))
    return CGRect(x: x, y: y, width: width, height: height)
  }

  /// Room kept around the numbers, as a share of the photo's height.
  private static let margin: CGFloat = 0.04
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
