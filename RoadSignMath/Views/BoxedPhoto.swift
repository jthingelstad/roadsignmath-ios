import SignCapture
import SignReading
import SwiftUI

/// A shot, whole, with each number boxed where it was read: a caution-yellow
/// ring and a tag with its value, as the Capture board draws them. A number
/// left out is a dashed white ring; the one being looked at gets a heavier
/// ring. A tap anywhere reports where on the photo (0...1 across and down).
struct BoxedPhoto: View {
  let picture: UIImage
  let numbers: [CheckedNumber]
  var focus: CheckedNumber.ID?
  /// The reading is still going: a band of light sweeps the photo.
  var scanning = false
  /// A spot being read again, after a tap.
  var spot: CGPoint?
  var tap: ((Double, Double) -> Void)?

  @Environment(\.accessibilityReduceMotion) private var still

  var body: some View {
    GeometryReader { geometry in
      let frame = Self.fit(picture.size, in: geometry.size)
      ZStack(alignment: .topLeading) {
        Image(uiImage: picture)
          .resizable()
          .frame(width: frame.width, height: frame.height)
          .offset(x: frame.minX, y: frame.minY)
          .accessibilityHidden(true)
        let tags = Self.tags(numbers, in: frame, focus: focus)
        ForEach(Array(numbers.enumerated()), id: \.element.id) { index, number in
          if let box = number.box {
            NumberRing(
              number: number, focused: focus == number.id, rect: Self.rect(box, in: frame),
              tag: tags[number.id], order: index)
          }
        }
        if scanning {
          ScanBand(still: still)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
        }
        if let spot {
          ProgressView()
            .tint(.white)
            .padding(8)
            .background(.black.opacity(0.6), in: Circle())
            .position(x: frame.minX + spot.x * frame.width, y: frame.minY + spot.y * frame.height)
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
      .contentShape(Rectangle())
      .gesture(
        SpatialTapGesture().onEnded { value in
          guard let tap, frame.width > 0, frame.height > 0 else { return }
          let x = (value.location.x - frame.minX) / frame.width
          let y = (value.location.y - frame.minY) / frame.height
          guard (0...1).contains(x), (0...1).contains(y) else { return }
          tap(x, y)
        }
      )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityAddTraits(.isImage)
  }

  private var label: String {
    let marked = numbers.filter { $0.box != nil }.count
    switch marked {
    case 0: return "Your photo of the sign"
    case 1: return "Your photo of the sign, with 1 number marked"
    default: return "Your photo of the sign, with \(marked) numbers marked"
    }
  }

  /// Where a picture of `size` sits when fitted, whole, into `space`.
  static func fit(_ size: CGSize, in space: CGSize) -> CGRect {
    guard size.width > 0, size.height > 0, space.width > 0, space.height > 0 else { return .zero }
    let scale = min(space.width / size.width, space.height / size.height)
    let width = size.width * scale
    let height = size.height * scale
    return CGRect(x: (space.width - width) / 2, y: (space.height - height) / 2, width: width, height: height)
  }

  /// Where each number's tag goes: above its ring, else below, else left
  /// off where it would cover another tag or number on a crowded sign (the ring stays, and the
  /// list says what it is). The focused number's tag is placed first.
  static func tags(_ numbers: [CheckedNumber], in frame: CGRect, focus: CheckedNumber.ID?) -> [CheckedNumber.ID: CGRect] {
    var placed: [CGRect] = []
    var places: [CheckedNumber.ID: CGRect] = [:]
    let rings = numbers.compactMap { number in number.box.map { (number.id, rect($0, in: frame).insetBy(dx: -3, dy: -3)) } }
    let ordered = numbers.filter { $0.id == focus } + numbers.filter { $0.id != focus }
    for number in ordered {
      guard let box = number.box else { continue }
      let ring = rect(box, in: frame).insetBy(dx: -3, dy: -3)
      let size = CGSize(width: 14 + 8 * CGFloat(number.text.count), height: 19)
      let above = CGRect(x: ring.minX, y: ring.minY - 3 - size.height, width: size.width, height: size.height)
      let below = CGRect(x: ring.minX, y: ring.maxY + 3, width: size.width, height: size.height)
      let room = above.minY >= frame.minY ? [above, below] : [below, above]
      // Clear of the tags placed so far and of every other number's ring.
      let free = room.first { spot in
        !placed.contains { $0.insetBy(dx: -1, dy: -1).intersects(spot) }
          && !rings.contains { $0.0 != number.id && $0.1.intersects(spot) }
      }
      if let free {
        placed.append(free)
        places[number.id] = free
      }
    }
    return places
  }

  /// A box on the photo, in points, at least big enough to see.
  static func rect(_ box: NormalizedBox, in frame: CGRect) -> CGRect {
    let raw = CGRect(
      x: frame.minX + box.x * frame.width, y: frame.minY + box.y * frame.height,
      width: box.width * frame.width, height: box.height * frame.height)
    return raw.insetBy(dx: min(0, (raw.width - 14) / 2), dy: min(0, (raw.height - 14) / 2))
  }
}

/// One number's ring and its tag.
private struct NumberRing: View {
  let number: CheckedNumber
  let focused: Bool
  let rect: CGRect
  /// Where its tag goes, or nil when there's no room for one.
  let tag: CGRect?
  let order: Int

  @State private var shown = false
  @Environment(\.accessibilityReduceMotion) private var still

  var body: some View {
    let ring = RoundedRectangle(cornerRadius: 5, style: .continuous)
    let on = shown || still
    ZStack(alignment: .topLeading) {
      ring
        .strokeBorder(
          number.kept ? Color.signYellow : .white.opacity(0.85),
          style: StrokeStyle(lineWidth: focused ? 3.5 : 2, dash: number.kept ? [] : [5, 4]))
        .shadow(color: .black.opacity(0.45), radius: 1)
        .background(focused ? Color.signYellow.opacity(0.18) : .clear, in: ring)
        .frame(width: rect.width + 6, height: rect.height + 6)
        .scaleEffect(on ? 1 : 0.4)
        .position(x: rect.midX, y: rect.midY)
      if let tag {
        Text(number.text)
          .font(Face.number.font(size: 13))
          .strikethrough(!number.kept)
          .foregroundStyle(number.kept ? Color(uiColor: UIColor(rgb: 0x18201C)) : .white)
          .padding(.horizontal, 6)
          .padding(.top, 2)
          .padding(.bottom, 1)
          .background(number.kept ? Color.signYellow : .black.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
          .fixedSize()
          .frame(width: tag.width, height: tag.height, alignment: .leading)
          .scaleEffect(on ? 1 : 0.4)
          .position(x: tag.midX, y: tag.midY)
      }
    }
    .opacity(on ? 1 : 0)
    .onAppear {
      withAnimation(.spring(duration: 0.35, bounce: 0.4).delay(Double(min(order, 12)) * 0.05)) { shown = true }
    }
    .animation(.snappy(duration: 0.2), value: number.kept)
    .animation(.snappy(duration: 0.2), value: focused)
  }
}

/// A band of light moving down the photo while it's read; still, a soft
/// pulse instead.
private struct ScanBand: View {
  let still: Bool
  @State private var down = false

  var body: some View {
    GeometryReader { geometry in
      if still {
        Color.white.opacity(down ? 0.12 : 0.02)
          .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { down = true }
          }
      } else {
        LinearGradient(
          colors: [.clear, Color.signYellow.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom
        )
        .frame(height: max(geometry.size.height * 0.18, 24))
        .offset(y: down ? geometry.size.height : -geometry.size.height * 0.18)
        .onAppear {
          withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) { down = true }
        }
      }
    }
    .clipped()
  }
}
