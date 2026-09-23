import SwiftUI

/// Fixed content size for the standalone trade window (`TradeWindowController`) — same reasoning as
/// `BattleWindowMetrics`: this screen used to live in the 360pt popover strip, but a multi-mon
/// roster grid + token stake needs real screen real estate, not a cramped strip. Sized close to
/// `BattleWindowMetrics` (520×460) so the two windows read as the same app, not two different sizes
/// for no reason — a little taller since the offer step stacks one more row (the token stake card)
/// than battle's roster-pick step does.
enum TradeWindowMetrics {
    static let width: CGFloat = 520
    static let height: CGFloat = 520
    static let padding: CGFloat = 14
}

/// Trade screen — same full-content-swap pattern as Settings/Battle (NOTE: see PopoverView's
/// reasoning for avoiding .sheet). Hosted in its own window (`TradeWindowController`), not the
/// popover, for the same reason `BattleView` moved out of it — see that type's doc comment.
///
/// Create/join/browse, matching `BattleView`'s picker flow shape and visual vocabulary end to end
/// (trading-overhaul.md + visual-style.md) — browse leads, a link is the backup path, and the offer
/// picker is multi-mon + a token stake instead of the old single-mon pick.
struct TradeView: View {
    @Environment(CompanionStore.self) private var companion
    @Environment(TradeStore.self) private var trade
    @Environment(OnlineStore.self) private var online
    var onClose: () -> Void

    /// Ordered, not a `Set` — same "pick order, not PC order" reasoning as BattleView's
    /// `selectedMonIDs`; `RosterPickerGrid`'s own drag reordering mutates this array directly.
    @State private var selectedMonIDs: [MonState.ID] = []
    /// Free-typed, clamped on every edit (see `clampTokenStakeText`) rather than a `Stepper` —
    /// balances here run into the hundreds of millions, where a +/- stepper is useless.
    @State private var tokenStakeText = "0"
    @State private var confirmingLink: TradeDeepLink?
    @State private var copiedFeedback = false
    @State private var pastedInviteLink = ""
    @State private var pastedInviteError = false
    /// Resolved names for mons shown by id — `offerTile` falls back to `companion.speciesName`
    /// (instant, but only real for an already-owned species) until this fills in from
    /// `CompanionStore.resolvedSpeciesName`'s network lookup, needed for a trade counterpart's
    /// species before their offer actually completes.
    @State private var resolvedNames: [String: String] = [:]
    /// Which screen of the "how do you want to start" flow is showing — same shape as
    /// `BattleView.PickerStep`.
    private enum PickerStep { case chooseMode, pasteLink, browseList }
    @State private var pickerStep: PickerStep = .chooseMode
    /// Set when the user picks "Start trade" from the mode chooser — see BattleView's
    /// `creatingNew` for why this is distinct from "still choosing how to start."
    @State private var creatingNew = false
    /// A session picked from the open-lobby list — the browse-path equivalent of
    /// `trade.pendingInvite` (a deep link). Both converge on the same offer picker → `joinTrade` call.
    @State private var browseTarget: (sessionId: String, server: String)?

    private var l: L { companion.l }

    private var joinTarget: (sessionId: String, server: String)? {
        if let invite = trade.pendingInvite { return (invite.sessionId, invite.server) }
        return browseTarget
    }

    private var tokenStake: Int { Int(tokenStakeText.filter(\.isNumber)) ?? 0 }

    var body: some View {
        content
        .padding(TradeWindowMetrics.padding)
        .frame(width: TradeWindowMetrics.width, height: TradeWindowMetrics.height, alignment: .top)
        .task { checkPendingInvite() }
        .onChange(of: trade.pendingInvite) { checkPendingInvite() }
        .alert(l.tradeJoinButton, isPresented: Binding(get: { confirmingLink != nil }, set: { if !$0 { declineInvite() } }),
               presenting: confirmingLink) { link in
            Button(l.tradeJoinButton) { online.serverURL = link.server; confirmingLink = nil }
            // Declining must drop the invite itself, not just the alert. Clearing `confirmingLink`
            // alone left `trade.pendingInvite` set, and the picker below reads that directly — so
            // the join screen stayed up, pointed at the very server the user just refused.
            Button(l.tradeCancelButton, role: .cancel) { declineInvite() }
        } message: { link in
            Text(online.serverURL.isEmpty
                 ? l.tradeConnectServerConfirm(link.server)
                 : l.tradeDifferentServerConfirm(link.server))
        }
    }

    /// Checks an invite that arrived via deep link and confirms the server before anything is
    /// offered to it.
    ///
    /// The only case that needs no prompt is an invite for the server the user already chose.
    /// Everything else asks, **including the no-server-configured case** — that is the default
    /// state of a fresh install, and it used to fall straight through to the join screen. A
    /// `poketokenbar://` link can be opened by any web page, so skipping the prompt there meant a
    /// page could put the user one click away from offering a Pokémon, their display name and
    /// their client id to a host they never chose and were never shown.
    private func checkPendingInvite() {
        guard let link = trade.pendingInvite else { return }
        if !online.serverURL.isEmpty, sameServer(online.serverURL, link.server) {
            return   // already the server the user picked — the picker renders join mode directly
        }
        confirmingLink = link
    }

    private func declineInvite() {
        confirmingLink = nil
        trade.declineInvite()
    }

    /// Maps the status codes the server actually documents (see PokeTokenBarOnline's /docs) to
    /// localized copy; anything else (network errors, decoding, unexpected codes) falls back to the
    /// generic title — better than dumping a raw Swift enum on someone who's not a developer.
    private func friendlyMessage(for error: TradeClient.TradeError) -> String {
        switch error {
        case .server(status: 401): return l.tradeAuthErrorMessage
        case .server(status: 400): return l.tradeInvalidOfferMessage
        case .server(status: 403): return l.tradeNotParticipantMessage
        case .server(status: 409): return l.tradeConflictMessage
        default: return "\(l.tradeFailedTitle): \(String(describing: error))"
        }
    }

    /// Mirrors the server's own offer validation (trades.ts: non-empty, ≤60 chars) so a missing
    /// display name is caught here instead of round-tripping to a 400.
    private var hasValidDisplayName: Bool {
        (1...60).contains(online.displayName.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }

    private func sameServer(_ a: String, _ b: String) -> Bool {
        guard let ua = OnlineStore.endpointURL(from: a, path: "/"),
              let ub = OnlineStore.endpointURL(from: b, path: "/") else { return false }
        return ua.host == ub.host && ua.port == ub.port
    }

    @ViewBuilder
    private var content: some View {
        switch trade.phase {
        case .idle:
            picker.onAppear { resetPickerState() }
        case .waitingForJoin(let sessionId, let shareURL):
            waitingForJoin(sessionId: sessionId, shareURL: shareURL)
        case .waitingForCounterpart:
            statusView(message: l.tradeWaitingForCounterpart, showsSpinner: true)
        case .reviewingCounterpart(_, let counterpart):
            reviewCounterpart(counterpart)
        case .confirmed(_, let counterpart):
            confirmedWaiting(counterpart)
        case .completed(let received, let tokens, let from):
            completedView(received: received, tokens: tokens, from: from)
        case .failed(let error):
            statusView(message: friendlyMessage(for: error), showsSpinner: false, showsRetry: true)
        case .expired:
            statusView(message: l.tradeExpiredTitle, showsSpinner: false, showsRetry: true)
        }
    }

    // MARK: Picking how to start — same 3-step shape as BattleView.rosterPicker

    @ViewBuilder
    private var picker: some View {
        if let target = joinTarget {
            offerPickStep(target: target)
        } else if creatingNew {
            offerPickStep(target: nil)
        } else {
            switch pickerStep {
            case .chooseMode: modeChooserStep
            case .pasteLink: pasteLinkStep
            case .browseList: browseListStep
            }
        }
    }

    /// Step 1: how to start. Browse leads — it's the primary way to find a trade to join, not one of
    /// three equally-weighted options; see `battleBrowseSubtitle`'s equivalent note for why a direct
    /// invite link stays a full card rather than a demoted text button.
    private var modeChooserStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l.tradeStartPrompt).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            modeChoiceButton(title: l.tradeBrowseOpen, subtitle: l.tradeBrowseSubtitle,
                              icon: "magnifyingglass", tint: .orange) {
                pickerStep = .browseList
                Task { await trade.refreshOpenTrades() }
            }
            modeChoiceButton(title: l.tradeCreateButton, subtitle: l.tradeCreateSubtitle,
                              icon: "plus.circle.fill", tint: .accentColor) {
                creatingNew = true
            }
            modeChoiceButton(title: l.tradeJoinViaLinkButton, subtitle: l.tradeJoinViaLinkSubtitle,
                              icon: "link", tint: .blue) {
                pickerStep = .pasteLink
            }
        }
    }

    /// Same card chrome (12pt radius, `Color.secondary.opacity(0.07)` fill + hairline border)
    /// `BattleView.modeChoiceButton` uses — icon badge + bold title + one-line subtitle + trailing
    /// chevron, per visual-style.md's "mode choice button pattern."
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

    /// Step 2a: paste a link — same icon-badge-card shape as `BattleView.pasteLinkStep`.
    private var pasteLinkStep: some View {
        VStack(spacing: 16) {
            backButton.frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .blue.opacity(0.3), radius: 8, y: 3)
                Text(l.tradePasteLinkPrompt).font(.system(size: 16, weight: .bold))
                    .padding(.top, 6)
                Text(l.tradeJoinViaLinkSubtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            pasteInviteCard
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Same shape as `BattleView.pasteInviteCard` — a custom-styled field (not the plain system
    /// `.roundedBorder`) plus a one-tap paste-from-clipboard button.
    private var pasteInviteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "link").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                TextField(l.tradePasteInviteLinkPlaceholder, text: $pastedInviteLink)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit(submitPastedInviteLink)
                Button {
                    if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !clip.isEmpty {
                        pastedInviteLink = clip
                        pastedInviteError = false
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .help(l.battlePasteFromClipboardHelp)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))

            if pastedInviteError {
                Label(l.tradeInvalidInviteLink, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.red)
            }
            Button(l.tradeJoinButton, action: submitPastedInviteLink)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(pastedInviteLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .frame(maxWidth: 360, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    private func submitPastedInviteLink() {
        guard let link = TradeDeepLink(pastedText: pastedInviteLink) else {
            pastedInviteError = true
            return
        }
        pastedInviteError = false
        pastedInviteLink = ""
        trade.handleIncomingLink(link)
    }

    // MARK: Step 2b: browse — same structure as BattleView.openBattlesList (no watch tab; trading
    // has nothing to spectate).

    private var browseListStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            backButton
            Text(l.tradeBrowsePrompt).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            openTradesList
        }
    }

    private var openTradesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if trade.isLoadingOpenTrades && trade.openTrades.isEmpty {
                browseStatus(showsSpinner: true, icon: nil, text: nil)
            } else if trade.openTrades.isEmpty {
                browseStatus(showsSpinner: false, icon: "tray", text: l.tradeNoOpenTrades)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(trade.openTrades, id: \.sessionId) { open in
                            openTradeRow(open)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            Button { Task { await trade.refreshOpenTrades() } } label: {
                if trade.isLoadingOpenTrades && !trade.openTrades.isEmpty {
                    Label(l.refresh, systemImage: "arrow.clockwise").opacity(0.5)
                } else {
                    Label(l.refresh, systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless).controlSize(.small)
            .disabled(trade.isLoadingOpenTrades)
        }
    }

    /// Same centered placeholder shape as `BattleView.browseStatus`.
    private func browseStatus(showsSpinner: Bool, icon: String?, text: String?) -> some View {
        VStack(spacing: 8) {
            if showsSpinner {
                ProgressView().controlSize(.small)
            } else if let icon {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(.tertiary)
            }
            if let text {
                Text(text).font(.system(size: 12)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openTradeRow(_ open: TradeClient.OpenTrade) -> some View {
        Button {
            browseTarget = (open.sessionId, online.serverURL)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(open.displayName).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        // Same "×N Pokémon" phrasing battles.md's own lobby row already uses —
                        // reused as-is (generic enough for either kind of offer).
                        if !open.pokemon.isEmpty {
                            Text(l.battleOpenRosterSize(open.pokemon.count)).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        if open.tokens > 0 {
                            Text("+\(TokenFormatter.compact(open.tokens))").font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
                        }
                    }
                    HStack {
                        Text(Date(timeIntervalSince1970: open.createdAt / 1000), style: .relative)
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                        Spacer()
                        Text(open.sessionId.suffix(4)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var backButton: some View {
        Button(action: { pickerStep = .chooseMode }) {
            Label(l.back, systemImage: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.borderless)
    }

    private func exitOfferPick() {
        browseTarget = nil
        declineInvite()
        creatingNew = false
        pickerStep = .chooseMode
    }

    // MARK: Step 3: offer — multi-mon (RosterPickerGrid) + a token stake, shared by create and join.

    private func offerPickStep(target: (sessionId: String, server: String)?) -> some View {
        let candidates = companion.benchedParty.filter { !trade.reservedMonIDs.contains($0.id) }
        return VStack(alignment: .leading, spacing: 8) {
            Button(action: exitOfferPick) {
                Label(l.back, systemImage: "chevron.left").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            Text(target != nil ? l.tradeJoinPrompt(target!.server) : l.tradePickOffer)
                .font(.caption).foregroundStyle(.secondary)
            if !hasValidDisplayName {
                Text(l.tradeDisplayNameRequired).font(.caption2).foregroundStyle(.orange)
            }
            // Unlike battling, an empty PC doesn't block this screen — a tokens-only offer (no
            // Pokémon at all) is valid by construction (trading-overhaul.md), so the submit button
            // below stays reachable either way.
            if candidates.isEmpty {
                Text(l.tradeNoBenchedMons).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                RosterPickerGrid(companion: companion, eligible: candidates, maxCount: TradeClient.maxOfferSize,
                                  selectedIDs: $selectedMonIDs, teamLabel: l.tradeYourOffer, poolLabel: l.battleYourParty)
                    .frame(maxHeight: .infinity)
            }
            tokenStakeCard
            Button {
                let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
                let offering = selectedMonIDs.compactMap { byID[$0] }
                let tokens = tokenStake
                Task {
                    if let target {
                        await trade.joinTrade(sessionId: target.sessionId, server: target.server, offering: offering, tokens: tokens)
                    } else {
                        await trade.createTrade(offering: offering, tokens: tokens)
                    }
                }
            } label: {
                Text(target != nil ? l.tradeJoinButton : l.tradeCreateButton)
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled((selectedMonIDs.isEmpty && tokenStake == 0) || !hasValidDisplayName)
        }
    }

    /// Bounded numeric field, clamped client-side to the sender's own current balance — same trust
    /// level as everything else self-reported here (nothing stops a hand-edited save from lying,
    /// same as today — trading-overhaul.md's "Open decisions"). Two rows, not one — a fixed-width
    /// field on the same line as the label/balance/Max button clipped once grouped commas made it
    /// long ("190,600,000"); the field now gets the full card width on its own row, with a compact
    /// "≈121M" readout beside the digits so the scale of a long grouped number is still legible at
    /// a glance.
    private var tokenStakeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.tradeTokenStakeLabel).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    // Grouped, not compact — sits right above the stake field, which is also
                    // grouped now; an abbreviated "190.6M" balance next to a precise "190,600,000"
                    // stake read as two different numbers at a glance.
                    Text(l.tradeTokenStakeAvailable(TokenFormatter.grouped(companion.availableTokens)))
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Spacer()
                Button(l.tradeTokenStakeMaxButton) { tokenStakeText = TokenFormatter.grouped(companion.availableTokens) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            // Its own bordered field box — same field chrome `pasteInviteCard` uses — instead of a
            // borderless TextField floating in the outer card, so the input itself reads as a
            // control, not inert text.
            HStack(spacing: 8) {
                TextField("0", text: $tokenStakeText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .onChange(of: tokenStakeText) { clampTokenStakeText() }
                if tokenStake > 0 {
                    Text(TokenFormatter.compact(tokenStake))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    /// Reformats with thousands separators on every keystroke — balances here run into the hundreds
    /// of millions/billions, where a bare digit string is easy to miscount (trading-overhaul.md's
    /// worked example is literally "+250,000,000 tokens"). Idempotent (stripping commas back out of
    /// an already-grouped string reproduces the same value), so this converges in one extra
    /// `onChange` bounce rather than looping.
    private func clampTokenStakeText() {
        let digits = tokenStakeText.filter(\.isNumber)
        let value = min(Int(digits) ?? 0, companion.availableTokens)
        tokenStakeText = TokenFormatter.grouped(value)
    }

    /// Everything `picker` (and only `picker`) owns as local `@State` — deliberately not
    /// `confirmingLink` (independently driven by `checkPendingInvite`, off `trade.pendingInvite`;
    /// clearing it here could race a genuinely still-pending cross-server invite confirmation).
    private func resetPickerState() {
        selectedMonIDs = []
        tokenStakeText = "0"
        browseTarget = nil
        pickerStep = .chooseMode
        creatingNew = false
        pastedInviteLink = ""
        pastedInviteError = false
    }

    // MARK: Waiting / sharing

    /// Same centered-with-invite-card shape as `BattleView.waitingForOpponent`/`waitingInviteCard`.
    private func waitingForJoin(sessionId: String, shareURL: URL?) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                ProgressView().controlSize(.regular)
                Text(l.tradeWaitingForJoin).font(.system(size: 15, weight: .semibold))
            }
            if let shareURL {
                waitingInviteCard(sessionId: sessionId, shareURL: shareURL)
            }
            Spacer(minLength: 0)
            Button(l.tradeCancelButton) { trade.cancel() }.buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func waitingInviteCard(sessionId: String, shareURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(l.tradeTitle.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).tracking(0.5)
                Text(sessionId.suffix(4).uppercased())
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
            }
            Text(l.tradeWaitingHelpText).font(.system(size: 11)).foregroundStyle(.secondary)
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
        .padding(14)
        .frame(maxWidth: 340, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    // MARK: Reviewing the counterpart's offer

    /// Side by side, not counterpart-only — "your offer" resolved against `companion.party` by id
    /// (`trade.myOfferedMonIDs`; the mons are still yours until the trade actually completes) next
    /// to the counterpart's, so both sides of the trade are comparable at a glance instead of
    /// trusting memory of what you picked two screens ago. Shared with `confirmedWaiting` — the same
    /// comparison stays visible after confirming, not swapped for a bare spinner.
    private func offerComparison(_ counterpart: TradeStore.Offer) -> some View {
        let myOffer = trade.myOfferedMonIDs.compactMap { id in companion.party.first { $0.id == id } }
        return HStack(alignment: .top, spacing: 12) {
            offerColumn(label: l.tradeYourOffer, mons: myOffer, tokens: trade.myOfferedTokens)
            Divider()
            offerColumn(label: l.tradeTheirOffer, mons: counterpart.pokemon, tokens: counterpart.tokens)
        }
        // My own mons resolve instantly (already owned); the counterpart's usually don't — this is
        // the one place that actually needs CompanionStore.resolvedSpeciesName's network fallback.
        .task { await ensureNamesResolved(myOffer + counterpart.pokemon) }
    }

    private func ensureNamesResolved(_ mons: [MonState]) async {
        for mon in mons where resolvedNames[mon.id] == nil {
            resolvedNames[mon.id] = await companion.resolvedSpeciesName(baseID: mon.baseID, currentID: mon.currentID)
        }
    }

    private func reviewCounterpart(_ counterpart: TradeStore.Offer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l.tradeReviewOffer(counterpart.displayName)).font(.caption).foregroundStyle(.secondary)
            offerComparison(counterpart)
            HStack {
                Button(l.tradeConfirmButton) { Task { await trade.confirm() } }
                    .buttonStyle(.borderedProminent)
                Button(l.tradeCancelButton) { trade.cancel() }
                    .buttonStyle(.borderless)
            }
        }
    }

    /// I've confirmed; the counterpart hasn't yet — same comparison as `reviewCounterpart`, so the
    /// screen doesn't jump to a bare "waiting" spinner and lose what you're about to receive, plus a
    /// visible "you confirmed" state (the whole point of this phase existing — see `TradeStore.Phase
    /// .confirmed`'s doc comment) and a real way out: `backOut()` actually tells the server, unlike
    /// a plain `cancel()` here which would leave the server still holding this side's confirmation.
    private func confirmedWaiting(_ counterpart: TradeStore.Offer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(.green)
                Text(l.tradeYouConfirmedWaiting).font(.caption).foregroundStyle(.secondary)
            }
            offerComparison(counterpart)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Button(l.tradeCancelButton) { Task { await trade.backOut() } }
                    .buttonStyle(.borderless)
            }
        }
    }

    /// One side of the your-offer/their-offer comparison — a fixed 3×2 grid (always all 6 slots,
    /// same shape `RosterPickerGrid`'s team grid uses for *picking*, here just for *display*: empty
    /// dashed slots for whatever wasn't offered, not a reflowing list) plus the token line below.
    private func offerColumn(label: String, mons: [MonState], tokens: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).tracking(0.5)
            offerGrid(mons)
            if tokens > 0 {
                tokenDeltaRow(tokens)
            } else if mons.isEmpty {
                Text("—").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `slots` fixed at `TradeClient.maxOfferSize` for the your-offer/their-offer comparison — both
    /// columns line up tile-for-tile even when one side offered fewer. `completedView` instead
    /// passes exactly `received.count`: a single lonely tile padded out to a 6-slot grid on its own
    /// result card read as sparse with no second column to justify the empty dashed slots. Display-
    /// only either way (no tap/drag, unlike `RosterPickerGrid`'s picker version of this same tile).
    private func offerGrid(_ mons: [MonState], slots: Int = TradeClient.maxOfferSize) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(0..<slots, id: \.self) { slot in
                if slot < mons.count {
                    offerTile(mons[slot])
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .frame(height: 58)   // matches the taller tile now that it carries a name line too
                }
            }
        }
    }

    private func offerTile(_ mon: MonState) -> some View {
        VStack(spacing: 1) {
            SpriteView(speciesID: mon.currentID, size: 28, shiny: mon.isShiny)
            // Instant fallback (own mon, or a species already seen elsewhere) until/unless
            // `ensureNamesResolved` fills in a real name for a counterpart's unseen species.
            Text(resolvedNames[mon.id] ?? companion.speciesName(mon.currentID))
                .font(.system(size: 8, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(companion.l.pcLevel(mon.level)).font(.system(size: 7)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func tokenDeltaRow(_ tokens: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.hexagongrid.fill").font(.system(size: 12)).foregroundStyle(.orange)
            Text(l.tradeTokenDelta(TokenFormatter.grouped(tokens))).font(.system(size: 12, weight: .semibold))
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Completed / status messages

    /// Same result-card shape `BattleView.resultView` uses — icon badge + bold title, a solid
    /// theme-adaptive card (not text floating directly on the window background), centered with
    /// `Spacer`s, one full-size primary action. The old version was a bare left-aligned list with no
    /// visual weight at all for what's meant to be the payoff screen of the whole flow.
    private func completedView(received: [MonState], tokens: Int, from: String) -> some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36)).foregroundStyle(.green)
                Text(l.tradeCompletedTitle).font(.system(size: 22, weight: .bold)).foregroundStyle(.primary)
                Text(l.tradeCompletedSummary(from)).font(.system(size: 12)).foregroundStyle(.secondary)
                if !received.isEmpty || tokens > 0 {
                    VStack(spacing: 10) {
                        if !received.isEmpty { offerGrid(received, slots: received.count) }
                        if tokens > 0 { tokenDeltaRow(tokens) }
                    }
                    .frame(maxWidth: 320)
                }
                Button(l.tradeDoneButton) { trade.cancel(); onClose() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(28)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusView(message: String, showsSpinner: Bool, showsRetry: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if showsSpinner { ProgressView().controlSize(.small) }
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if showsRetry {
                Button(l.tradeTryAgainButton) { trade.cancel() }.buttonStyle(.bordered)
            }
        }
    }
}
