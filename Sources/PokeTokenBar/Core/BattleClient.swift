import Foundation

/// PokeTokenBarOnline's battle session API — pure networking, mirrors TradeClient's shape. Unlike
/// trading, the server actually interprets these primitives (derives real stats via `@pkmn/sim`
/// instead of just relaying opaque JSON), so this file also owns turning a `MonState` into the wire
/// primitive — see `primitive(for:companion:)`.
enum BattleClient {
    /// A roster is 1–6 mons — mirrors `isRoster`'s bound in `pkmnAdapter.ts`, which rejects the whole
    /// create/join request with `400` if violated. Enforced here too so the roster picker's own
    /// selection cap matches what the server will actually accept, instead of letting someone select
    /// a 7th mon only to have the entire request bounce.
    static let maxRosterSize = 6

    /// Species id/level/nature/ability/IVs/EVs/moves — verifiable primitives, never a precomputed
    /// stat block. Mirrors `PokeTokenBarOnline`'s `MonPrimitive` (`src/pkmnAdapter.ts`) field-for-
    /// field; keep both in sync. See battles.md's "Trust model" section for why the split exists.
    struct StatsTable: Codable, Equatable {
        let hp, atk, def, spa, spd, spe: Int
    }
    struct Primitive: Codable, Equatable {
        let speciesID: Int
        let level: Int
        let nature: String
        let ability: String
        let ivs: StatsTable
        let evs: StatsTable
        let moves: [String]
    }

    struct PublicMon: Codable, Equatable {
        let speciesID: Int
        let name: String
        let fainted: Bool
        let hpFraction: Double
    }
    /// Gen 5 move audit, Fix B: the server's live per-slot move state for this side's active mon
    /// (id/PP/disabled, post-Disable/Taunt/Encore/Torment/Imprison/Mimic/Sketch/charge-turn) — see
    /// `activeMoveSlots` in `battles.ts`. `moveSlug` is a PokéAPI-style hyphenated slug
    /// (`move.name` lowercased, spaces to hyphens), matched against `moveDetail(name:)`.
    /// 서버가 준 슬롯 목록을 게임 규칙 상한(`MonState.maxKnownMoves`)으로 자른다.
    ///
    /// `activeMoves` 는 **서버가 주는 값**이고, 이 앱의 서버는 초대 링크로 지정될 수 있으므로 신뢰 대상이
    /// 아니다(`OnlineStore.isAllowedScheme` 주석과 같은 전제). 소비 루프가 슬롯마다 `moveDetail(name:)`
    /// 을 한 번씩 호출하므로, 길이를 안 자르면 슬롯 수만큼 PokéAPI 요청이 그대로 나간다 — 남의 서비스로
    /// 증폭되는 축이고, 순차 await 라 그동안 화면도 멈춘다.
    ///
    /// 4개 초과는 정상 대전에서 나올 수 없는 값이라 잘라내도 잃는 정보가 없다. `knownMoves` 를
    /// 신뢰경계에서 자른 것과 같은 규칙이고, 같은 상수를 쓴다.
    static func cappedActiveMoves(_ slots: [ActiveMoveSlot]?) -> [ActiveMoveSlot]? {
        guard let slots else { return nil }
        return Array(slots.prefix(MonState.maxKnownMoves))
    }

    struct ActiveMoveSlot: Codable, Equatable {
        let moveSlug: String
        let pp: Int
        let maxPP: Int
        let disabled: Bool
    }
    struct You: Codable, Equatable {
        let displayName: String
        let roster: [PublicMon]
        let activeIndex: Int
        /// `nil` while it isn't this side's move choice (switch/team-preview/wait) — same states
        /// `pendingChoice` distinguishes.
        let activeMoves: [ActiveMoveSlot]?
        /// Gen 5 move audit, "partial trap" category (Wrap/Bind/Fire Spin/...) — true while a
        /// partial-trap (or other switch-blocking) volatile is active on this side's mon. Optional,
        /// not defaulted server-side to `false`, purely so an older server that predates this field
        /// decodes fine too (missing key → `nil`) — treat `nil` the same as `false` at call sites.
        let trapped: Bool?
    }
    struct Opponent: Codable, Equatable {
        let displayName: String
        let active: PublicMon?
        let rosterSize: Int
    }
    /// `you`/`opponent`/`log`/`pendingChoice`/`result` are all absent while `status == "waiting"`
    /// (nobody's joined yet) — see `battleView` in `battles.ts`. Every field but `status`/`turn` is
    /// therefore optional here, not just the ones that stay absent after a battle starts.
    struct BattleView: Codable, Equatable {
        let status: String   // "waiting" | "active" | "completed"
        let turn: Int
        let pendingChoice: String?
        let you: You?
        let opponent: Opponent?
        /// The session creator's first roster slot — the same value for both sides' polls
        /// regardless of who's asking (read server-side off `meta` directly, not "you"/"opponent",
        /// which flip per-viewer). Used to pick a battle background by type deterministically, so
        /// both players land on the same terrain without either client needing to know who's the
        /// host — see `BattleView.backgroundTerrain(for:)`.
        let hostLeadSpeciesID: Int?
        let log: [String]?
        let result: String?  // "win" | "loss" | "draw"
    }
    // MARK: Spectating — see spectator.md

    /// The same restricted shape `battleView` already gives a participant's *opponent* (species/
    /// name/fainted/HP-fraction on the active mon, bench size only) — a spectator gets this for
    /// both sides, never the "you" privilege (real moveset, exact roster) either participant has
    /// over their own mon. No new privilege level, just this one rendered twice server-side.
    struct SpectatorSide: Codable, Equatable {
        let displayName: String
        let active: PublicMon?
        let rosterSize: Int
    }
    struct SpectatorView: Codable, Equatable {
        let status: String   // "waiting" | "active" | "completed"
        let turn: Int
        let p1: SpectatorSide?
        let p2: SpectatorSide?
        let hostLeadSpeciesID: Int?
        let log: [String]?
        let winner: String?  // "p1" | "p2" | "draw" — never "win"/"loss", which only mean something
                              // relative to a participant; see spectatorView in battles.ts.
    }

    /// No `uuid` — spectating needs none of the participant auth `status(...)` requires (see
    /// `GET /battles/:id/spectate`'s own doc comment server-side).
    static func spectate(serverURL: String, sessionId: String,
                          session: URLSession = .shared) async throws(BattleError) -> SpectatorView {
        guard let url = OnlineStore.endpointURL(from: serverURL, path: "/battles/\(sessionId)/spectate") else {
            throw .invalidServerURL
        }
        let req = request(url, method: "GET")
        let data = try await send(req, session: session)
        guard let decoded = try? JSONDecoder().decode(SpectatorView.self, from: data) else { throw .decoding }
        return decoded
    }

    struct OpenBattle: Codable, Equatable {
        let sessionId: String
        let displayName: String
        let rosterSize: Int
        /// Epoch milliseconds, a raw `Date.now()` from the server — NOT an ISO 8601 string, unlike
        /// `MonState`'s embedded dates in a trade payload. Decode as a number; convert manually
        /// (`Date(timeIntervalSince1970: createdAt / 1000)`) if a `Date` is ever needed for display.
        let createdAt: Double
    }

    /// A battle already underway, browsable for spectating — `GET /battles/live`'s entries. Browse
    /// is now the primary way in for both joining (`OpenBattle`) and spectating; a shared link is
    /// the backup, not the default.
    struct LiveBattle: Codable, Equatable {
        let sessionId: String
        let p1DisplayName: String
        let p2DisplayName: String
        let turn: Int
        let createdAt: Double
    }

    enum BattleError: Error, Equatable {
        case invalidServerURL
        case network(String)
        case server(status: Int)
        case decoding
    }

    private struct CreatePayload: Encodable {
        let uuid: String
        let displayName: String
        let party: [Primitive]
    }
    private struct ChoicePayload: Encodable { let uuid: String; let choice: String }
    private struct UUIDPayload: Encodable { let uuid: String }
    private struct CreateResponse: Decodable { let sessionId: String }
    private struct OpenListResponse: Decodable { let battles: [OpenBattle] }
    private struct LiveListResponse: Decodable { let battles: [LiveBattle] }

    /// Per-request deadline. URLRequest's default is 60s, which is far longer than the quit path
    /// is willing to wait: `applicationShouldTerminate` fires a leave and must let the app die
    /// promptly. Bounding the request itself is the root fix; the quit deadline is the backstop.
    /// `AppDelegate.quitLeaveDeadline` must stay above this — asserted in BattleClientTests.
    static let requestTimeout: TimeInterval = 10

    private static func request(_ url: URL, method: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = requestTimeout
        return req
    }

    private static func request(_ url: URL, method: String, body: some Encodable) throws(BattleError) -> URLRequest {
        var req = request(url, method: method)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let data = try? JSONEncoder().encode(body) else { throw .decoding }
        req.httpBody = data
        return req
    }

    private static func send(_ req: URLRequest, session: URLSession) async throws(BattleError) -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw .network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw .network("no response") }
        guard (200..<300).contains(http.statusCode) else { throw .server(status: http.statusCode) }
        return data
    }

    static func create(serverURL: String, uuid: String, displayName: String, party: [Primitive],
                        session: URLSession = .shared) async throws(BattleError) -> String {
        guard let url = OnlineStore.endpointURL(from: serverURL, path: "/battles") else { throw .invalidServerURL }
        let req = try request(url, method: "POST", body: CreatePayload(uuid: uuid, displayName: displayName, party: party))
        let data = try await send(req, session: session)
        guard let decoded = try? JSONDecoder().decode(CreateResponse.self, from: data) else { throw .decoding }
        return decoded.sessionId
    }

    static func join(serverURL: String, sessionId: String, uuid: String, displayName: String, party: [Primitive],
                      session: URLSession = .shared) async throws(BattleError) {
        guard let url = OnlineStore.endpointURL(from: serverURL, path: "/battles/\(sessionId)/join") else {
            throw .invalidServerURL
        }
        let req = try request(url, method: "POST", body: CreatePayload(uuid: uuid, displayName: displayName, party: party))
        _ = try await send(req, session: session)
    }

    static func status(serverURL: String, sessionId: String, uuid: String,
                        session: URLSession = .shared) async throws(BattleError) -> BattleView {
        guard let url = OnlineStore.endpointURL(from: serverURL, path: "/battles/\(sessionId)",
                                                queryItems: [URLQueryItem(name: "uuid", value: uuid)]) else {
            throw .invalidServerURL
        }
        let req = request(url, method: "GET")
        let data = try await send(req, session: session)
        guard let decoded = try? JSONDecoder().decode(BattleView.self, from: data) else { throw .decoding }
        return decoded
    }

    static func choose(serverURL: String, sessionId: String, uuid: String, choice: String,
                        session: URLSession = .shared) async throws(BattleError) -> BattleView {
        guard let url = OnlineStore.endpointURL(from: serverURL, path: "/battles/\(sessionId)/choose") else {
            throw .invalidServerURL
        }
        let req = try request(url, method: "POST", body: ChoicePayload(uuid: uuid, choice: choice))
        let data = try await send(req, session: session)
        guard let decoded = try? JSONDecoder().decode(BattleView.self, from: data) else { throw .decoding }
        return decoded
    }

    /// Tells the server this side is abandoning the session — pre-join this hard-deletes it (so it
    /// drops off `/battles/open` immediately instead of idling out its TTL); mid-battle it forfeits,
    /// so the other side's next poll reports a real win rather than a stalled session. Best-effort:
    /// callers fire-and-forget this (app quit, window close-while-waiting) as well as await it.
    static func leave(serverURL: String, sessionId: String, uuid: String,
                       session: URLSession = .shared) async throws(BattleError) {
        guard let url = OnlineStore.endpointURL(from: serverURL, path: "/battles/\(sessionId)/leave") else {
            throw .invalidServerURL
        }
        let req = try request(url, method: "POST", body: UUIDPayload(uuid: uuid))
        _ = try await send(req, session: session)
    }

    static func openBattles(serverURL: String, session: URLSession = .shared) async throws(BattleError) -> [OpenBattle] {
        guard let url = OnlineStore.endpointURL(from: serverURL, path: "/battles/open") else { throw .invalidServerURL }
        let req = request(url, method: "GET")
        let data = try await send(req, session: session)
        guard let decoded = try? JSONDecoder().decode(OpenListResponse.self, from: data) else { throw .decoding }
        return decoded.battles
    }

    static func liveBattles(serverURL: String, session: URLSession = .shared) async throws(BattleError) -> [LiveBattle] {
        guard let url = OnlineStore.endpointURL(from: serverURL, path: "/battles/live") else { throw .invalidServerURL }
        let req = request(url, method: "GET")
        let data = try await send(req, session: session)
        guard let decoded = try? JSONDecoder().decode(LiveListResponse.self, from: data) else { throw .decoding }
        return decoded.battles
    }

    // MARK: Opponent roster reveal (gym badges)

    /// Team preview (`|poke|p1|Pikachu, L50|`, one line per roster slot, in roster order) reveals
    /// every mon's species for *both* sides right at battle start, including bench mons never sent
    /// out — kept as its own small copy of the parse `BattleView` (the SwiftUI screen) already does
    /// for its chat recap; different callers, pure wire-format knowledge, not worth sharing a type
    /// across the Core/UI boundary for.
    /// 팀 프리뷰(`|poke|<side>|<species>, ...|`)에서 진영별 종명을 뽑는다. **이 파서는 여기 하나뿐이다.**
    ///
    /// 로그는 서버가 주고, 서버는 초대·관전 링크로 지정될 수 있어 신뢰 대상이 아니다. 호출부들이 뽑힌
    /// 이름마다 `speciesID(name:)` 로 PokéAPI 를 한 번씩 부르므로(순차 await), 자르지 않으면 서버가 보낸
    /// 서로 다른 이름 수만큼 요청이 나가고 그동안 화면이 멈춘다. `slug` 제한(#25)은 URL 경로를 지킬 뿐
    /// **요청 수**는 지키지 못한다 — 이 상한이 그 몫이다.
    ///
    /// 실제 대전은 두 진영(`p1`/`p2`) × 최대 `maxRosterSize` 마리가 전부라, 그 밖의 진영 키나 초과분은
    /// 정상 대전에서 나올 수 없고 잘라도 잃는 정보가 없다.
    ///
    /// 예전엔 같은 파서가 `BattleClient`·`BattleView`·`SpectatorView` 세 곳에 복사돼 있었다. 셋 다 상한이
    /// 없었고, 고치려면 세 번 고쳐야 했다 — 복사본이 늘수록 다음 복사본에서 빠뜨린다. 그래서 합쳤다.
    static func teamPreviewSpeciesNames(_ log: [String]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for line in log {
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 4, parts[1] == "poke" else { continue }
            let side = parts[2]
            guard side == "p1" || side == "p2", (result[side]?.count ?? 0) < maxRosterSize else { continue }
            let species = parts[3].components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? parts[3]
            result[side, default: []].append(species)
        }
        return result
    }

    /// This side's ident always looks like "{side}a: {displayName}-{index}" (pkmnAdapter.ts's
    /// nickname convention) — so scanning the log for the first ident whose nickname starts with
    /// our own display name tells "p1"/"p2" apart without ever needing to be told which one we are
    /// server-side (the wire format always speaks in terms of you/opponent, never p1/p2).
    private static func mySide(log: [String], myDisplayName: String) -> String? {
        let prefix = myDisplayName + "-"
        for line in log {
            for part in line.components(separatedBy: "|") {
                guard part.hasPrefix("p1") || part.hasPrefix("p2"), let colonRange = part.range(of: ": ") else { continue }
                if part[colonRange.upperBound...].hasPrefix(prefix) { return String(part.prefix(2)) }
            }
        }
        return nil
    }

    /// Every species in the opponent's revealed roster (team preview), for scoring gym badges once
    /// a battle completes as a win — see `GymBadge.earned(against:)`. Empty if team preview never
    /// ran (shouldn't happen; this app's fixed battle format always runs it) or `mySide` couldn't be
    /// determined (e.g. a truncated/corrupt log).
    static func opponentRosterNames(log: [String], myDisplayName: String) -> [String] {
        guard let mine = mySide(log: log, myDisplayName: myDisplayName) else { return [] }
        let other = mine == "p1" ? "p2" : "p1"
        return teamPreviewSpeciesNames(log)[other] ?? []
    }

    // MARK: MonState → Primitive

    enum PrimitiveError: Error, Equatable {
        /// A mon with no known moves yet (fresh hatch, before level-up auto-fill) can't field a
        /// legal roster slot — `MonPrimitive.moves` requires at least one on the server. Caught here,
        /// client-side, rather than let the server 400 it — the roster picker should exclude such a
        /// mon (or explain why) instead of offering a pick that's silently doomed to fail.
        case noKnownMoves
        /// Species base stats (needed for ability resolution) weren't available — offline, or
        /// PokéAPI unreachable. The same data CompanionView already needs to show a mon's stats page,
        /// so if this throws, that screen would currently be showing "loading" too.
        case missingBaseStats
    }

    /// Builds a verifiable, server-trusted primitive from a `MonState` — the client-side counterpart
    /// of `SaveTransfer.sanitizedMon`'s trust-boundary role, just producing input for the server's
    /// own clamp/derivation (`pkmnAdapter.ts`) instead of clamping locally. Needs live PokéAPI data
    /// (species base stats for ability resolution, move slugs for each known move id), so this is
    /// async and can fail — see `PrimitiveError`.
    @MainActor
    static func primitive(for mon: MonState, companion: CompanionStore) async throws -> Primitive {
        guard let base = await companion.baseStats(speciesID: mon.currentID) else {
            throw PrimitiveError.missingBaseStats
        }
        var slugs: [String] = []
        for moveID in mon.knownMoves {
            if let move = await companion.moveDetail(id: moveID) {
                slugs.append(move.name)
            }
        }
        guard !slugs.isEmpty else { throw PrimitiveError.noKnownMoves }

        let iv = mon.effectiveIVs
        let ev = mon.evs
        return Primitive(
            speciesID: mon.currentID,
            level: mon.level,
            // Legacy mons predating the nature roll have `nature == nil` (see MonState's comment);
            // "hardy" is neutral (no stat modifiers either way), matching what StatCalc.compute
            // already does for a nil nature — same net effect as the value we submit here.
            nature: mon.nature?.rawValue ?? "hardy",
            ability: mon.effectiveAbility(candidates: base.abilities) ?? base.abilities.first?.name ?? "no-ability",
            ivs: StatsTable(hp: iv.hp, atk: iv.attack, def: iv.defense, spa: iv.specialAttack, spd: iv.specialDefense, spe: iv.speed),
            evs: StatsTable(hp: ev.hp, atk: ev.attack, def: ev.defense, spa: ev.specialAttack, spd: ev.specialDefense, spe: ev.speed),
            moves: Array(slugs.prefix(MonState.maxKnownMoves))
        )
    }
}
