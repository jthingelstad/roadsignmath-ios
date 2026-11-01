import RoadSignMathAPI
import SwiftUI

/// You's "On your signs": the ways other players found and the hearts they
/// gave on your signs in the last 30 days, newest first, the ones since
/// you last looked marked new. A tap opens the sign. No push and no
/// running count: the dot on your avatar says something's here.
struct OnYourSigns: View {
  let rows: [ActivityRow]
  let days: Int
  let open: (ActivityItem.SignRef) -> Void
  @State private var showingAll = false

  /// How many rows show before "Show all".
  static let first = 5

  var body: some View {
    let anyNew = rows.contains(where: \.new)
    let shown = showingAll ? rows : Array(rows.prefix(Self.first))
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center, spacing: 8) {
        Text("On your signs")
          .face(.section)
          .foregroundStyle(Color.ink)
          .accessibilityAddTraits(.isHeader)
        if anyNew {
          Text("New")
            .face(.tabOn)
            .foregroundStyle(Color.yellowInk)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.signYellow, in: Capsule())
            .accessibilityLabel("Something new")
        }
        Spacer(minLength: 8)
        if anyNew {
          Text("Since you last looked").face(.meta).foregroundStyle(Color.ink2)
            .accessibilityHidden(true)
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 14)
      .padding(.bottom, 8)
      ForEach(shown) { row in
        Divider().overlay(Color.rule)
        Button {
          open(row.sign)
        } label: {
          ActivityRowView(row: row)
        }
        .buttonStyle(CardPress())
      }
      if rows.count > shown.count {
        Divider().overlay(Color.rule)
        Button {
          withAnimation(.smooth) { showingAll = true }
        } label: {
          Text("Show all \(rows.count)")
            .face(.name)
            .foregroundStyle(Color.greenInk)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
      }
      Divider().overlay(Color.rule)
      Text("The last \(days) days. A tap opens the sign.")
        .face(.meta)
        .foregroundStyle(Color.ink2)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }
    .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.rule, lineWidth: 1) }
    .padding(.horizontal, 16)
  }
}

/// One line: who, what, which sign and when; a way's math on its plate.
private struct ActivityRowView: View {
  let row: ActivityRow
  @ScaledMetric(relativeTo: .body) private var size: CGFloat = 15

  var body: some View {
    HStack(alignment: wayMath == nil ? .center : .top, spacing: 12) {
      mark
      VStack(alignment: .leading, spacing: 8) {
        sentence
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
        if let way = wayMath {
          SignPlate(text: way.text, tex: way.tex, size: 17)
            .accessibilityHidden(true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(row.new ? Color.wayGround.opacity(0.45) : Color.clear)
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(spoken)
    .accessibilityHint("Opens the sign")
  }

  private var wayMath: ActivityItem.Way? {
    if case .way(let way) = row.kind { return way }
    return nil
  }

  /// A way: the finder's avatar, with a dot while new. Hearts: a heart,
  /// red while new.
  @ViewBuilder private var mark: some View {
    if wayMath != nil, let player = row.players.first {
      Avatar(name: player.name ?? "", color: Color(hex: player.avatarColor) ?? .signGreen, size: 38,
             photo: player.avatarThumbUrl)
        .overlay(alignment: .topTrailing) { if row.new { NewDot().offset(x: 1, y: -1) } }
    } else {
      Image(systemName: "heart.fill")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(row.new ? Color.heart : Color.greenInk)
        .frame(width: 38, height: 38)
        .background(row.new ? Color.heartSoft : Color.wayGround, in: Circle())
    }
  }

  /// "**Jamie** found another way on **I-35W at 82nd Street** ∙ 2h".
  private var sentence: Text {
    let bold = Face.bodyBold.font(size: size)
    let plain = row.new ? Color.ink : Color.ink2
    let verb = wayMath == nil ? " hearted " : " found another way on "
    return Text("\(Text(row.who).font(bold).foregroundStyle(Color.ink))\(Text(verb))\(Text(row.sign.title).font(bold).foregroundStyle(Color.ink))\(Text(String.dot + ActivityRow.when(row.at)).foregroundStyle(Color.ink2))")
      .font(Face.body.font(size: size))
      .foregroundStyle(plain)
  }

  private var spoken: String {
    let verb = wayMath == nil ? " hearted " : " found another way on "
    var words = (row.new ? "New: " : "") + row.who + verb + row.sign.title + ", "
      + row.at.formatted(.relative(presentation: .named))
    if let way = wayMath { words += ". " + MathLine.spoken(way.text) }
    return words
  }
}
