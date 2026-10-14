import SwiftUI

/// Badge color per competitive tier — the same gold → red → purple → blue → green → grey ladder the
/// Rarity Dex web page uses, so the two read alike.
func tierColor(_ tier: CompetitiveTier) -> Color {
    switch tier {
    case .s: return .orange
    case .a: return .red
    case .b: return .purple
    case .c: return .blue
    case .d: return .green
    case .e, .f: return .gray
    }
}

/// Letter-grade capsule (S–F): colored text on a light tint of the same color, like the "Raising"
/// capsule in the catch log, so it stays legible in both themes.
struct TierBadge: View {
    let tier: CompetitiveTier
    var size: CGFloat = 11

    var body: some View {
        Text(tier.rawValue)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .foregroundStyle(tierColor(tier))
            .frame(minWidth: size * 1.6)
            .padding(.vertical, 1)
            .background(tierColor(tier).opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// What a move does: power / accuracy / PP / priority / damage class, then its in-game description.
/// Shared by the TM detail screen and the dex's move detail.
///
/// `move` may be a TM-catalog summary without descriptions (`descriptions == nil`); the full detail
/// is then fetched once so the text still appears.
struct MoveFactsView: View {
    let store: CompanionStore
    let move: Move
    @State private var full: Move?

    private var shown: Move { full ?? move }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                cell(l.movePowerLabel, shown.power.map(String.init) ?? l.moveNoPower)
                cell(l.moveAccuracyLabel, shown.accuracy.map { "\($0)%" } ?? l.moveNoPower)
                cell(l.movePPLabel, "\(shown.pp)")
                if let priority = shown.priority, priority != 0 {
                    cell(l.movePriorityLabel, priority > 0 ? "+\(priority)" : "\(priority)")
                }
                cell("", l.moveDamageClassName(shown.damageClass))
                Spacer(minLength: 0)
            }
            if let text = shown.localizedDescription(store.language) {
                Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            } else if shown.descriptions != nil {
                Text(l.moveNoDescription).font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("···").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .task(id: move.id) {
            guard move.descriptions == nil else { return }
            full = await store.moveDetail(id: move.id)
        }
    }

    private func cell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if !label.isEmpty { Text(label).font(.caption2).foregroundStyle(.secondary) }
            Text(value).font(.caption.weight(.semibold)).monospacedDigit()
        }
    }
}

/// A single move, opened from a dex move list or a suggested build. Swaps in place of the screen
/// that opened it (`onClose` returns), same as every other drill-down in the popover.
struct MoveDetailView: View {
    let store: CompanionStore
    let moveID: Int
    var onClose: () -> Void
    @State private var move: Move?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: onClose) { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).accessibilityLabel(store.l.back)
                Text(move?.localizedName(store.language) ?? "···").font(.callout.weight(.semibold))
                Spacer()
            }
            if let move {
                Text(store.l.typeName(move.type).uppercased()).font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(typeColor(move.type)).foregroundStyle(.white).clipShape(Capsule())
                MoveFactsView(store: store, move: move)
            }
            Spacer(minLength: 0)
        }
        .task(id: moveID) { move = await store.moveDetail(id: moveID) }
    }
}
