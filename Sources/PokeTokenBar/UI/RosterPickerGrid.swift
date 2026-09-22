import SwiftUI

/// Multi-select roster grid — a fixed team grid of picked mons (drag-reorderable, up to `maxCount`)
/// above a scrollable pool of the rest, tap-to-toggle. Pulled out of `BattleView`'s original
/// roster-pick screen once trading needed the identical "multi-select up to N, training slot
/// included" shape (trading-overhaul.md: "same component, different call site") — same visuals,
/// same drag/toggle rules, different caller and label text.
struct RosterPickerGrid: View {
    let companion: CompanionStore
    let eligible: [MonState]
    let maxCount: Int
    @Binding var selectedIDs: [MonState.ID]
    let teamLabel: String
    let poolLabel: String

    private var byID: [MonState.ID: MonState] {
        Dictionary(uniqueKeysWithValues: eligible.map { ($0.id, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader(teamLabel)
                Spacer()
                Text("\(selectedIDs.count)/\(maxCount)")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
            teamGrid
            sectionHeader(poolLabel)
            // Flexible, not a fixed height — fills whatever space is left below the fixed-size team
            // grid/headers, matching battles.md's original roster picker (unlike TradeView's old
            // single-mon offer list, which used a fixed height — no longer applicable once this is
            // a grid, not a scrollable row list).
            ScrollView { poolGrid }
                .frame(maxHeight: .infinity)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }

    /// Fixed 3-column grid (not "as many columns as fit") — a team is always up to `maxCount`, so a
    /// stable grid reads as "your team" rather than a list that reflows as you add/remove picks.
    /// Order follows pick order (`selectedIDs`), not pool order — this is exactly the order a
    /// caller's own submit maps it in. Filled tiles are also drag-reorderable — dropping one onto
    /// another tile, or an empty dashed slot, moves it there rather than requiring
    /// remove-then-re-add-in-order.
    private var teamGrid: some View {
        let selected = selectedIDs.compactMap { byID[$0] }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(0..<maxCount, id: \.self) { slot in
                if slot < selected.count {
                    tile(selected[slot], selected: true, size: 38)
                        .draggable(selected[slot].id)
                        .dropDestination(for: String.self) { items, _ in moveDropped(items, toSlot: slot) }
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .frame(height: 54)
                        .dropDestination(for: String.self) { items, _ in moveDropped(items, toSlot: slot) }
                }
            }
        }
    }

    /// The rest of the pool to pick from — mons already on the team are hidden here (shown up in
    /// `teamGrid` instead). Draggable up into a team slot — `moveDropped` treats a not-yet-selected
    /// id as a pick rather than a move.
    private var poolGrid: some View {
        let unselected = eligible.filter { !selectedIDs.contains($0.id) }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
            ForEach(unselected) { mon in
                tile(mon, selected: false, size: 30)
                    .draggable(mon.id)
            }
        }
    }

    private func tile(_ mon: MonState, selected: Bool, size: CGFloat) -> some View {
        Button { toggle(mon.id) } label: {
            VStack(spacing: 2) {
                SpriteView(speciesID: mon.currentID, size: size, shiny: mon.isShiny)
                Text(companion.l.pcLevel(mon.level)).font(.system(size: 8, weight: .semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(selected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ id: MonState.ID) {
        if let idx = selectedIDs.firstIndex(of: id) {
            selectedIDs.remove(at: idx)
        } else if selectedIDs.count < maxCount {
            selectedIDs.append(id)
        }
    }

    /// A drop landing in the team grid at `slot` — either a reorder (the dragged id is already on
    /// the team, so it's removed from its old spot first) or a pick (dragged up from the pool, not
    /// yet on the team, so it's just inserted — same size cap `toggle` already enforces on tap).
    /// `slot` may be past the current selection's end (an empty dashed slot), so it's clamped to
    /// append in that case.
    private func moveDropped(_ items: [String], toSlot slot: Int) -> Bool {
        guard let draggedID = items.first else { return false }
        if let from = selectedIDs.firstIndex(of: draggedID) {
            selectedIDs.remove(at: from)
        } else if selectedIDs.count >= maxCount {
            return false
        }
        selectedIDs.insert(draggedID, at: min(slot, selectedIDs.count))
        return true
    }
}
