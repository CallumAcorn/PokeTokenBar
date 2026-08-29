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
    struct You: Codable, Equatable {
        let displayName: String
        let roster: [PublicMon]
        let activeIndex: Int
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
        let log: [String]?
        let result: String?  // "win" | "loss" | "draw"
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
    private struct CreateResponse: Decodable { let sessionId: String }
    private struct OpenListResponse: Decodable { let battles: [OpenBattle] }

    private static func request(_ url: URL, method: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
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

    static func openBattles(serverURL: String, session: URLSession = .shared) async throws(BattleError) -> [OpenBattle] {
        guard let url = OnlineStore.endpointURL(from: serverURL, path: "/battles/open") else { throw .invalidServerURL }
        let req = request(url, method: "GET")
        let data = try await send(req, session: session)
        guard let decoded = try? JSONDecoder().decode(OpenListResponse.self, from: data) else { throw .decoding }
        return decoded.battles
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
