import SwiftUI

/// Fixed content size for the standalone battle window (BattleWindowController) — this screen lives
/// in a real window now, not the 360pt popover strip, so it gets real screen real estate instead of
/// PopoverMetrics. Not resizable (styleMask omits `.resizable`) — keeps the battle-scene layout math
/// (below) simple; revisit if that ever feels cramped.
enum BattleWindowMetrics {
    static let width: CGFloat = 520
    static let height: CGFloat = 460
    static let padding: CGFloat = 14
    /// Shared by actionBox/battleOverHoldingBox (their own minHeight) and battleScene (how much
    /// bottom clearance the info boxes need to stay above the action-box overlay) — one number,
    /// not two literals that could quietly drift apart.
    static let actionBoxHeight: CGFloat = 132
}

/// Battle screen — same full-content-swap pattern as Trade/Settings for the picker/waiting/result
/// screens (see PopoverView's reasoning for avoiding .sheet; the same reasoning rules out .sheet for
/// the in-battle voluntary-switch picker below too). Hosted in its own window (BattleWindowController)
/// rather than the popover — the window's own title bar/close button replace what used to be an
/// in-content back button here.
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
    /// Bumped whenever that side's active mon's HP fraction drops between two consecutive polls —
    /// the trigger for battleSprite's hit flash/shake (see battleScene's .onChange below). Any
    /// distinct Int change re-plays the phase sequence, so a plain incrementing counter is enough;
    /// the actual value never gets read for anything but its identity.
    @State private var opponentHitTrigger = 0
    @State private var yourHitTrigger = 0
    /// Gates the win/loss screen behind a short hold once the server reports the battle as
    /// completed — without it, battlingContent would swap straight to resultView the instant
    /// `status == "completed"` arrives, which is the same response that carries the finishing
    /// blow's HP drop, so its hit-flash/faint animation would never get a chance to render at all.
    @State private var revealResult = false

    private var l: L { companion.l }

    private var joinTarget: (sessionId: String, server: String)? {
        if let invite = battle.pendingInvite { return (invite.sessionId, invite.server) }
        return browseTarget
    }

    var body: some View {
        content
            .frame(width: BattleWindowMetrics.width, height: BattleWindowMetrics.height, alignment: .top)
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

    @ViewBuilder
    private var content: some View {
        switch battle.phase {
        case .idle:
            rosterPicker.padding(BattleWindowMetrics.padding)
        case .waitingForOpponent(_, let shareURL):
            waitingForOpponent(shareURL: shareURL).padding(BattleWindowMetrics.padding)
        case .battling(_, let view):
            // Deliberately no padding — a battle scene reads as a real game screen only if the
            // background actually fills the window edge to edge, not sitting in a padded card.
            battlingContent(view)
        case .failed(let error):
            statusView(message: friendlyMessage(for: error), showsSpinner: false, showsRetry: true)
                .padding(BattleWindowMetrics.padding)
        case .expired:
            statusView(message: l.battleExpiredTitle, showsSpinner: false, showsRetry: true)
                .padding(BattleWindowMetrics.padding)
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

    // MARK: In battle — laid out like the handheld games' own battle screen: sky-to-grass field,
    // opponent's info box upper-left / sprite upper-right, your info box lower-right / sprite
    // lower-left, a bordered message/action box along the bottom. Front-facing sprites for both
    // sides (no back-view artwork available here, unlike the real games) is the one deliberate
    // simplification — everything else follows the classic diagonal.

    @ViewBuilder
    private func battlingContent(_ view: BattleClient.BattleView) -> some View {
        if view.status == "completed" && revealResult {
            resultView(view)
        } else if let you = view.you, let opponent = view.opponent {
            // ZStack, not VStack: the action box is a real overlay painted in front of the scene,
            // not a separate panel below it. That's what lets your own (large, foreground) sprite
            // stand *behind* it — its lower body tucked out of sight where they overlap, the same
            // way the real games' message box sits in front of your Pokémon, never the opponent's
            // (theirs is small and far enough up-screen that the two never meet).
            ZStack(alignment: .bottom) {
                // Rendered even once completed — this is what lets the finishing blow's HP-drop
                // (and the fainted side's tip-over) actually play before resultView takes over.
                battleScene(opponent: opponent, you: you)
                if view.status == "completed" {
                    battleOverHoldingBox
                } else {
                    actionBox(view, you: you)
                }
            }
            .task(id: view.status) {
                guard view.status == "completed" else { revealResult = false; return }
                // Long enough for battleSprite's hit-flash (~0.28s) and the faint fade/tilt (0.35s)
                // to finish — see their .phaseAnimator/.animation durations.
                try? await Task.sleep(nanoseconds: 900_000_000)
                if !Task.isCancelled { revealResult = true }
            }
        } else {
            statusView(message: l.battleWaitingForOpponent, showsSpinner: true)
                .padding(BattleWindowMetrics.padding)
        }
    }

    private var battleOverHoldingBox: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(l.battleOver).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BattleWindowMetrics.padding)
        .frame(maxWidth: .infinity, minHeight: BattleWindowMetrics.actionBoxHeight, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.secondary.opacity(0.3)), alignment: .top)
    }

    private func battleScene(opponent: BattleClient.Opponent, you: BattleClient.You) -> some View {
        let yourActive = you.roster[safeIndex: you.activeIndex]
        return ZStack {
            battleFieldBackground
            pokemonInfoBox(name: opponent.displayName, active: opponent.active, benchCount: opponent.rosterSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
            // Kept clear of the action-box overlay below (extra bottom padding) — unlike the plain
            // sprite artwork, this card is information (name/HP) and must never be the thing that's
            // partly hidden.
            pokemonInfoBox(name: you.displayName, active: yourActive, benchCount: you.roster.count)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.horizontal, 14).padding(.top, 14)
                .padding(.bottom, BattleWindowMetrics.actionBoxHeight + 10)
            battleSprite(speciesID: opponent.active?.speciesID, fainted: opponent.active?.fainted ?? false, size: 130, facing: .front, hitTrigger: opponentHitTrigger)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 16).padding(.trailing, 28)
            // .back (the real games' own convention: you see your own mon from behind, the
            // opponent's face-on) and deliberately shallow bottom padding — its lower body is meant
            // to sit behind the action-box overlay the caller (battlingContent) draws in front of
            // this whole scene, the same way the real games' own message box covers the very bottom
            // of your Pokémon but never reaches the opponent's (too far up-screen to ever meet it).
            battleSprite(speciesID: yourActive?.speciesID, fainted: yourActive?.fainted ?? false, size: 170, facing: .back, hitTrigger: yourHitTrigger)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.bottom, 96).padding(.leading, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        // A move landing has no explicit event from the server — only the HP fraction to compare
        // turn over turn — so "it went down since last time we looked" is the hit signal. Detects
        // damage, not status/support moves (Growl etc. never move this number); a fuller effect
        // system would need to parse @pkmn/sim's own log lines, which is a lot more machinery for
        // a cosmetic touch — this covers the actual common case (something got hit).
        .onChange(of: opponent.active?.hpFraction) { old, new in
            if let old, let new, new < old { opponentHitTrigger += 1 }
        }
        .onChange(of: yourActive?.hpFraction) { old, new in
            if let old, let new, new < old { yourHitTrigger += 1 }
        }
    }

    private var battleFieldBackground: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.68, green: 0.85, blue: 0.95), location: 0.0),
                .init(color: Color(red: 0.80, green: 0.91, blue: 0.97), location: 0.42),
                .init(color: Color(red: 0.56, green: 0.76, blue: 0.42), location: 0.44),
                .init(color: Color(red: 0.44, green: 0.66, blue: 0.36), location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom)
    }

    /// A soft ground shadow under the sprite (real games ground their sprites on a battle platform)
    /// plus a fainted cue — real games have the sprite slide/drop off-screen; a 90° tilt is the
    /// cheapest approximation that still reads as "down" without an actual animation timeline.
    private func battleSprite(speciesID: Int?, fainted: Bool, size: CGFloat, facing: SpriteFacing, hitTrigger: Int) -> some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.16))
                .frame(width: size * 0.85, height: size * 0.24)
                .offset(y: size * 0.44)
            SpriteView(speciesID: speciesID, size: size, facing: facing)
                .opacity(fainted ? 0.35 : 1)
                .rotationEffect(.degrees(fainted ? 90 : 0))
                // Hit flash/shake — a quick left-right jitter + brightness pop, replayed once per
                // hitTrigger bump (see battleScene's .onChange). No move-type tinting (would need the
                // opponent's move name resolved to a type we usually don't have data for locally).
                .phaseAnimator([0, 1, 2, 0], trigger: hitTrigger) { content, phase in
                    content
                        .offset(x: phase == 1 ? -7 : (phase == 2 ? 7 : 0))
                        .brightness(phase == 1 || phase == 2 ? 0.6 : 0)
                } animation: { _ in .easeInOut(duration: 0.07) }
        }
        .animation(.easeInOut(duration: 0.35), value: fainted)
    }

    private func pokemonInfoBox(name: String, active: BattleClient.PublicMon?, benchCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(name).font(.system(size: 12, weight: .bold)).lineLimit(1)
                Spacer(minLength: 4)
                Text("×\(benchCount)").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            if let active {
                HStack(spacing: 5) {
                    Text("HP").font(.system(size: 8, weight: .heavy)).italic().foregroundStyle(.orange)
                    HPBar(fraction: active.hpFraction).frame(width: 92, height: 7)
                }
            } else {
                Text("—").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.22), radius: 3, y: 2))
    }

    private func actionBox(_ view: BattleClient.BattleView, you: BattleClient.You) -> some View {
        Group {
            if voluntarySwitchOpen {
                switchStrip(you.roster, activeIndex: you.activeIndex, forced: false)
            } else if view.pendingChoice == "switch" {
                VStack(alignment: .leading, spacing: 6) {
                    Text(l.battleForcedSwitchPrompt).font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                    switchStrip(you.roster, activeIndex: you.activeIndex, forced: true)
                }
            } else if view.pendingChoice == "move" {
                moveGrid(you: you)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(l.battleWaitingOnOpponentToChooseMove(view.opponent?.displayName ?? "")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(BattleWindowMetrics.padding)
        .frame(maxWidth: .infinity, minHeight: BattleWindowMetrics.actionBoxHeight, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.secondary.opacity(0.3)), alignment: .top)
    }

    private func moveGrid(you: BattleClient.You) -> some View {
        Group {
            if let mon = battle.myRoster[safeIndex: you.activeIndex] {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l.battleWaitingOnYouToChooseMove).font(.system(size: 12, weight: .semibold))
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
        return VStack(spacing: 14) {
            Spacer()
            Text(title).font(.system(size: 22, weight: .bold))
            Button(l.battleDoneButton) { battle.cancel(); onClose() }.buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(battleFieldBackground)
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
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(Array(mon.knownMoves.enumerated()), id: \.offset) { index, moveID in
                let move = moves[safeIndex: index] ?? nil
                Button {
                    onChoose(index + 1)
                } label: {
                    HStack(spacing: 6) {
                        Text(move?.localizedName(store.language) ?? "#\(moveID)")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        if let move {
                            // Same type-badge convention CompanionView's MoveRow already uses —
                            // reused directly, not reinvented.
                            Text(store.l.typeName(move.type).uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(typeColor(move.type)).foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
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
