import SwiftUI

/// Trade screen — same full-content-swap pattern as Settings (NOTE: see PopoverView's reasoning
/// for avoiding .sheet). Kept as its own screen rather than crammed into a 5th segmented tab for
/// the same reason — the 360pt-wide segment bar is already tight.
struct TradeView: View {
    @Environment(CompanionStore.self) private var companion
    @Environment(TradeStore.self) private var trade
    @Environment(OnlineStore.self) private var online
    var onClose: () -> Void

    @State private var selectedMonID: MonState.ID?
    @State private var confirmingLink: TradeDeepLink?
    @State private var copiedFeedback = false
    @State private var pastedInviteLink = ""
    @State private var pastedInviteError = false

    private var l: L { companion.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .padding(PopoverMetrics.padding)
        .frame(width: PopoverMetrics.width)
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

    private var header: some View {
        HStack {
            Button { onClose() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            Text(l.tradeTitle).font(.callout.weight(.semibold))
            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch trade.phase {
        case .idle:
            if let link = trade.pendingInvite {
                offerPicker(joining: link)
            } else {
                offerPicker(joining: nil)
            }
        case .waitingForJoin(_, let shareURL):
            waitingForJoin(shareURL: shareURL)
        case .waitingForCounterpart:
            statusView(message: l.tradeWaitingForCounterpart, showsSpinner: true)
        case .reviewingCounterpart(_, let counterpart):
            reviewCounterpart(counterpart)
        case .completed(let received, let from):
            completedView(received: received, from: from)
        case .failed(let error):
            statusView(message: friendlyMessage(for: error), showsSpinner: false, showsRetry: true)
        case .expired:
            statusView(message: l.tradeExpiredTitle, showsSpinner: false, showsRetry: true)
        }
    }

    // MARK: Picking a mon

    private func offerPicker(joining link: TradeDeepLink?) -> some View {
        let candidates = companion.benchedParty.filter { !trade.reservedMonIDs.contains($0.id) }
        return VStack(alignment: .leading, spacing: 8) {
            if let link {
                Text(l.tradeJoinPrompt(link.server)).font(.caption).foregroundStyle(.secondary)
            } else {
                pasteInviteRow
            }
            if !hasValidDisplayName {
                Text(l.tradeDisplayNameRequired).font(.caption2).foregroundStyle(.orange)
            }
            Text(l.tradePickOffer).font(.caption).foregroundStyle(.secondary)
            if candidates.isEmpty {
                Text(l.tradeNoBenchedMons).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(candidates) { mon in
                            TradeOfferRow(store: companion, mon: mon, isSelected: mon.id == selectedMonID) {
                                selectedMonID = mon.id
                            }
                        }
                    }
                }
                // Fixed height, not maxHeight — same fix as Bag/Shop/Collection: a ScrollView sized by
                // maxHeight reports an unstable fitting size on a fresh mount (e.g. Cancel remounting
                // this picker), which leaves the popover stuck at the wrong size instead of resizing
                // to fit.
                .frame(height: 300)
                Button(link != nil ? l.tradeJoinButton : l.tradeCreateButton) {
                    guard let mon = candidates.first(where: { $0.id == selectedMonID }) else { return }
                    Task {
                        if let link {
                            await trade.joinTrade(sessionId: link.sessionId, server: link.server, offering: mon)
                        } else {
                            await trade.createTrade(offering: mon)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedMonID == nil || !hasValidDisplayName)
            }
        }
    }

    /// Manual fallback for joining — the OS only ever routes `poketokenbar://` to one locally
    /// registered app, so a link received as plain text (chat, a second local instance in dev) needs
    /// somewhere to be pasted instead of clicked.
    private var pasteInviteRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField(l.tradePasteInviteLinkPlaceholder, text: $pastedInviteLink)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit(submitPastedInviteLink)
                Button(l.tradeJoinButton, action: submitPastedInviteLink)
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(pastedInviteLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if pastedInviteError {
                Text(l.tradeInvalidInviteLink).font(.caption2).foregroundStyle(.red)
            }
        }
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

    // MARK: Waiting / sharing

    private func waitingForJoin(shareURL: URL?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(l.tradeWaitingForJoin).font(.caption).foregroundStyle(.secondary)
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
            Button(l.tradeCancelButton) { trade.cancel() }.buttonStyle(.borderless)
        }
    }

    // MARK: Reviewing the counterpart's offer

    private func reviewCounterpart(_ counterpart: TradeStore.Offer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l.tradeReviewOffer(counterpart.displayName)).font(.caption).foregroundStyle(.secondary)
            TradeOfferRow(store: companion, mon: counterpart.pokemon, isSelected: false, onTap: nil)
            HStack {
                Button(l.tradeConfirmButton) { Task { await trade.confirm() } }
                    .buttonStyle(.borderedProminent)
                Button(l.tradeCancelButton) { trade.cancel() }
                    .buttonStyle(.borderless)
            }
        }
    }

    // MARK: Completed / status messages

    private func completedView(received: MonState, from: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TradeOfferRow(store: companion, mon: received, isSelected: false, onTap: nil)
            Text(l.tradeCompleted(companion.l.rarityLabel(received.rarity), from: from))
                .font(.caption).foregroundStyle(.secondary)
            Button(l.tradeDoneButton) { trade.cancel(); onClose() }.buttonStyle(.borderedProminent)
        }
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

/// One mon row on the trade screen — sprite + level/rarity/shiny. Not selectable when onTap is nil
/// (the review/completed screens).
private struct TradeOfferRow: View {
    let store: CompanionStore
    let mon: MonState
    let isSelected: Bool
    let onTap: (() -> Void)?

    var body: some View {
        let row = HStack(spacing: 10) {
            SpriteView(speciesID: mon.currentID, size: 44, shiny: mon.isShiny)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(store.l.pcLevel(mon.level)).font(.system(size: 11, weight: .bold))
                    if mon.isShiny { Text("✨").font(.system(size: 10)) }
                }
                Text(store.l.rarityLabel(mon.rarity)).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.secondary.opacity(isSelected ? 0.16 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))

        if let onTap {
            Button(action: onTap) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}
