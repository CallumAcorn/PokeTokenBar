import SwiftUI

/// Battle screen — same full-content-swap pattern as Trade/Settings (see PopoverView's reasoning
/// for avoiding .sheet; the same reasoning rules out .sheet for the in-battle voluntary-switch
/// picker below too, not just top-level screens).
struct BattleView: View {
    @Environment(CompanionStore.self) private var companion
    @Environment(BattleStore.self) private var battle
    @Environment(OnlineStore.self) private var online
    var onClose: () -> Void

    @State private var selectedMonIDs: Set<MonState.ID> = []
    @State private var confirmingLink: BattleDeepLink?
    @State private var copiedFeedback = false
    @State private var pastedInviteLink = ""
    @State private var pastedInviteError = false
    @State private var showBrowse = false
    /// A session picked from the open-lobby list — the browse-path equivalent of `battle.pendingInvite`
    /// (a deep link). Both converge on the same roster picker → `joinBattle` call.
    @State private var browseTarget: (sessionId: String, server: String)?
    @State private var voluntarySwitchOpen = false

    private var l: L { companion.l }

    private var joinTarget: (sessionId: String, server: String)? {
        if let invite = battle.pendingInvite { return (invite.sessionId, invite.server) }
        return browseTarget
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .padding(PopoverMetrics.padding)
        .frame(width: PopoverMetrics.width)
        .task { checkPendingInvite() }
        .onChange(of: battle.pendingInvite) { checkPendingInvite() }
        .alert(l.battleJoinButton, isPresented: Binding(get: { confirmingLink != nil }, set: { if !$0 { declineInvite() } }),
               presenting: confirmingLink) { link in
            Button(l.battleJoinButton) { online.serverURL = link.server; confirmingLink = nil }
            Button(l.tradeCancelButton, role: .cancel) { declineInvite() }
        } message: { link in
            Text(online.serverURL.isEmpty
                 ? l.battleConnectServerConfirm(link.server)
                 : l.battleDifferentServerConfirm(link.server))
        }
    }

    /// Same reasoning as TradeView.checkPendingInvite: a `poketokenbar://` link is attacker-
    /// influenced (any web page can open one), so the server it names is always confirmed before
    /// anything is submitted to it — including the no-server-configured case.
    private func checkPendingInvite() {
        guard let link = battle.pendingInvite else { return }
        if !online.serverURL.isEmpty, sameServer(online.serverURL, link.server) { return }
        confirmingLink = link
    }
    private func declineInvite() {
        confirmingLink = nil
        battle.declineInvite()
    }
    private func sameServer(_ a: String, _ b: String) -> Bool {
        guard let ua = OnlineStore.endpointURL(from: a, path: "/"),
              let ub = OnlineStore.endpointURL(from: b, path: "/") else { return false }
        return ua.host == ub.host && ua.port == ub.port
    }
    private var hasValidDisplayName: Bool {
        (1...60).contains(online.displayName.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }

    private func friendlyMessage(for error: BattleStore.StoreError) -> String {
        switch error {
        case .client(.server(status: 401)): return l.tradeAuthErrorMessage
        case .client(.server(status: 403)): return l.tradeNotParticipantMessage
        case .client(.server(status: 409)): return l.tradeConflictMessage
        case .primitive(.noKnownMoves): return l.battleNoKnownMovesMessage
        case .primitive(.missingBaseStats): return l.battleMissingDataMessage
        default: return "\(l.battleFailedTitle): \(String(describing: error))"
        }
    }

    private var header: some View {
        HStack {
            Button { onClose() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            Text(l.battleTitle).font(.callout.weight(.semibold))
            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch battle.phase {
        case .idle:
            rosterPicker
        case .waitingForOpponent(_, let shareURL):
            waitingForOpponent(shareURL: shareURL)
        case .battling(_, let view):
            battlingContent(view)
        case .failed(let error):
            statusView(message: friendlyMessage(for: error), showsSpinner: false, showsRetry: true)
        case .expired:
            statusView(message: l.battleExpiredTitle, showsSpinner: false, showsRetry: true)
        }
    }

    // MARK: Picking a roster

    private var rosterPicker: some View {
        // A mon with no known moves yet can't field a legal roster slot (the server would reject
        // it) — filtered out here so the picker never offers a pick that's doomed to fail. Unlike
        // trading's offer picker, the whole party is eligible, not just the bench — battling never
        // removes a mon from the PC the way a trade does (battles.md's Flow §1).
        let eligible = companion.party.filter { !$0.knownMoves.isEmpty }
        let target = joinTarget
        return VStack(alignment: .leading, spacing: 8) {
            if let target {
                HStack {
                    Text(l.battleJoinPrompt(target.server)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { browseTarget = nil; declineInvite() } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless)
                }
            } else {
                Picker("", selection: $showBrowse) {
                    Text(l.battleShareTab).tag(false)
                    Text(l.battleBrowseOpen).tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: showBrowse) { if showBrowse { Task { await battle.refreshOpenBattles() } } }
                if showBrowse {
                    openBattlesList
                } else {
                    pasteInviteRow
                }
            }
            if !hasValidDisplayName {
                Text(l.tradeDisplayNameRequired).font(.caption2).foregroundStyle(.orange)
            }
            Text(l.battlePickRoster).font(.caption).foregroundStyle(.secondary)
            if eligible.isEmpty {
                Text(l.battleNoBenchedMons).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(eligible) { mon in
                            BattleRosterRow(store: companion, mon: mon, isSelected: selectedMonIDs.contains(mon.id)) {
                                toggle(mon.id)
                            }
                        }
                    }
                }
                // Fixed height, not maxHeight — same reasoning as TradeView's offer list.
                .frame(height: 240)
                Button(target != nil ? l.battleJoinButton : l.battleCreateButton) {
                    let roster = eligible.filter { selectedMonIDs.contains($0.id) }
                    Task {
                        if let target {
                            await battle.joinBattle(sessionId: target.sessionId, server: target.server, roster: roster)
                        } else {
                            await battle.createBattle(roster: roster)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedMonIDs.isEmpty || !hasValidDisplayName)
            }
        }
    }

    private func toggle(_ id: MonState.ID) {
        if selectedMonIDs.contains(id) {
            selectedMonIDs.remove(id)
        } else if selectedMonIDs.count < BattleClient.maxRosterSize {
            selectedMonIDs.insert(id)
        }
    }

    private var pasteInviteRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField(l.battlePasteInviteLinkPlaceholder, text: $pastedInviteLink)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit(submitPastedInviteLink)
                Button(l.battleJoinButton, action: submitPastedInviteLink)
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(pastedInviteLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if pastedInviteError {
                Text(l.battleInvalidInviteLink).font(.caption2).foregroundStyle(.red)
            }
        }
    }

    private func submitPastedInviteLink() {
        guard let link = BattleDeepLink(pastedText: pastedInviteLink) else {
            pastedInviteError = true
            return
        }
        pastedInviteError = false
        pastedInviteLink = ""
        battle.handleIncomingLink(link)
    }

    private var openBattlesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if battle.openBattles.isEmpty {
                Text(l.battleNoOpenBattles).font(.caption2).foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(battle.openBattles, id: \.sessionId) { open in
                            Button {
                                browseTarget = (open.sessionId, online.serverURL)
                            } label: {
                                HStack {
                                    Text(open.displayName).font(.caption)
                                    Spacer()
                                    Text("\(open.rosterSize)").font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(6)
                                .background(Color.secondary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 120)
            }
            Button { Task { await battle.refreshOpenBattles() } } label: {
                Label(l.battleBrowseOpen, systemImage: "arrow.clockwise")
            }.buttonStyle(.borderless).controlSize(.small)
        }
    }

    // MARK: Waiting to be joined

    private func waitingForOpponent(shareURL: URL?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(l.battleWaitingForOpponent).font(.caption).foregroundStyle(.secondary)
            }
            if let shareURL {
                HStack(spacing: 8) {
                    ShareLink(item: shareURL) { Label(l.tradeShareLink, systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(shareURL.absoluteString, forType: .string)
                        copiedFeedback = true
                        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copiedFeedback = false }
                    } label: {
                        Label(copiedFeedback ? l.tradeCopied : l.tradeCopyLink, systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }
            Button(l.tradeCancelButton) { battle.cancel() }.buttonStyle(.borderless)
        }
    }

    // MARK: In battle

    @ViewBuilder
    private func battlingContent(_ view: BattleClient.BattleView) -> some View {
        if view.status == "completed" {
            resultView(view)
        } else if let you = view.you, let opponent = view.opponent {
            VStack(alignment: .leading, spacing: 10) {
                sideHeader(displayName: opponent.displayName, active: opponent.active, benchCount: opponent.rosterSize)
                Divider()
                sideHeader(displayName: you.displayName, active: you.roster[safeIndex: you.activeIndex], benchCount: you.roster.count)
                if voluntarySwitchOpen {
                    switchStrip(you.roster, activeIndex: you.activeIndex, forced: false)
                } else if view.pendingChoice == "switch" {
                    Text(l.battleForcedSwitchPrompt).font(.caption2).foregroundStyle(.orange)
                    switchStrip(you.roster, activeIndex: you.activeIndex, forced: true)
                } else if view.pendingChoice == "move" {
                    moveGrid(you: you)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(l.battleWaitingForYourMove).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            statusView(message: l.battleWaitingForOpponent, showsSpinner: true)
        }
    }

    private func sideHeader(displayName: String, active: BattleClient.PublicMon?, benchCount: Int) -> some View {
        HStack(spacing: 8) {
            SpriteView(speciesID: active?.speciesID, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName).font(.caption.weight(.semibold))
                if let active {
                    HPBar(fraction: active.hpFraction)
                        .frame(width: 100, height: 6)
                    Text(active.name).font(.system(size: 9)).foregroundStyle(.secondary)
                } else {
                    Text("—").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text("\(benchCount)").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func moveGrid(you: BattleClient.You) -> some View {
        Group {
            if let mon = battle.myRoster[safeIndex: you.activeIndex] {
                VStack(alignment: .leading, spacing: 8) {
                    BattleMoveGrid(store: companion, mon: mon) { slot in
                        Task { await battle.choose(BattleStore.moveChoice(slot)) }
                    }
                    Button(l.battleSwitchButton) { voluntarySwitchOpen = true }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
    }

    private func switchStrip(_ roster: [BattleClient.PublicMon], activeIndex: Int, forced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(roster.enumerated()), id: \.offset) { index, mon in
                Button {
                    voluntarySwitchOpen = false
                    Task { await battle.choose(BattleStore.switchChoice(index + 1)) }
                } label: {
                    HStack(spacing: 8) {
                        SpriteView(speciesID: mon.speciesID, size: 32)
                        Text(mon.name).font(.caption)
                        Spacer()
                        HPBar(fraction: mon.hpFraction).frame(width: 60, height: 6)
                        if mon.fainted { Image(systemName: "xmark.circle").font(.caption2).foregroundStyle(.red) }
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(index == activeIndex ? 0.16 : 0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(mon.fainted || index == activeIndex)
            }
            if !forced {
                Button(l.tradeCancelButton) { voluntarySwitchOpen = false }.buttonStyle(.borderless)
            }
        }
    }

    private func resultView(_ view: BattleClient.BattleView) -> some View {
        let title = switch view.result {
        case "win": l.battleResultWin
        case "loss": l.battleResultLoss
        default: l.battleResultDraw
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.bold))
            Button(l.battleDoneButton) { battle.cancel(); onClose() }.buttonStyle(.borderedProminent)
        }
    }

    // MARK: Status messages

    private func statusView(message: String, showsSpinner: Bool, showsRetry: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if showsSpinner { ProgressView().controlSize(.small) }
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if showsRetry {
                Button(l.tradeTryAgainButton) { battle.cancel() }.buttonStyle(.bordered)
            }
        }
    }
}

private extension Array {
    subscript(safeIndex index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// One mon row on the roster picker — sprite + level/rarity/shiny, mirrors TradeOfferRow but with a
/// checkmark (multi-select) instead of a plain highlight (trade only ever selects one).
private struct BattleRosterRow: View {
    let store: CompanionStore
    let mon: MonState
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                SpriteView(speciesID: mon.currentID, size: 40, shiny: mon.isShiny)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(store.l.pcLevel(mon.level)).font(.system(size: 11, weight: .bold))
                        if mon.isShiny { Text("✨").font(.system(size: 10)) }
                    }
                    Text(store.l.rarityLabel(mon.rarity)).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .padding(8)
            .background(Color.secondary.opacity(isSelected ? 0.16 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

/// A mon's up-to-4 known moves as tappable buttons — loaded from `CompanionStore.moveDetail`, the
/// same source the PC detail screen's known-move list already uses. Local data only (see
/// `BattleStore.myRoster`'s doc comment for why the server's own response can't supply this).
private struct BattleMoveGrid: View {
    let store: CompanionStore
    let mon: MonState
    let onChoose: (Int) -> Void

    @State private var moves: [Move?] = []

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(Array(mon.knownMoves.enumerated()), id: \.offset) { index, moveID in
                Button {
                    onChoose(index + 1)
                } label: {
                    Text(moves[safeIndex: index].flatMap { $0?.localizedName(store.language) } ?? "#\(moveID)")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .task(id: mon.id) {
            var loaded: [Move?] = []
            for id in mon.knownMoves { loaded.append(await store.moveDetail(id: id)) }
            moves = loaded
        }
    }
}

/// Small horizontal HP meter — green above half, orange above a quarter, red below. No numeric
/// value shown (the server only ever gives a fraction, matching real games' "don't show exact HP
/// numbers for the opponent" convention — showing a number for your own side but not the
/// opponent's would be an inconsistent UI for no real benefit, so neither side gets one).
private struct HPBar: View {
    let fraction: Double
    private var color: Color {
        if fraction > 0.5 { return .green }
        if fraction > 0.2 { return .orange }
        return .red
    }
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.2))
                RoundedRectangle(cornerRadius: 3).fill(color)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
    }
}
