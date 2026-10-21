import SwiftUI

/// Day Care — reached from the PC header (doc: specs/2026-10-21-day-care.md). Same in-place
/// swap as the PC's mon detail: the slot list, or the parent picker for one slot. Confirmations morph
/// the buttons inline (no .sheet/.alert — see ShopView).
struct DayCareView: View {
    let store: CompanionStore
    var onClose: () -> Void
    @State private var pickingSlot: Int?

    var body: some View {
        if let slot = pickingSlot {
            DayCarePickerView(store: store, slot: slot) { pickingSlot = nil }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button(action: onClose) { Image(systemName: "chevron.left") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(store.l.back)
                        Text(store.l.dayCareTitle).font(.callout.weight(.semibold))
                        Spacer()
                    }
                    Text(store.l.dayCareHint)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(0..<DayCare.maxSlots, id: \.self) { index in
                        DayCareSlotCard(store: store, index: index) { pickingSlot = index }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

/// ♂/♀ next to a sprite — blank (same width) for genderless or not-yet-loaded.
struct GenderMark: View {
    let gender: Gender?
    let l: L
    /// Keep a mark's width when there's none, so list rows line up. Off where the mark sits centred.
    var reservesSpace = true

    var body: some View {
        switch gender {
        case .male?:
            Text("♂").font(.system(size: 11, weight: .bold)).foregroundStyle(.blue)
                .accessibilityLabel(l.genderLabel(.male))
        case .female?:
            Text("♀").font(.system(size: 11, weight: .bold)).foregroundStyle(.pink)
                .accessibilityLabel(l.genderLabel(.female))
        case .genderless?, nil:
            // Same footprint as a mark, so rows line up whether or not a gender shows.
            if reservesSpace {
                Text("♂").font(.system(size: 11, weight: .bold)).hidden().accessibilityHidden(true)
            }
        }
    }
}

private struct DayCareSlotCard: View {
    let store: CompanionStore
    let index: Int
    var onPick: () -> Void
    @State private var confirm: Confirm?
    private enum Confirm { case cancel, hatch, discard }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(l.dayCareSlotLabel(index + 1)).font(.system(size: 12, weight: .bold))
                Spacer()
                if let slot = store.dayCareSlot(index) {
                    Text(l.rarityLabel(slot.babyRarity).uppercased()).font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(rarityColor(slot.babyRarity)).foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            if index >= store.dayCareSlotCount {
                Label(l.dayCareSecondSlotHint(TokenFormatter.compact(DayCare.secondSlotPrice)), systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let slot = store.dayCareSlot(index) {
                occupied(slot, l)
            } else {
                HStack {
                    Text(l.dayCareEmpty).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(l.dayCareDropOffPair, action: onPick)
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    @ViewBuilder
    private func occupied(_ slot: DayCareSlot, _ l: L) -> some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(slot.parentIDs, id: \.self) { id in
                if let mon = store.party.first(where: { $0.id == id }) { ParentBadge(store: store, mon: mon) }
            }
            Image(systemName: "arrow.right").font(.callout).foregroundStyle(.tertiary)
            EggBadge(store: store, speciesID: slot.traits.babySpeciesID, knownName: store.dayCareBabyName(slot))
        }
        .frame(maxWidth: .infinity)
        if slot.isReady {
            Label(l.dayCareEggReady, systemImage: "sparkles")
                .font(.caption.weight(.semibold)).foregroundStyle(.green)
            readyControls(slot, l)
        } else {
            let fraction = slot.target > 0 ? Double(slot.progress) / Double(slot.target) : 1
            HStack(spacing: 6) {
                Text(l.dayCareIncubating).font(.caption2)
                ProgressView(value: min(1, fraction)).controlSize(.small).tint(.orange)
                Text(l.dayCareProgressLabel(TokenFormatter.compact(slot.progress), TokenFormatter.compact(slot.target)))
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            if confirm == .cancel {
                confirmRow(l.dayCareCancelConfirm(TokenFormatter.compact(DayCare.fee)), action: l.dayCareCancelAction, l) {
                    store.cancelDayCare(slot: slot.slot)
                }
            } else {
                HStack {
                    Spacer()
                    Button(l.dayCareCancelAction) { confirm = .cancel }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private func readyControls(_ slot: DayCareSlot, _ l: L) -> some View {
        switch confirm {
        case .hatch?:
            confirmRow(l.dayCareHatchConfirm(store.displayName), action: l.dayCareHatchAction, l) {
                store.hatchDayCareEgg(slot: slot.slot)
            }
        case .discard?:
            confirmRow(l.dayCareDiscardConfirm, action: l.dayCareDiscardAction, l) {
                store.discardDayCareEgg(slot: slot.slot)
            }
        default:
            if !store.canHatchDayCareEgg {
                Text(l.dayCareHatchBlocked).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(l.dayCareDiscardAction) { confirm = .discard }
                    .buttonStyle(.borderless).controlSize(.small)
                Spacer()
                Button(l.dayCareHatchAction) { confirm = .hatch }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(!store.canHatchDayCareEgg)
            }
        }
    }

    private func confirmRow(_ message: String, action: String, _ l: L, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(message).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action) { confirm = nil; perform() }
                .buttonStyle(.borderedProminent).controlSize(.small)
            Button(l.cancel) { confirm = nil }
                .buttonStyle(.borderless).controlSize(.small)
        }
    }
}

/// A parent as a column: sprite, then name and gender mark.
private struct ParentBadge: View {
    let store: CompanionStore
    let mon: MonState
    @State private var gender: Gender?

    var body: some View {
        VStack(spacing: 0) {
            // Gen 5 sprites sit in a mostly empty canvas — draw large and let the frame trim the margin.
            SpriteView(speciesID: mon.currentID, size: 56, shiny: mon.isShiny).frame(width: 64, height: 48)
            HStack(spacing: 2) {
                SpeciesName(store: store, speciesID: mon.currentID).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                GenderMark(gender: gender, l: store.l, reservesSpace: false)
            }
            .frame(maxWidth: 76)
        }
        .help(store.speciesName(mon.currentID))
        .task(id: mon.id) { gender = await store.gender(of: mon) }
    }
}

/// The egg, with the species it will hatch underneath.
private struct EggBadge: View {
    let store: CompanionStore
    let speciesID: Int
    let knownName: String

    var body: some View {
        VStack(spacing: 0) {
            SpriteView(speciesID: nil, size: 36).frame(width: 64, height: 48)
            SpeciesName(store: store, speciesID: speciesID, knownName: knownName)
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                .frame(maxWidth: 76)
        }
    }
}

/// A species name that may not be in the Pokédex yet — shows what's known, then fills in from
/// PokéAPI (`catalogSpeciesName`) when that was only a "#id" placeholder.
private struct SpeciesName: View {
    let store: CompanionStore
    let speciesID: Int
    var knownName: String?
    @State private var resolved: String?

    var body: some View {
        let known = knownName ?? store.speciesName(speciesID)
        Text(resolved ?? known)
            .task(id: "\(speciesID)-\(store.language.rawValue)") {
                resolved = known.hasPrefix("#") ? await store.catalogSpeciesName(speciesID) : nil
            }
    }
}

/// Pick two benched Pokémon for one slot, attach optional items, see compatibility, pay and drop off.
///
/// Egg data for every candidate loads up front (species responses are cached), so the list can
/// show egg groups, filter by them, and mark who can pair with the first pick without a fetch per pair.
private struct DayCarePickerView: View {
    let store: CompanionStore
    let slot: Int
    var onDone: () -> Void

    @State private var selected: [String] = []
    @State private var info: [String: DayCare.Candidate] = [:]
    @State private var groupFilter: String?
    @State private var useDestinyKnot = false
    @State private var everstoneMonID: String?
    @State private var message: String?
    @State private var submitting = false

    /// Benched and not already incubating somewhere.
    private var candidates: [MonState] {
        store.party.filter { $0.id != store.trainingMon?.id && !store.isAtDayCare($0.id) }
    }
    private var pair: [MonState] { selected.compactMap { id in store.party.first { $0.id == id } } }
    private var compatibility: DayCare.Compatibility? {
        guard selected.count == 2, let a = info[selected[0]], let b = info[selected[1]] else { return nil }
        return DayCare.compatibility(a, b)
    }
    private var canSubmit: Bool {
        compatibility == .compatible && !submitting
            && store.canDropOff(slot: slot, parentIDs: selected, destinyKnot: useDestinyKnot, everstoneMonID: everstoneMonID)
    }

    /// Egg groups present in the PC, in a stable order, for the filter chips.
    private var groupsInPC: [String] {
        var seen = Set<String>()
        return candidates.compactMap { info[$0.id] }.flatMap(\.info.eggGroups)
            .filter { seen.insert($0).inserted }
            .sorted { EggGroupChip.order($0) < EggGroupChip.order($1) }
    }

    /// How a row relates to the first pick: nil = nothing picked yet (or this is the pick).
    private func relation(_ mon: MonState) -> DayCare.Compatibility? {
        guard let first = selected.first, first != mon.id, let a = info[first], let b = info[mon.id] else { return nil }
        return DayCare.compatibility(a, b)
    }

    /// Filtered, with partners that can pair with the first pick on top.
    private var rows: [MonState] {
        let filtered = candidates.filter { mon in
            guard let groupFilter else { return true }
            return info[mon.id]?.info.eggGroups.contains(groupFilter) ?? false
        }
        guard !selected.isEmpty else { return filtered }
        func rank(_ m: MonState) -> Int {
            if selected.contains(m.id) { return 0 }
            return relation(m) == .compatible ? 1 : 2
        }
        return filtered.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onDone) { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(l.back)
                Text(l.dayCarePickTitle).font(.callout.weight(.semibold))
                Spacer()
                Text(l.dayCarePickHint).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).minimumScaleFactor(0.8)
            }
            filterChips(l)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(rows) { mon in
                        PickerRow(store: store, mon: mon, candidate: info[mon.id], isSelected: selected.contains(mon.id),
                                  relation: relation(mon), sharedGroups: sharedGroups(with: mon)) { toggle(mon.id) }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)
            pairSummary(l)
            options(l)
            footer(l)
        }
        .task {
            for mon in candidates where info[mon.id] == nil {
                if let c = await store.dayCareCandidate(mon) { info[mon.id] = c }
            }
        }
    }

    /// Groups this row shares with the first pick — highlighted on its chips.
    private func sharedGroups(with mon: MonState) -> Set<String> {
        guard let first = selected.first, first != mon.id, let a = info[first] else { return [] }
        return Set(a.info.eggGroups)
    }

    private func filterChips(_ l: L) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                chip(l.eggRegionAll, active: groupFilter == nil) { groupFilter = nil }
                ForEach(groupsInPC, id: \.self) { g in
                    chip(l.eggGroupName(g), active: groupFilter == g) { groupFilter = groupFilter == g ? nil : g }
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(active ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(active ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func toggle(_ id: String) {
        message = nil
        if let i = selected.firstIndex(of: id) {
            selected.remove(at: i)
            if everstoneMonID == id { everstoneMonID = nil }
        } else {
            if selected.count == 2 {
                let dropped = selected.removeFirst()
                if everstoneMonID == dropped { everstoneMonID = nil }
            }
            selected.append(id)
        }
    }

    /// The two parents → the baby that hatches, plus the verdict. Shown once anything is picked.
    @ViewBuilder
    private func pairSummary(_ l: L) -> some View {
        if !selected.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(pair) { mon in ParentBadge(store: store, mon: mon) }
                    if pair.count == 1 {
                        Image(systemName: "plus").font(.caption2).foregroundStyle(.tertiary)
                        Text(l.dayCarePickPartner).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let baby = babyPreview {
                        Image(systemName: "arrow.right").font(.callout).foregroundStyle(.tertiary)
                        EggBadge(store: store, speciesID: baby, knownName: store.speciesName(baby))
                    }
                    Spacer(minLength: 0)
                }
                if let compatibility {
                    Label(l.dayCareCompatibility(compatibility),
                          systemImage: compatibility == .compatible ? "heart.fill" : "xmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(compatibility == .compatible ? .pink : .secondary)
                } else if pair.count == 2 {
                    Text(l.dayCareChecking).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// The species the egg will hatch — the mother's line base (Nidoran♀/Illumise may also hatch their
    /// partner species; the preview shows the line's own).
    private var babyPreview: Int? {
        guard compatibility == .compatible, let a = info[selected[0]], let b = info[selected[1]] else { return nil }
        return DayCare.babySpecies(motherBaseID: pair[DayCare.motherIndex(a, b)].baseID, roll: 0)
    }

    @ViewBuilder
    private func options(_ l: L) -> some View {
        if store.itemCount(.destinyKnot) > 0 {
            Toggle(l.dayCareDestinyKnotToggle(DayCare.destinyKnotInheritedIVCount), isOn: $useDestinyKnot)
                .toggleStyle(.checkbox).font(.caption)
        }
        if store.itemCount(.everstone) > 0, pair.count == 2 {
            HStack {
                Text(l.dayCareEverstoneLabel).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $everstoneMonID) {
                    Text(l.dayCareEverstoneNone).tag(String?.none)
                    ForEach(pair) { mon in
                        Text(mon.nature.map { "\(store.speciesName(mon.currentID)) · \($0.name(store.language))" }
                             ?? store.speciesName(mon.currentID))
                            .tag(String?.some(mon.id))
                    }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
        }
    }

    private func footer(_ l: L) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message {
                Text(message).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(l.dayCareFee(TokenFormatter.compact(DayCare.fee)))
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                Spacer()
                if store.availableTokens < DayCare.fee {
                    Text(l.notEnoughTokens).font(.caption2).foregroundStyle(.tertiary)
                } else {
                    Button(l.dayCareDropOffAction) { submit() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .disabled(!canSubmit)
                }
            }
        }
    }

    private func submit() {
        submitting = true
        let parents = selected, knot = useDestinyKnot, everstone = everstoneMonID
        Task {
            let result = await store.dropOff(slot: slot, parentIDs: parents, destinyKnot: knot, everstoneMonID: everstone)
            submitting = false
            if result == .droppedOff { onDone() } else { message = store.l.dayCareDropOffResult(result) }
        }
    }
}

/// One picker row — sprite, name, gender, level, egg groups, and how it pairs with the first pick.
private struct PickerRow: View {
    let store: CompanionStore
    let mon: MonState
    let candidate: DayCare.Candidate?
    let isSelected: Bool
    /// Compatibility with the first pick; nil when nothing else is picked.
    let relation: DayCare.Compatibility?
    let sharedGroups: Set<String>
    var onTap: () -> Void

    /// Can't make eggs at all, or can't pair with the first pick.
    private var dimmed: Bool {
        if candidate?.info.isUndiscovered == true { return true }
        if let relation { return relation != .compatible }
        return false
    }

    var body: some View {
        let l = store.l
        Button(action: onTap) {
            HStack(spacing: 8) {
                SpriteView(speciesID: mon.currentID, size: 48, shiny: mon.isShiny).frame(width: 44, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        SpeciesName(store: store, speciesID: mon.currentID).font(.system(size: 12, weight: .bold)).lineLimit(1)
                        GenderMark(gender: candidate?.gender, l: l)
                        Text(l.pcLevel(mon.level)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 3) {
                        if let groups = candidate?.info.eggGroups {
                            ForEach(groups, id: \.self) { g in
                                EggGroupChip(slug: g, l: l, highlighted: sharedGroups.contains(g))
                            }
                        } else {
                            ProgressView().controlSize(.mini)
                        }
                    }
                }
                Spacer(minLength: 4)
                trailing(l)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.secondary.opacity(isSelected ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5)
                }
            }
            .opacity(dimmed && !isSelected ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .help(helpText(l))
        .accessibilityLabel(helpText(l))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func trailing(_ l: L) -> some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
        } else if relation == .compatible {
            Image(systemName: "heart.fill").foregroundStyle(.pink)
        } else if let relation {
            Text(l.dayCareCompatibilityShort(relation)).font(.system(size: 9)).foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing).frame(maxWidth: 90, alignment: .trailing)
        } else if candidate?.info.isUndiscovered == true {
            Text(l.dayCareCompatibilityShort(.undiscovered)).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    private func helpText(_ l: L) -> String {
        var parts = [store.speciesName(mon.currentID), l.pcLevel(mon.level)]
        if let g = candidate?.gender { parts.append(l.genderLabel(g)) }
        if let groups = candidate?.info.eggGroups { parts.append(groups.map(l.eggGroupName).joined(separator: ", ")) }
        if let relation { parts.append(l.dayCareCompatibility(relation)) }
        return parts.joined(separator: " · ")
    }
}

/// An egg group as a small capsule. Highlighted when it's the group a pair shares.
struct EggGroupChip: View {
    let slug: String
    let l: L
    var highlighted = false

    /// Display order — the games' egg group numbering, Undiscovered last.
    static func order(_ slug: String) -> Int {
        ["monster", "water1", "bug", "flying", "ground", "fairy", "plant", "humanshape", "water3",
         "mineral", "indeterminate", "water2", "ditto", "dragon", "no-eggs"].firstIndex(of: slug) ?? 99
    }

    var body: some View {
        Text(l.eggGroupName(slug)).font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(highlighted ? Color.pink.opacity(0.85) : Color.secondary.opacity(0.14), in: Capsule())
            .foregroundStyle(highlighted ? Color.white : Color.secondary)
    }
}
