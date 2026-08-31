import SwiftUI

/// Fixed content size for the standalone battle window (BattleWindowController) — this screen lives
/// in a real window now, not the 360pt popover strip, so it gets real screen real estate instead of
/// PopoverMetrics. Not resizable (styleMask omits `.resizable`) — keeps the battle-scene layout math
/// (below) simple; revisit if that ever feels cramped.
enum BattleWindowMetrics {
    static let width: CGFloat = 520
    static let height: CGFloat = 460
    static let padding: CGFloat = 14
    /// Shared by actionBox/battleOverHoldingBox (their own `minHeight`) and battleScene (how much
    /// bottom clearance the info boxes need to stay above the action-box overlay) — one number, not
    /// two literals that could quietly drift apart. Sized for the tallest *routine* content: a 2-row
    /// move grid + label + Switch button + a "Used X!" line, all at BattleMoveGrid's compact
    /// `.controlSize(.small)`. The voluntary-switch roster list can still grow past this for a big
    /// party — that's `minHeight`, not a hard cap, so it's allowed to (nothing below it to cover).
    static let actionBoxHeight: CGFloat = 185
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
    /// Which screen of the "how do you want to start" flow is showing, before any join target is
    /// locked in — see `rosterPicker`. Once a target exists (a deep link, a submitted paste, or a
    /// browse tap all converge on `joinTarget`) or `creatingNew` is set, this step is bypassed
    /// entirely in favor of the roster-pick screen; it only governs the *pre*-target choice.
    private enum PickerStep { case chooseMode, pasteLink, browseList }
    @State private var pickerStep: PickerStep = .chooseMode
    /// Set when the user picks "Create Battle" from the mode chooser — distinguishes "creating fresh,
    /// no target yet" from "still choosing how to start" now that both skip straight past `pickerStep`
    /// to the same roster-pick screen `joinTarget` drives.
    @State private var creatingNew = false
    /// A session picked from the open-lobby list — the browse-path equivalent of `battle.pendingInvite`
    /// (a deep link). Both converge on the same roster picker → `joinBattle` call.
    @State private var browseTarget: (sessionId: String, server: String)?
    @State private var voluntarySwitchOpen = false
    /// Bumped for every move that lands on that side, not just damaging ones — see battleScene's
    /// .onChange and triggerMoveEffect. `color` comes from the move's real type (typeColor, the
    /// same palette move buttons already use); `isDamaging` (damageClass != .status) switches
    /// battleSprite between a shake+flash and a gentler pulse+glow.
    // `fileprivate`, not `private` — shared with `BattleSpriteFlash` below, a sibling top-level
    // type in this same file (a nested `private` type is only visible inside BattleView itself).
    fileprivate struct SpriteEffect: Equatable {
        var trigger = 0
        var color = Color.white
        var isDamaging = true
    }
    @State private var opponentEffect = SpriteEffect()
    @State private var yourEffect = SpriteEffect()
    /// Short floating labels next to a sprite ("+1 SPE", "Poisoned!", "-14% HP") — the numeric/named
    /// detail the flash/color alone doesn't convey. A list, not a single overwritten value, because
    /// one log update can carry more than one (Leech Seed damages one side and heals the other in
    /// the same tick). Each entry removes itself after a beat — see `addEffectChip`.
    @State private var opponentChips: [EffectChip] = []
    @State private var yourChips: [EffectChip] = []
    /// Running "last known HP fraction" per log identity ("p1a: Ash-0"), so `parseLogBeats` can turn
    /// a `-damage`/`-heal` line's absolute HP into a delta — see its doc comment.
    @State private var hpFractionsByIdent: [String: Double] = [:]
    /// This side's real max HP for whichever mon is currently active — known (unlike the opponent's,
    /// permanently hidden) because this is *our own* roster, computed the same way `primitive(for:)`
    /// did to build the battle request in the first place. Refreshed by battleScene's `.task(id:)`
    /// whenever the active mon changes; `nil` until that first resolves (or if it fails), in which
    /// case HP chips just show the "% HP" fallback `parseLogBeats` already computed.
    @State private var myActiveMaxHP: Int?
    /// Beats not yet played, in arrival order — `enqueueBeats` appends to this and starts
    /// `drainBeats` if it isn't already running; a poll landing mid-playback just grows the queue
    /// instead of spawning a second concurrent player (which would re-introduce the exact
    /// out-of-order/simultaneous playback this queue exists to prevent).
    @State private var pendingBeats: [LogBeat] = []
    @State private var isPlayingBeats = false
    /// Gates the win/loss screen behind a short hold once the server reports the battle as
    /// completed — without it, battlingContent would swap straight to resultView the instant
    /// `status == "completed"` arrives, which is the same response that carries the finishing
    /// blow's HP drop, so its hit-flash/faint animation would never get a chance to render at all.
    @State private var revealResult = false
    /// Resolved once per battle from `view.hostLeadSpeciesID` (see `battlingContent`'s `.task`) —
    /// `nil` until that resolves (or if it never does), during which `battleFieldBackground` falls
    /// back to the plain gradient it replaced.
    @State private var battleBackgroundImage: NSImage?
    /// The fully-formatted "Pikachu used Thunder Shock!" text for whatever move is currently being
    /// played back (see `play(_:)`/`showMoveUsedText`) — shown so a status move (Growl, Tail Whip…)
    /// that never moves an HP bar still gets some visible confirmation it did something, not just
    /// damaging moves. Self-clearing rather than sitting there permanently once any move has landed.
    @State private var recentMoveText: String?
    /// Bumped every time `showMoveUsedText` runs — see its doc comment for why.
    @State private var moveTextGeneration = 0
    @State private var lastSeenLogCount = 0
    /// The full battle log, toggled on demand — off by default (the scene + action box already
    /// cover "what do I do now"; this is for "what actually happened", opt-in detail).
    @State private var showMoveLog = false
    @State private var confirmingForfeit = false

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

    struct MoveLogEvent: Equatable {
        let moveName: String
        let userIsMine: Bool
        let targetIsMine: Bool
        /// The species name of whichever mon used the move ("Pikachu") — `nil` straight out of
        /// `parseLogBeats` (a log identifier like "p1a: Ash-0" carries no species info, only this
        /// app's own `"{displayName}-{index}"` nickname), filled in afterward by `battleScene`'s
        /// `.onChange(of: log)` from the *currently active* mon on the acting side (`you`/`opponent`
        /// already carry real species names — see `PublicMon.name`). A move is always used by
        /// whichever mon is active when it lands, so "whoever the view currently shows as active for
        /// that side" is accurate, not an approximation that can go stale mid-battle.
        var userName: String? = nil
    }

    struct EffectChip: Identifiable, Equatable {
        let id = UUID()
        /// `var`, not `let` — an HP chip's percentage text can be upgraded to a real point count
        /// after parsing, once this side's real max HP is known; see `hpDeltaFraction` below.
        var text: String
        let isMine: Bool
        let isPositive: Bool
        /// Set only for an HP chip (`-heal`/`-damage`) — the raw, unrounded fraction of max HP this
        /// side just gained/lost. `text` is already a formatted "-20% HP" fallback using this same
        /// number; `battleScene`'s `.onChange(of: log)` upgrades `isMine` chips to a real point count
        /// ("-14 HP") when it knows this side's real max HP, by multiplying this fraction against it
        /// rather than re-deriving anything from the already-rounded percentage text. `nil` for every
        /// other chip kind (a stat stage, a status, a faint) — nothing to upgrade there.
        var hpDeltaFraction: Double? = nil

        // `id` (and `hpDeltaFraction`, which only ever varies alongside `text` anyway) deliberately
        // excluded — every chip gets a fresh UUID (needed so ForEach/removal-by-id work when two
        // chips carry identical text), which would make two otherwise-identical chips never compare
        // equal by synthesized Equatable. Content is what tests (and SwiftUI's `.animation(value:)`
        // change-detection) actually care about.
        static func == (lhs: EffectChip, rhs: EffectChip) -> Bool {
            lhs.text == rhs.text && lhs.isMine == rhs.isMine && lhs.isPositive == rhs.isPositive
        }
    }

    /// One line of "what visibly happened" — a move landing (flash + banner) or a side-effect chip
    /// (a stat stage, a status, an HP swing, a faint). Kept as an enum, not two separate arrays, so
    /// playback can walk them in one single, already-correctly-ordered sequence — see `parseLogBeats`.
    enum LogBeat: Equatable {
        case move(MoveLogEvent)
        case chip(EffectChip)
    }

    /// Walks whatever's new in the raw @pkmn/sim log since the last time this was called
    /// (`previouslySeenCount`) exactly once, in order, turning each recognized line into a beat —
    /// a move (`|move|{user}|{MoveName}|{target}`) or a side-effect chip. The point of doing this in
    /// a single ordered pass, rather than two separate scans concatenated together, is turn order:
    /// `@pkmn/sim` has already resolved who acts first (speed, priority brackets, speed ties) before
    /// any of this ever reaches the client, and that resolution *is* the log's own line order — so
    /// playing beats back in the order this function emits them, one at a time (see
    /// `BattleView.enqueueBeats`), is the whole fix. No speed/priority logic needs to exist client-side.
    ///
    /// HP is reported as a *fraction* — this side's delta vs the same identity's last known fraction,
    /// assumed 1.0 the first time an identity is seen (true for any mon that hasn't been hit yet this
    /// battle) — never a real number for either side, deliberately matching `HPBar`'s own choice: a
    /// number for your own mon but not the opponent's hidden real stats would be an inconsistent UI
    /// for no real benefit.
    ///
    /// `hpFractions` is `inout`, not captured state, so this stays a pure/testable function — the
    /// caller owns persisting it across calls. Cleared on the same "log got shorter" reset as
    /// `previouslySeenCount` itself (a new battle reusing this window) — carrying stale fractions over
    /// would corrupt every delta for a new battle whose mons happen to reuse the same
    /// "{displayName}-{index}" nicknames. `log.count < previouslySeenCount` is that same signal:
    /// reset to 0 rather than crash on a negative range.
    static func parseLogBeats(from log: [String], previouslySeenCount: Int, myDisplayName: String, l: L,
                               hpFractions: inout [String: Double]) -> (beats: [LogBeat], seenCount: Int) {
        if log.count < previouslySeenCount { hpFractions.removeAll() }
        let seenCount = log.count < previouslySeenCount ? 0 : previouslySeenCount
        guard log.count > seenCount else { return ([], log.count) }
        var beats: [LogBeat] = []
        for line in log[seenCount...] {
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 3 else { continue }
            let isMine = identBelongsToMe(parts[2], myDisplayName: myDisplayName)
            switch parts[1] {
            case "move":
                guard parts.count >= 4 else { continue }
                // No explicit target field (some self-targeting moves omit it) — assume it landed on
                // whoever used it, the same side the move came from.
                let targetIsMine = parts.count >= 5 ? identBelongsToMe(parts[4], myDisplayName: myDisplayName) : isMine
                beats.append(.move(MoveLogEvent(moveName: parts[3], userIsMine: isMine, targetIsMine: targetIsMine)))
            case "-boost", "-unboost":
                guard parts.count >= 5, let stat = statLabel(parts[3], l: l), let amount = Int(parts[4]) else { continue }
                let positive = parts[1] == "-boost"
                beats.append(.chip(EffectChip(text: "\(positive ? "+" : "-")\(amount) \(stat)", isMine: isMine, isPositive: positive)))
            case "-status":
                guard parts.count >= 4, let name = statusName(parts[3], l: l) else { continue }
                beats.append(.chip(EffectChip(text: name, isMine: isMine, isPositive: false)))
            case "-curestatus":
                beats.append(.chip(EffectChip(text: l.battleStatusCured, isMine: isMine, isPositive: true)))
            case "-heal", "-damage":
                guard parts.count >= 4, let frac = hpFraction(parts[3]) else { continue }
                let prev = hpFractions[parts[2]] ?? 1.0
                hpFractions[parts[2]] = frac
                let rawDelta = frac - prev
                let deltaPct = Int((rawDelta * 100).rounded())
                guard deltaPct != 0 else { continue }
                // "% HP" is the fallback for a side whose real max HP is unknowable (the opponent's
                // hidden real stats) — battleScene's .onChange upgrades `isMine` chips to a real point
                // count when it knows this side's real max HP, using `hpDeltaFraction` below.
                beats.append(.chip(EffectChip(text: "\(deltaPct > 0 ? "+" : "")\(deltaPct)% HP", isMine: isMine,
                                               isPositive: deltaPct > 0, hpDeltaFraction: rawDelta)))
            case "faint":
                beats.append(.chip(EffectChip(text: l.battleFainted, isMine: isMine, isPositive: false)))
            default:
                continue
            }
        }
        return (beats, log.count)
    }

    /// A log mon identifier looks like "p1a: Ash-0" — the part after ": " is `toPokemonSet`'s own
    /// nickname convention, `"{displayName}-{index}"` (pkmnAdapter.ts), so a prefix match against
    /// `"{myDisplayName}-"` tells the two sides apart without this app ever needing to learn which
    /// of "p1"/"p2" it actually is server-side (deliberately never told — the wire format always
    /// speaks in terms of "you"/"opponent", not p1/p2).
    private static func identBelongsToMe(_ ident: String, myDisplayName: String) -> Bool {
        guard let colonRange = ident.range(of: ": ") else { return false }
        return ident[colonRange.upperBound...].hasPrefix(myDisplayName + "-")
    }

    private static func statLabel(_ code: String, l: L) -> String? {
        switch code {
        case "atk": return l.statAttack
        case "def": return l.statDefense
        case "spa": return l.statSpecialAttack
        case "spd": return l.statSpecialDefense
        case "spe": return l.statSpeed
        case "accuracy": return l.statAccuracy
        case "evasion": return l.statEvasion
        default: return nil
        }
    }

    private static func statusName(_ code: String, l: L) -> String? {
        switch code {
        case "brn": return l.battleStatusBurned
        case "par": return l.battleStatusParalyzed
        case "psn", "tox": return l.battleStatusPoisoned
        case "slp": return l.battleStatusAsleep
        case "frz": return l.battleStatusFrozen
        default: return nil
        }
    }

    /// "91/100" → 0.91; "91/100 par" (status suffix) → 0.91; "0 fnt" (fainted) → 0. `nil` for
    /// anything else (e.g. a malformed line) rather than a guessed value.
    private static func hpFraction(_ raw: String) -> Double? {
        let token = raw.components(separatedBy: " ").first ?? raw
        if token == "0" { return 0 }
        let comps = token.components(separatedBy: "/")
        guard comps.count == 2, let cur = Double(comps[0]), let max = Double(comps[1]), max > 0 else { return nil }
        return cur / max
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
            // The picker is a reused view in a reused window (BattleWindowController never rebuilds
            // it) — without this, canceling out of one battle (or finishing one and hitting Done)
            // would leave the next visit showing the last roster pick, browse tab, and pasted link,
            // as if they'd carried over from an unrelated session. onAppear fires every time the
            // switch re-enters .idle, which covers both "returning to idle" and "window reopened
            // while already idle" in one hook.
            rosterPicker.padding(BattleWindowMetrics.padding)
                .onAppear { resetPickerState() }
        case .starting:
            // The instant gap between tapping Create/Join and there being anything real to show
            // (the roster-build + create/join POST + join's first confirming poll) — without this,
            // the roster picker just sat there unchanged after a tap, reading as stuck/unresponsive.
            statusView(message: l.battleStartingTitle, showsSpinner: true)
                .padding(BattleWindowMetrics.padding)
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
    //
    // A step-by-step flow, not one screen showing everything at once: "how do you want to start"
    // (create / join via link / browse) is its own screen; picking a target (pasting a link,
    // browsing) is its own screen; picking a roster is its own screen, reached only once a target
    // exists (joining) or "Create" was explicitly chosen. At most one of these is ever visible.

    @ViewBuilder
    private var rosterPicker: some View {
        if let target = joinTarget {
            rosterPickStep(target: target)
        } else if creatingNew {
            rosterPickStep(target: nil)
        } else {
            switch pickerStep {
            case .chooseMode: modeChooserStep
            case .pasteLink: pasteLinkStep
            case .browseList: browseListStep
            }
        }
    }

    /// Step 1: how to start. No roster/link/browse detail on screen yet — just the three ways in, as
    /// real tappable cards (icon badge + title + subtitle + chevron) rather than plain native
    /// `.bordered` rows, which read thin and flat at this size — this is the screen's *only* content,
    /// so it can afford to give each choice real visual weight.
    private var modeChooserStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l.battleStartPrompt).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            modeChoiceButton(title: l.battleCreateButton, subtitle: l.battleCreateSubtitle,
                              icon: "plus.circle.fill", tint: .accentColor) {
                creatingNew = true
            }
            modeChoiceButton(title: l.battleJoinViaLinkButton, subtitle: l.battleJoinViaLinkSubtitle,
                              icon: "link", tint: .blue) {
                pickerStep = .pasteLink
            }
            modeChoiceButton(title: l.battleBrowseOpen, subtitle: l.battleBrowseSubtitle,
                              icon: "magnifyingglass", tint: .orange) {
                pickerStep = .browseList
                Task { await battle.refreshOpenBattles() }
            }
        }
    }

    /// A big, card-style entry-point button — icon badge, title + one-line subtitle, trailing
    /// chevron. Same custom-chrome-over-`.plain` convention `pcStyleTile`/`openBattlesList`'s rows
    /// already use elsewhere in this file, not a new pattern.
    private func modeChoiceButton(title: String, subtitle: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(.primary)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Step 2a: paste a link. Submitting a valid one sets `battle.pendingInvite`, which makes
    /// `joinTarget` non-nil — `rosterPicker` advances to the roster-pick step on its own next render,
    /// no explicit step transition needed here.
    private var pasteLinkStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            backButton
            Text(l.battlePasteLinkPrompt).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            pasteInviteRow
        }
    }

    /// Step 2b: browse the open lobby. Tapping an entry sets `browseTarget`, which — same as
    /// `pasteLinkStep` — makes `joinTarget` non-nil and advances the flow on its own.
    private var browseListStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            backButton
            Text(l.battleBrowsePrompt).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            openBattlesList
        }
    }

    private var backButton: some View {
        Button { pickerStep = .chooseMode } label: {
            Label(l.back, systemImage: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.borderless)
    }

    /// Step 3, shared by both create and join: pick a roster, then confirm. `target` is `nil` only
    /// for a fresh create — everything else about this screen (the "X" to back out, the display-name
    /// gate, the grid, the submit button) is identical either way.
    private func rosterPickStep(target: (sessionId: String, server: String)?) -> some View {
        // A mon with no known moves yet can't field a legal roster slot (the server would reject
        // it) — filtered out here so the picker never offers a pick that's doomed to fail. Unlike
        // trading's offer picker, the whole party is eligible, not just the bench — battling never
        // removes a mon from the PC the way a trade does (battles.md's Flow §1).
        let eligible = companion.party.filter { !$0.knownMoves.isEmpty }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(target != nil ? l.battleJoinPrompt(target!.server) : l.battlePickRoster)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    browseTarget = nil
                    declineInvite()
                    creatingNew = false
                    pickerStep = .chooseMode
                } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.borderless)
            }
            if !hasValidDisplayName {
                Text(l.tradeDisplayNameRequired).font(.caption2).foregroundStyle(.orange)
            }
            if eligible.isEmpty {
                Text(l.battleNoBenchedMons).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack {
                    sectionHeader(l.battleYourTeam)
                    Spacer()
                    Text("\(selectedMonIDs.count)/\(BattleClient.maxRosterSize)")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
                // Your picked team, always visible above the full party — 3 wide × 2 high (up to 6),
                // empty dashed slots for the rest. Tap a filled one to drop it back out.
                selectedRosterGrid(eligible: eligible)
                sectionHeader(l.battleYourParty)
                ScrollView {
                    partyGrid(eligible: eligible)
                }
                // Fixed height, not maxHeight — same reasoning as TradeView's offer list.
                .frame(height: 130)
                Button {
                    let roster = eligible.filter { selectedMonIDs.contains($0.id) }
                    Task {
                        if let target {
                            await battle.joinBattle(sessionId: target.sessionId, server: target.server, roster: roster)
                        } else {
                            await battle.createBattle(roster: roster)
                        }
                    }
                } label: {
                    Text(target != nil ? l.battleJoinButton : l.battleCreateButton)
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedMonIDs.isEmpty || !hasValidDisplayName)
            }
        }
    }

    /// Small uppercase/tracked label over a section of the picker — "Your Team" over the 3×2 picked
    /// grid, "Your Party" over the full scrollable grid below it, so the two are never mistaken for
    /// one continuous list.
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }

    /// Fixed 3×2 grid (not "as many columns as fit") — a party is always exactly up to 6, so a
    /// stable grid reads as "your team" rather than a list that reflows as you add/remove picks.
    private func selectedRosterGrid(eligible: [MonState]) -> some View {
        let selected = eligible.filter { selectedMonIDs.contains($0.id) }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(0..<BattleClient.maxRosterSize, id: \.self) { slot in
                if slot < selected.count {
                    pcStyleTile(selected[slot], selected: true, size: 38)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .frame(height: 54)
                }
            }
        }
    }

    /// The rest of the party to pick from — a PC-box grid (sprite tiles), not the old list rows.
    private func partyGrid(eligible: [MonState]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
            ForEach(eligible) { mon in
                pcStyleTile(mon, selected: selectedMonIDs.contains(mon.id), size: 30)
            }
        }
    }

    private func pcStyleTile(_ mon: MonState, selected: Bool, size: CGFloat) -> some View {
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
        if selectedMonIDs.contains(id) {
            selectedMonIDs.remove(id)
        } else if selectedMonIDs.count < BattleClient.maxRosterSize {
            selectedMonIDs.insert(id)
        }
    }

    /// Everything `rosterPicker` (and only `rosterPicker`) owns as local `@State` — deliberately not
    /// `confirmingLink` (independently driven by `checkPendingInvite`, off `battle.pendingInvite`;
    /// clearing it here could race a genuinely still-pending cross-server invite confirmation).
    private func resetPickerState() {
        selectedMonIDs = []
        browseTarget = nil
        pickerStep = .chooseMode
        creatingNew = false
        pastedInviteLink = ""
        pastedInviteError = false
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
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(open.displayName).font(.system(size: 12, weight: .semibold))
                                            Spacer()
                                            Text(l.battleOpenRosterSize(open.rosterSize)).font(.caption2).foregroundStyle(.secondary)
                                        }
                                        HStack {
                                            // "X min ago", live-updating — the freshest lobby is usually
                                            // the right one when several share a display name (e.g. two
                                            // local test instances both named "Test P2").
                                            Text(Date(timeIntervalSince1970: open.createdAt / 1000), style: .relative)
                                                .font(.system(size: 9)).foregroundStyle(.tertiary)
                                            Spacer()
                                            // Last 4 chars of the session id — a stable tiebreaker when name
                                            // *and* age are both ambiguous (created within the same second).
                                            Text(open.sessionId.suffix(4)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                                        }
                                    }
                                    // Reinforces the whole row is tappable — matches modeChoiceButton's
                                    // same trailing-chevron affordance.
                                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                                }
                                .padding(8)
                                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1))
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
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(shareURL.absoluteString, forType: .string)
                        copiedFeedback = true
                        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copiedFeedback = false }
                    } label: {
                        Label(copiedFeedback ? l.tradeCopied : l.tradeCopyLink, systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            Button(l.tradeCancelButton) { Task { await battle.cancel() } }.buttonStyle(.borderless)
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
                battleScene(opponent: opponent, you: you, log: view.log)
                if view.status == "completed" {
                    battleOverHoldingBox
                } else {
                    // Tucked into the command box's own bottom-right corner, not floated over the
                    // scene — the corner up by the opponent's info card (its previous spot) read as
                    // if it belonged to their side, not a control for you.
                    actionBox(view, you: you)
                        .overlay(alignment: .bottomTrailing) { forfeitButton }
                }
            }
            .task(id: view.status) {
                guard view.status == "completed" else { revealResult = false; return }
                // Long enough for battleSprite's hit-flash (~0.28s) and the faint fade/tilt (0.35s)
                // to finish — see their .phaseAnimator/.animation durations.
                try? await Task.sleep(nanoseconds: 900_000_000)
                if !Task.isCancelled { revealResult = true }
            }
            // hostLeadSpeciesID is fixed for the whole battle (see its doc comment) — keyed on it
            // rather than something like view.turn so this only ever resolves once, not every poll.
            .task(id: view.hostLeadSpeciesID) {
                guard let speciesID = view.hostLeadSpeciesID else { return }
                let type = await companion.baseStats(speciesID: speciesID)?.types.first ?? .normal
                let terrain = Self.backgroundTerrain(for: type)
                battleBackgroundImage = Self.loadBackgroundImage(terrain: terrain)
            }
            // Log overlay first, buttons last — overlays stack in call order, and the toggle button
            // has to stay clickable on TOP of the log panel once it's open, or there's no way to
            // close it again.
            .overlay { if showMoveLog { moveLogOverlay(log: view.log ?? []) } }
            .overlay(alignment: .topTrailing) { moveLogToggleButton }
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

    private var moveLogToggleButton: some View {
        Button { showMoveLog.toggle() } label: {
            Image(systemName: showMoveLog ? "xmark.circle.fill" : "list.bullet.rectangle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.white, Color.black.opacity(0.35))
        }
        .buttonStyle(.plain)
        .padding(.top, 8).padding(.trailing, 8)
        .help(l.battleLogTitle)
    }

    /// Voluntary mid-battle exit — everywhere else `battle.cancel()` only ever fires once the battle
    /// is already over or never started (waiting screen, result screen, retry). This is the one path
    /// where a player can walk away from a battle that's still live, so it's the one path that gets a
    /// confirmation first — losing on purpose deserves a second tap, unlike backing out of a lobby.
    private var forfeitButton: some View {
        Button { confirmingForfeit = true } label: {
            Image(systemName: "flag.checkered")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 10).padding(.trailing, 10)
        .help(l.battleForfeitButton)
        .confirmationDialog(l.battleForfeitConfirmTitle, isPresented: $confirmingForfeit) {
            Button(l.battleForfeitButton, role: .destructive) { Task { await battle.cancel() } }
            Button(l.tradeCancelButton, role: .cancel) {}
        }
    }

    /// Off by default — the scene + action box already cover "what do I do now"; this is opt-in
    /// detail for "what actually happened", the raw @pkmn/sim log lightly reworded into sentences
    /// (formattedLogLines) rather than shown as raw protocol text.
    private func moveLogOverlay(log: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(l.battleLogTitle).font(.system(size: 13, weight: .semibold))
                .padding(10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(Self.formattedLogLines(log).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }

    /// Reworks the handful of @pkmn/sim log line kinds a casual player would care about into plain
    /// sentences; everything else (internal bookkeeping lines like |split|, |gametype|, |tier|) is
    /// dropped rather than shown as raw protocol text. Not exhaustive — an unhandled line kind is
    /// just omitted, not a functional problem for what's meant to be a readable recap.
    static func formattedLogLines(_ log: [String]) -> [String] {
        log.compactMap { line -> String? in
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 2 else { return nil }
            switch parts[1] {
            case "move": return parts.count >= 4 ? "\(shortMonName(parts[2])) used \(parts[3])!" : nil
            case "-damage": return parts.count >= 3 ? "\(shortMonName(parts[2])) took damage." : nil
            case "-heal": return parts.count >= 3 ? "\(shortMonName(parts[2])) recovered HP." : nil
            case "-boost": return parts.count >= 4 ? "\(shortMonName(parts[2]))'s \(parts[3]) rose!" : nil
            case "-unboost": return parts.count >= 4 ? "\(shortMonName(parts[2]))'s \(parts[3]) fell!" : nil
            case "-status": return parts.count >= 3 ? "\(shortMonName(parts[2])) was afflicted!" : nil
            case "faint": return parts.count >= 3 ? "\(shortMonName(parts[2])) fainted!" : nil
            case "win": return parts.count >= 3 ? "\(parts[2]) won the battle!" : nil
            case "tie": return "The battle ended in a draw."
            case "turn": return parts.count >= 3 ? "— Turn \(parts[2]) —" : nil
            default: return nil
            }
        }
    }

    /// "p1a: Ash-0" -> "Ash-0" — same identifier shape parseMoveEvents' identBelongsToMe reads.
    private static func shortMonName(_ ident: String) -> String {
        guard let colonRange = ident.range(of: ": ") else { return ident }
        return String(ident[colonRange.upperBound...])
    }

    private func battleScene(opponent: BattleClient.Opponent, you: BattleClient.You, log: [String]?) -> some View {
        let yourActive = you.roster[safeIndex: you.activeIndex]
        return ZStack {
            battleFieldBackground
            // chipStack is attached here, before the .frame(maxWidth: .infinity, ...) below — that
            // frame expands to the whole scene, so an .overlay attached *after* it (the original,
            // buggy placement) anchors to the scene's own bounds, not the box's actual small footprint,
            // landing both sides' chips at the same top-center spot regardless of which mon they're
            // for. Attached here, `.top`/`.bottom` alignment is relative to the compact card itself.
            pokemonInfoBox(name: opponent.displayName, active: opponent.active, benchCount: opponent.rosterSize)
                .overlay(alignment: .bottom) { chipStack(opponentChips).offset(y: 20) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
            // Kept clear of the action-box overlay below (extra bottom padding) — unlike the plain
            // sprite artwork, this card is information (name/HP) and must never be the thing that's
            // partly hidden.
            pokemonInfoBox(name: you.displayName, active: yourActive, benchCount: you.roster.count)
                .overlay(alignment: .top) { chipStack(yourChips).offset(y: -20) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.horizontal, 14).padding(.top, 14)
                .padding(.bottom, BattleWindowMetrics.actionBoxHeight + 10)
            battleSprite(speciesID: opponent.active?.speciesID, fainted: opponent.active?.fainted ?? false, size: 130, facing: .front, effect: opponentEffect)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 16).padding(.trailing, 28)
            // .back (the real games' own convention: you see your own mon from behind, the
            // opponent's face-on) and deliberately shallow bottom padding — its lower body is meant
            // to sit behind the action-box overlay the caller (battlingContent) draws in front of
            // this whole scene, the same way the real games' own message box covers the very bottom
            // of your Pokémon but never reaches the opponent's (too far up-screen to ever meet it).
            battleSprite(speciesID: yourActive?.speciesID, fainted: yourActive?.fainted ?? false, size: 170, facing: .back, effect: yourEffect)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.bottom, 130).padding(.leading, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        // Real max HP for whichever mon is active on our side — the opponent's equivalent is
        // permanently unknowable (their real stats are never sent to this client), but ours isn't;
        // recomputed whenever the active slot changes (a switch), not per-chip.
        .task(id: you.activeIndex) {
            guard let mon = battle.myRoster[safeIndex: you.activeIndex],
                  let base = await companion.baseStats(speciesID: mon.currentID) else {
                myActiveMaxHP = nil
                return
            }
            myActiveMaxHP = StatCalc.compute(base: base, ivs: mon.effectiveIVs, evs: mon.evs,
                                              level: mon.level, nature: mon.nature).hp
        }
        // A move landing has no explicit event from the server — only the log to compare turn over
        // turn — so every new line since we last looked is what drives this, not just ones that
        // happen to move an HP bar (status moves never do, but still did something real).
        .onChange(of: log) { _, newLog in
            guard let newLog else { return }
            let result = Self.parseLogBeats(from: newLog, previouslySeenCount: lastSeenLogCount, myDisplayName: you.displayName,
                                             l: l, hpFractions: &hpFractionsByIdent)
            lastSeenLogCount = result.seenCount
            // parseLogBeats can't know species names (a log identifier carries none — see
            // MoveLogEvent.userName's doc comment) or real HP numbers (a pure function has no access
            // to this side's stats) — both filled in here instead, from state this render has on hand.
            let resolvedBeats = result.beats.map { beat -> LogBeat in
                switch beat {
                case .move(var event):
                    event.userName = event.userIsMine ? yourActive?.name : opponent.active?.name
                    return .move(event)
                case .chip(var chip):
                    if chip.isMine, let frac = chip.hpDeltaFraction, let maxHP = myActiveMaxHP {
                        let delta = Int((frac * Double(maxHP)).rounded())
                        if delta != 0 { chip.text = "\(delta > 0 ? "+" : "")\(delta) HP" }
                    }
                    return .chip(chip)
                }
            }
            enqueueBeats(resolvedBeats)
        }
    }

    /// Queues new beats and, if nothing is currently playing, starts draining — the single point
    /// that guarantees at most one playback loop ever runs, so a poll landing mid-sequence can't
    /// spawn a second player racing the first (see `pendingBeats`'s doc comment for why that matters).
    private func enqueueBeats(_ beats: [LogBeat]) {
        pendingBeats.append(contentsOf: beats)
        guard !isPlayingBeats else { return }
        isPlayingBeats = true
        Task { await drainBeats() }
    }

    /// Plays queued beats strictly one at a time, in arrival order — the actual "moves happen one
    /// after another, server-decided" fix: the order is already correct (see `parseLogBeats`), this
    /// just paces playback to match instead of firing every beat in the batch at once.
    private func drainBeats() async {
        while !pendingBeats.isEmpty {
            let beat = pendingBeats.removeFirst()
            await play(beat)
            try? await Task.sleep(nanoseconds: 450_000_000)
        }
        isPlayingBeats = false
    }

    private func play(_ beat: LogBeat) async {
        switch beat {
        case .move(let event):
            showMoveUsedText(event)
            await triggerMoveEffect(event)
        case .chip(let chip):
            addEffectChip(chip)
        }
    }

    /// Shows the move-used text, then clears it after a beat rather than leaving it sitting there
    /// permanently once any move has ever landed — a message that appears and disappears draws the
    /// eye; one that never goes away just becomes part of the furniture. `moveTextGeneration` guards
    /// against a *later* move's text getting wiped by an *earlier* move's now-stale clear timer if
    /// two land close together. Falls back to the nameless template on the rare miss (a switch
    /// happening in the exact same log batch right before this move, or the active-mon lookup
    /// otherwise coming back empty) rather than showing a blank/broken subject.
    private func showMoveUsedText(_ event: MoveLogEvent) {
        recentMoveText = event.userName.map { l.battleUsedMoveByPokemon($0, event.moveName) } ?? l.battleUsedMove(event.moveName)
        moveTextGeneration += 1
        let generation = moveTextGeneration
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if moveTextGeneration == generation { recentMoveText = nil }
        }
    }

    /// Appends the chip to the right side's queue, then removes just that one after a beat — a list,
    /// not a single overwritten `@State`, because more than one can be visible at once (a chip from
    /// an earlier beat can still be fading while a later beat's chip appears).
    private func addEffectChip(_ chip: EffectChip) {
        if chip.isMine { yourChips.append(chip) } else { opponentChips.append(chip) }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if chip.isMine { yourChips.removeAll { $0.id == chip.id } }
            else { opponentChips.removeAll { $0.id == chip.id } }
        }
    }

    private func chipStack(_ chips: [EffectChip]) -> some View {
        VStack(spacing: 2) {
            ForEach(chips) { chip in
                Text(chip.text)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(chip.isPositive ? .green : .red)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: chips)
    }

    /// Resolves the move's real type (typeColor — the same palette move buttons already use) and
    /// damage class, then bumps the appropriate side's effect. companion.moveDetail(name:) checks
    /// the app-wide move cache by name before ever hitting the network, so this is free for a move
    /// this side already knows (already fetched for the move grid) and only a real fetch for a move
    /// only the opponent has ever used — a failed/unresolved lookup (an unusual name PokéAPI's own
    /// slug convention can't round-trip, e.g. one with an apostrophe) just plays the neutral default
    /// instead of a type color, not a functional break.
    private func triggerMoveEffect(_ event: MoveLogEvent) async {
        let move = await companion.moveDetail(name: event.moveName)
        let color = move.map { typeColor($0.type) } ?? .white
        let isDamaging = move?.damageClass != .status
        if event.targetIsMine {
            yourEffect = SpriteEffect(trigger: yourEffect.trigger + 1, color: color, isDamaging: isDamaging)
        } else {
            opponentEffect = SpriteEffect(trigger: opponentEffect.trigger + 1, color: color, isDamaging: isDamaging)
        }
    }

    /// Real pixel-art terrain (see `Resources/BattleBackgrounds`) once `battleBackgroundTask` has
    /// resolved one; the flat gradient this replaced is kept as the fallback for the gap before that
    /// resolves (or if it never does — offline, an unrecognized species). `.interpolation(.none)`
    /// keeps the art crisp when scaled — the default smooth interpolation blurs pixel art badly.
    @ViewBuilder
    private var battleFieldBackground: some View {
        if let battleBackgroundImage {
            // GeometryReader, not `.frame(maxWidth: .infinity, maxHeight: .infinity)` (tried first,
            // didn't fix it) — `aspectRatio(contentMode: .fill)` has to resolve its scale factor
            // against a *concrete* size. Handed `.infinity`, SwiftUI falls back to the image's own
            // native pixel size as its "ideal" size instead of the space it was actually given,
            // which is what stretched it and let it paint over everything else in the ZStack rather
            // than being correctly bounded to its slot. `geo.size` is always a real, finite number.
            GeometryReader { geo in
                Image(nsImage: battleBackgroundImage)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        } else {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.68, green: 0.85, blue: 0.95), location: 0.0),
                    .init(color: Color(red: 0.80, green: 0.91, blue: 0.97), location: 0.42),
                    .init(color: Color(red: 0.56, green: 0.76, blue: 0.42), location: 0.44),
                    .init(color: Color(red: 0.44, green: 0.66, blue: 0.36), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom)
        }
    }

    /// One terrain per type, not a 1:1 asset-per-type mapping — several types share a terrain
    /// (fighting/flying/rock/steel all read as "mountain", say) rather than force a thematic fit
    /// that isn't there. Dual-type mons use their primary type only (`BaseStats.types.first`) — a
    /// background is flavor, not worth blending two terrains over.
    static let backgroundTerrainByType: [PokemonType: String] = [
        .normal: "path", .electric: "path",
        .fighting: "mountain", .flying: "mountain", .rock: "mountain", .steel: "mountain",
        .poison: "cave", .ghost: "cave", .dragon: "cave", .dark: "cave",
        .ground: "desert", .fire: "desert",
        .psychic: "lake",
        .bug: "tall-grass", .grass: "tall-grass",
        .ice: "snow",
        .water: "ocean",
        .fairy: "beach",
    ]

    static func backgroundTerrain(for type: PokemonType) -> String {
        backgroundTerrainByType[type] ?? "path"
    }

    /// Loads a bundled battle background by terrain name (see `Package.swift`'s
    /// `.copy("Resources/BattleBackgrounds")` — `Bundle.module` is SwiftPM's generated accessor for
    /// it, working identically in the debug binary and the packaged release .app, unlike the
    /// `assets/` folder these were first dropped into, which only `AppIcon.icns` ever gets copied
    /// out of into a release build). A local bundled file, so this reads synchronously — no need for
    /// the async/cache machinery `SpriteLoader` needs for runtime-fetched sprites.
    static func loadBackgroundImage(terrain: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: terrain, withExtension: "png", subdirectory: "BattleBackgrounds")
        else { return nil }
        return NSImage(contentsOf: url)
    }

    /// A soft ground shadow under the sprite (real games ground their sprites on a battle platform)
    /// plus a fainted cue — real games have the sprite slide/drop off-screen; a 90° tilt is the
    /// cheapest approximation that still reads as "down" without an actual animation timeline.
    /// A real layout sibling below the sprite, not a ZStack + `.offset()` overlay — `.offset` moves
    /// pixels without changing what the layout system thinks the view's bounds are, so once the
    /// *outer* frame stretched to fill the whole scene (the fix for the previous overlap issue),
    /// the two drifted apart: the ellipse kept its intended position relative to the sprite's
    /// pre-offset bounds, not its actual on-screen position. A VStack ties them together for real —
    /// wherever this whole unit gets positioned, both move as one.
    private func battleSprite(speciesID: Int?, fainted: Bool, size: CGFloat, facing: SpriteFacing, effect: SpriteEffect) -> some View {
        VStack(spacing: -size * 0.16) {
            BattleSpriteFlash(speciesID: speciesID, size: size, facing: facing, effect: effect)
                .opacity(fainted ? 0.35 : 1)
                .rotationEffect(.degrees(fainted ? 90 : 0))
                // VStack paints children in declaration order just like ZStack does (later = front)
                // — with negative spacing pulling the two into overlap, the ellipse declared below
                // would otherwise paint on top of the sprite's overlapping lower portion. zIndex wins
                // paint order without touching layout (which still needs the sprite listed first, so
                // it's the one positioned on top).
                .zIndex(1)
            Ellipse()
                .fill(Color.black.opacity(0.16))
                .frame(width: size * 0.85, height: size * 0.24)
        }
        .animation(.easeInOut(duration: 0.35), value: fainted)
    }

    /// A fixed max width, not just `.frame(maxWidth: .infinity, alignment:)` at the call site — an
    /// `HStack` with a `Spacer` inside an unconstrained parent expands to fill whatever space it's
    /// offered, which is the *entire scene width* once the call site's own alignment frame spans the
    /// full window. Bounding the card itself keeps it a compact card; the call site's frame still
    /// positions that bounded card wherever it wants within the larger area.
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
        .frame(maxWidth: 190)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.22), radius: 3, y: 2))
    }

    private func actionBox(_ view: BattleClient.BattleView, you: BattleClient.You) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Confirms a status move actually did something — without this, Growl/Tail Whip/String
            // Shot (never move an HP bar, so no hit-flash either) look completely unresponsive even
            // though the server already applied them. Sized/weighted like the real games' own
            // battle text (not a small secondary caption easy to miss next to the move grid below
            // it), and self-clearing (showMoveUsedText) so it reads as an announcement, not a static
            // label permanently sitting there once any move has ever landed.
            if let recentMoveText {
                Text(recentMoveText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .transition(.opacity)
            }
            if voluntarySwitchOpen {
                switchStrip(you.roster, activeIndex: you.activeIndex, forced: false)
            } else if view.pendingChoice == "switch" {
                VStack(alignment: .leading, spacing: 6) {
                    Text(l.battleForcedSwitchPrompt).font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                    switchStrip(you.roster, activeIndex: you.activeIndex, forced: true)
                }
            } else if view.pendingChoice == "move" {
                moveGrid(you: you, turn: view.turn)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(l.battleWaitingOnOpponentToChooseMove(view.opponent?.displayName ?? "")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: recentMoveText)
        .padding(BattleWindowMetrics.padding)
        .frame(maxWidth: .infinity, minHeight: BattleWindowMetrics.actionBoxHeight, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.secondary.opacity(0.3)), alignment: .top)
    }

    private func moveGrid(you: BattleClient.You, turn: Int) -> some View {
        Group {
            if let mon = battle.myRoster[safeIndex: you.activeIndex] {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l.battleWaitingOnYouToChooseMove).font(.system(size: 12, weight: .semibold))
                    BattleMoveGrid(store: companion, mon: mon, turn: turn) { slot in
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
        // Color-codes the outcome at a glance, matching HPBar's own green/red vocabulary elsewhere
        // on this screen — a plain uncolored title left the win/loss distinction to reading text only.
        let (icon, tint): (String, Color) = switch view.result {
        case "win": ("trophy.fill", .green)
        case "loss": ("xmark.circle.fill", .red)
        default: ("equal.circle.fill", .secondary)
        }
        return VStack {
            Spacer()
            // A solid, theme-adaptive card — not colored text sitting directly on the light pastel
            // sky/grass gradient behind it, which read as low-contrast (green title text over a
            // green-tinted background especially). Same fix pokemonInfoBox/actionBox already use for
            // the same underlying problem: guarantee contrast against a busy/variable background by
            // putting text on a solid surface instead. The icon alone keeps the win/loss tint — a
            // small shape reads fine in color; a whole line of text needs the safer `.primary`.
            VStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 36)).foregroundStyle(tint)
                Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(.primary)
                Button(l.battleDoneButton) { Task { await battle.cancel() }; onClose() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(28)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
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
                Button(l.tradeTryAgainButton) { Task { await battle.cancel() } }.buttonStyle(.bordered)
            }
        }
    }
}

private extension Array {
    subscript(safeIndex index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// The hit-flash (shake+color for a damaging move, a gentler pulse+glow for a status move) as its
/// own view with its own `@State`, driven by an explicit `.onChange(of: effect.trigger)` + a timed
/// reset — not a `.phaseAnimator` wrapping `SpriteView` directly.
///
/// [Regression] `.phaseAnimator` was the original approach here, and it worked until animated (GIF)
/// sprites were turned on — after that, the flash would reliably get stuck on its "active" phase for
/// one side (reported as "the darkening effect... stays dark" and never clears). `SpriteView`'s own
/// animated-GIF path re-renders its content on its own timer (a new frame, independent of anything
/// this view does); `.phaseAnimator` expects to own the content identity it's driving through phases,
/// so a wrapped view that's *also* mutating itself on its own schedule can desync the phase sequence
/// from its content, and it can get stuck on whichever phase was active when that happened instead of
/// completing back to the neutral one. Driving `isFlashing` by hand — set on trigger, always cleared
/// by an awaited sleep on the same Task, no dependency on an animation "finishing" — can't get stuck
/// this way: the reset always runs regardless of what the wrapped content does in between.
private struct BattleSpriteFlash: View {
    let speciesID: Int?
    let size: CGFloat
    let facing: SpriteFacing
    let effect: BattleView.SpriteEffect

    @State private var isFlashing = false
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        SpriteView(speciesID: speciesID, size: size, animated: true, facing: facing)
            .offset(x: shakeOffset)
            .scaleEffect(isFlashing && !effect.isDamaging ? 1.07 : 1.0)
            .colorMultiply(isFlashing ? effect.color : .white)
            .animation(.easeInOut(duration: 0.09), value: isFlashing)
            .animation(.easeInOut(duration: 0.09), value: shakeOffset)
            .onChange(of: effect.trigger) { _, _ in
                Task { await runFlash() }
            }
    }

    private func runFlash() async {
        isFlashing = true
        if effect.isDamaging {
            shakeOffset = -7
            try? await Task.sleep(nanoseconds: 90_000_000)
            shakeOffset = 7
            try? await Task.sleep(nanoseconds: 90_000_000)
            shakeOffset = 0
        } else {
            try? await Task.sleep(nanoseconds: 180_000_000)
        }
        isFlashing = false
    }
}

/// A mon's up-to-4 known moves as tappable buttons — loaded from `CompanionStore.moveDetail`, the
/// same source the PC detail screen's known-move list already uses. Local data only (see
/// `BattleStore.myRoster`'s doc comment for why the server's own response can't supply this).
private struct BattleMoveGrid: View {
    let store: CompanionStore
    let mon: MonState
    /// Only used to reset `selectedSlot` between turns (see .onChange below) — the active mon
    /// usually stays the same across several turns in a row, so keying the reset on `mon.id` alone
    /// would leave the previous turn's highlight stuck showing on a move you already used.
    let turn: Int
    let onChoose: (Int) -> Void

    @State private var moves: [Move?] = []
    /// Set the instant a move is tapped — immediate feedback while the request round-trips, rather
    /// than the button looking completely inert until the next poll shows something changed.
    @State private var selectedSlot: Int?

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(Array(mon.knownMoves.enumerated()), id: \.offset) { index, moveID in
                let move = moves[safeIndex: index] ?? nil
                let slot = index + 1
                Button {
                    selectedSlot = slot
                    onChoose(slot)
                } label: {
                    HStack(spacing: 6) {
                        Text(move?.localizedName(store.language) ?? "#\(moveID)")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        if let move {
                            Text("\(store.l.battlePP) \(move.pp)")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
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
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedSlot != nil && selectedSlot != slot)
                // On the button itself, not nested inside the label content — that inner rectangle
                // never actually lined up with the real button chrome `.buttonStyle(.bordered)`
                // draws (different padding/corner radius), so it read as an outline on some random
                // inner box, not on the move button itself. A green outline on the chosen move, not a
                // filled background — a solid fill reads as heavy/blocky at this size and swallows
                // the PP/type-badge text's own color underneath it.
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(selectedSlot == slot ? Color.green : Color.clear, lineWidth: 2))
            }
        }
        .task(id: mon.id) {
            var loaded: [Move?] = []
            for id in mon.knownMoves { loaded.append(await store.moveDetail(id: id)) }
            moves = loaded
        }
        .onChange(of: turn) { selectedSlot = nil }
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
