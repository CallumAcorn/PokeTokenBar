import Foundation

/// `poketokenbar://battle?server=<url>&session=<id>` — same shape/reasoning as `TradeDeepLink`.
///
/// Unlike trading, there's no `/b/:id` HTML landing page on the server yet (battles.md lists it
/// under M3, still pending) — so unlike `TradeDeepLink`, there's no `pastedText` form that accepts
/// a plain `https://server/b/:id` share link, only the raw deep link string. `BattleStore` still
/// builds something shareable (the raw deep link itself) in the meantime — see `createBattle`.
struct BattleDeepLink: Equatable {
    let server: String
    let sessionId: String

    init?(url: URL) {
        guard url.scheme == "poketokenbar", url.host == "battle",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let server = items.first(where: { $0.name == "server" })?.value, !server.isEmpty,
              let sessionId = items.first(where: { $0.name == "session" })?.value, !sessionId.isEmpty
        else { return nil }
        self.server = server
        self.sessionId = sessionId
    }

    init?(pastedText: String) {
        let trimmed = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        self.init(url: url)
    }
}

/// Battle session orchestration — polling, roster→primitive conversion, phase management. Mirrors
/// `TradeStore`'s shape, but simpler in one way (no reservation bookkeeping: unlike a trade offer,
/// picking a mon for a battle roster never removes it from the party or risks a double-offer — see
/// battles.md's Flow §1) and richer in another (a battle has an active, evolving state — HP, whose
/// turn it is, a log — trading only ever has "here's the other side's offer").
@MainActor
@Observable
final class BattleStore {
    enum StoreError: Error, Equatable {
        case client(BattleClient.BattleError)
        case primitive(BattleClient.PrimitiveError)
    }

    enum Phase: Equatable {
        case idle
        /// Set the instant Create/Join is tapped, before the roster-build (PokéAPI calls per mon) and
        /// the create/join POST even start — covers both until there's something real to show:
        /// `.waitingForOpponent` once a create succeeds, `.battling` once a join's first poll confirms
        /// `"active"`, or `.failed`/`.expired` on error. Without this, `phase` stayed `.idle` through
        /// that whole round trip, so the roster picker just sat there looking unresponsive after a tap
        /// — createBattle at least landed on `.waitingForOpponent` once it finished; joinBattle had no
        /// equivalent at all, since a join has no "share link" moment of its own to land on.
        case starting
        case waitingForOpponent(sessionId: String, shareURL: URL?)
        case battling(sessionId: String, view: BattleClient.BattleView)
        case failed(StoreError)
        case expired
    }

    private(set) var phase: Phase = .idle
    /// The lobby browse list — `GET /battles/open`, refreshed on demand by the roster-picker UI, not
    /// polled continuously (unlike an in-progress battle, a lobby list going a few seconds stale is
    /// harmless — worst case you tap a session that just got taken and get a plain join error).
    private(set) var openBattles: [BattleClient.OpenBattle] = []
    /// True only while a `refreshOpenBattles()` call is in flight — lets the browse screen show a
    /// spinner on the very first load instead of flashing "no open battles" for the round trip.
    private(set) var isLoadingOpenBattles = false
    /// The roster this side submitted — kept client-side because the server's `BattleView` never
    /// echoes back which moves a mon knows (`PublicMon` is just species/name/fainted/HP; `choose`
    /// only ever takes a 1-indexed slot number). The move grid renders this side's active mon's real
    /// moves from here, matched to `you.roster`/`activeIndex` by array position (both are built from
    /// this same roster, in this same order, so the positions always agree).
    private(set) var myRoster: [MonState] = []

    private let companion: CompanionStore
    private let online: OnlineStore
    private let session: URLSession
    private let pollIntervalNanoseconds: UInt64
    private var pollTask: Task<Void, Never>?
    /// The server a joined battle actually lives on — distinct from `online.serverURL` when the
    /// session was joined via a deep link/browse entry pointing at someone else's server (see
    /// `joinBattle`). Needed by `cancel()`'s `/leave` call, which must hit the same server the
    /// polling itself has been talking to, not necessarily this side's own configured server.
    private var activeServerURL: String?

    init(companion: CompanionStore, online: OnlineStore, session: URLSession = .shared, pollIntervalNanoseconds: UInt64 = 2_000_000_000) {
        self.companion = companion
        self.online = online
        self.session = session
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
    }

    /// An invite that arrived via deep link — the UI reads this to show a "join this battle?" screen.
    /// Same pattern as `TradeStore.pendingInvite`.
    private(set) var pendingInvite: BattleDeepLink?
    func handleIncomingLink(_ link: BattleDeepLink) {
        pendingInvite = link
    }
    func declineInvite() {
        pendingInvite = nil
    }

    // MARK: Roster → primitives

    /// Converts a whole roster, failing the attempt outright (not silently dropping a mon) the
    /// instant any single one can't be converted — the roster picker already showed the user this
    /// exact set of mons, so quietly submitting a smaller roster than what they picked would be
    /// more confusing than a clear "couldn't ready Pikachu for battle" error.
    private func buildParty(_ roster: [MonState]) async -> Result<[BattleClient.Primitive], StoreError> {
        var out: [BattleClient.Primitive] = []
        out.reserveCapacity(roster.count)
        for mon in roster {
            do {
                out.append(try await BattleClient.primitive(for: mon, companion: companion))
            } catch let e as BattleClient.PrimitiveError {
                return .failure(.primitive(e))
            } catch {
                // primitive(for:companion:) only ever throws PrimitiveError — unreachable in
                // practice, kept only for exhaustiveness.
                return .failure(.primitive(.missingBaseStats))
            }
        }
        return .success(out)
    }

    // MARK: Starting — create / join / browse

    func createBattle(roster: [MonState]) async {
        await cancel()
        phase = .starting
        let party: [BattleClient.Primitive]
        switch await buildParty(roster) {
        case .success(let p): party = p
        case .failure(let e): fail(e); return
        }
        do {
            let sessionId = try await BattleClient.create(serverURL: online.serverURL, uuid: online.clientUUID,
                                                           displayName: online.displayName, party: party, session: session)
            myRoster = roster
            phase = .waitingForOpponent(sessionId: sessionId, shareURL: shareURL(sessionId: sessionId, server: online.serverURL))
            startPolling(sessionId: sessionId)
        } catch {
            fail(.client(error))
        }
    }

    func joinBattle(sessionId: String, server: String, roster: [MonState]) async {
        await cancel()
        pendingInvite = nil
        phase = .starting
        let party: [BattleClient.Primitive]
        switch await buildParty(roster) {
        case .success(let p): party = p
        case .failure(let e): fail(e); return
        }
        do {
            try await BattleClient.join(serverURL: server, sessionId: sessionId, uuid: online.clientUUID,
                                        displayName: online.displayName, party: party, session: session)
            myRoster = roster
            startPolling(sessionId: sessionId, server: server)
        } catch {
            fail(.client(error))
        }
    }

    /// The raw deep link itself, standing in for a proper share link until the `/b/:id` landing page
    /// (battles.md M3) exists — `online.serverURL` is normalized through the same
    /// `OnlineStore.endpointURL` every other request already goes through, so a bare host the user
    /// typed ("trade.example.com") still round-trips as a full origin here, not a dangling fragment.
    private func shareURL(sessionId: String, server: String) -> URL? {
        guard let normalized = OnlineStore.endpointURL(from: server, path: "") else { return nil }
        var components = URLComponents()
        components.scheme = "poketokenbar"
        components.host = "battle"
        components.queryItems = [
            URLQueryItem(name: "server", value: normalized.absoluteString),
            URLQueryItem(name: "session", value: sessionId),
        ]
        return components.url
    }

    func refreshOpenBattles() async {
        isLoadingOpenBattles = true
        defer { isLoadingOpenBattles = false }
        openBattles = (try? await BattleClient.openBattles(serverURL: online.serverURL, session: session)) ?? []
    }

    // MARK: Polling

    private func startPolling(sessionId: String, server: String? = nil) {
        let serverURL = server ?? online.serverURL
        activeServerURL = serverURL
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce(sessionId: sessionId, serverURL: serverURL)
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }
        }
    }

    private func pollOnce(sessionId: String, serverURL: String) async {
        do {
            let view = try await BattleClient.status(serverURL: serverURL, sessionId: sessionId, uuid: online.clientUUID, session: session)
            switch view.status {
            case "active", "completed":
                phase = .battling(sessionId: sessionId, view: view)
                if view.status == "completed" { pollTask?.cancel() }
            default:
                break   // "waiting" — nothing new, still waiting for a join
            }
        } catch BattleClient.BattleError.server(status: 404) {
            fail(.client(.server(status: 404)))
        } catch BattleClient.BattleError.server(status: 401) {
            // Same reasoning as TradeStore: a 401 is never transient (wrong URL / deployment auth
            // wall), so don't let it spin the "waiting" state forever like a real network hiccup would.
            fail(.client(.server(status: 401)))
        } catch {
            // A transient network failure retries on the next tick — don't overwrite phase.
        }
    }

    // MARK: Choosing a move or switch

    static func moveChoice(_ oneIndexedSlot: Int) -> String { "move \(oneIndexedSlot)" }
    static func switchChoice(_ oneIndexedSlot: Int) -> String { "switch \(oneIndexedSlot)" }

    /// Applies the server's response to this call directly rather than waiting for the next poll
    /// tick — safe here (unlike TradeStore.confirm deliberately *not* doing this for its own
    /// completion), since choosing never mutates local party/save state, only reflects server truth
    /// a couple seconds sooner.
    func choose(_ choice: String) async {
        guard case .battling(let sessionId, let currentView) = phase else { return }
        do {
            let view = try await BattleClient.choose(serverURL: online.serverURL, sessionId: sessionId, uuid: online.clientUUID,
                                                      choice: choice, session: session)
            phase = .battling(sessionId: sessionId, view: view)
            if view.status == "completed" { pollTask?.cancel() }
        } catch {
            if case .server(status: 404) = error {
                fail(.client(error))
            } else {
                // A rejected/failed choose (bad move index, network hiccup) isn't fatal — stay on the
                // current view and let the next poll (or the player retrying) sort it out, same
                // "don't overwrite phase on a transient failure" reasoning pollOnce already follows.
                phase = .battling(sessionId: sessionId, view: currentView)
            }
        }
    }

    // MARK: Failure / cleanup

    /// Same self-healing shape as TradeStore.fail: put up the failure state, then automatically
    /// return to idle after a beat rather than leave a dead-end screen.
    private func fail(_ error: StoreError) {
        pollTask?.cancel()
        pollTask = nil
        if case .client(.server(status: 404)) = error {
            phase = .expired
            return
        }
        phase = .failed(error)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, case .failed = self.phase else { return }
            await self.cancel()
        }
    }

    /// Abandons whatever session is currently active — best-effort tells the server first (pre-join
    /// this deletes the session outright; mid-battle it forfeits, so the opponent's next poll reports
    /// a real win instead of a stalled session) so `/battles/open` and the other side's view both stay
    /// honest. A `.failed`/`.expired`/already-`"completed"` phase has nothing left to tell the server
    /// (the session's already gone, or already resolved) so leaveIfNeeded is a no-op there.
    func cancel() async {
        await leaveIfNeeded()
        pollTask?.cancel()
        pollTask = nil
        activeServerURL = nil
        phase = .idle
        myRoster = []
    }

    private func leaveIfNeeded() async {
        let sessionId: String
        switch phase {
        case .waitingForOpponent(let id, _):
            sessionId = id
        case .battling(let id, let view) where view.status != "completed":
            sessionId = id
        default:
            return
        }
        try? await BattleClient.leave(serverURL: activeServerURL ?? online.serverURL, sessionId: sessionId,
                                       uuid: online.clientUUID, session: session)
    }
}
