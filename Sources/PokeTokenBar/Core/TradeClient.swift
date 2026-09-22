import Foundation

/// PokeTokenBarOnline's trade session API — pure networking, no state (orchestration lives in
/// TradeStore). The server never interprets the `pokemon` field, only stores and forwards it
/// (opaque JSON), so we encode `MonState` as-is here too — no separate schema on the server side.
/// See trading-overhaul.md for the multi-mon + token wire format this mirrors.
enum TradeClient {
    /// Same bound as BattleClient.maxRosterSize — mirrors trades.ts's isOffer, which rejects the
    /// whole create/join request with `400` past 6.
    static let maxOfferSize = 6

    struct StatusResponse: Codable {
        let status: String   // "open" | "offered" | "completed"
        let counterpart: Counterpart?
        struct Counterpart: Codable {
            let displayName: String
            let pokemon: [MonState]
            let tokens: Int
        }
    }

    /// A session still waiting for a second player, browsable via `GET /trades/open` — the
    /// alternative to sharing a link. Mirrors `BattleClient.OpenBattle`'s shape.
    struct OpenTrade: Codable, Equatable {
        let sessionId: String
        let displayName: String
        let pokemon: [MonState]
        let tokens: Int
        /// Epoch milliseconds, a raw `Date.now()` from the server — same convention as
        /// `BattleClient.OpenBattle.createdAt`, NOT the `.iso8601` dates `MonState` itself carries.
        let createdAt: Double
    }

    enum TradeError: Error, Equatable {
        case invalidServerURL
        case network(String)
        case server(status: Int)
        case decoding
    }

    private struct OfferPayload: Encodable {
        let uuid: String
        let displayName: String
        let pokemon: [MonState]
        let tokens: Int
    }
    private struct ConfirmPayload: Encodable { let uuid: String }
    private struct CreateResponse: Decodable { let sessionId: String }
    private struct OpenListResponse: Decodable { let trades: [OpenTrade] }

    /// The save file (CompanionStore.save/load) uses the default encoding (epoch double), but this
    /// payload crosses a device boundary, so it follows the same convention as SaveTransfer
    /// (.iso8601) — a different persistence path, a different codec.
    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private static func request(_ url: URL, method: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        return req
    }

    private static func request(_ url: URL, method: String, body: some Encodable) throws(TradeError) -> URLRequest {
        var req = request(url, method: method)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let data = try? makeEncoder().encode(body) else { throw .decoding }
        req.httpBody = data
        return req
    }

    private static func send(_ req: URLRequest, session: URLSession) async throws(TradeError) -> Data {
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

    static func create(serverURL: String, uuid: String, displayName: String, offering mons: [MonState], tokens: Int,
                        session: URLSession = .shared) async throws(TradeError) -> String {
        guard let url = OnlineStore.endpointURL(from: serverURL, path: "/trades") else { throw .invalidServerURL }
        let req = try request(url, method: "POST",
                               body: OfferPayload(uuid: uuid, displayName: displayName, pokemon: mons, tokens: tokens))
        let data = try await send(req, session: session)
        guard let decoded = try? makeDecoder().decode(CreateResponse.self, from: data) else { throw .decoding }
        return decoded.sessionId
    }

    static func join(serverURL: String, sessionId: String, uuid: String, displayName: String, offering mons: [MonState], tokens: Int,
                      session: URLSession = .shared) async throws(TradeError) {
        guard let url = OnlineStore.endpointURL(from: serverURL, path: "/trades/\(sessionId)/join") else {
            throw .invalidServerURL
        }
        let req = try request(url, method: "POST",
                               body: OfferPayload(uuid: uuid, displayName: displayName, pokemon: mons, tokens: tokens))
        _ = try await send(req, session: session)
    }

    static func status(serverURL: String, sessionId: String, uuid: String,
                        session: URLSession = .shared) async throws(TradeError) -> StatusResponse {
        guard let url = OnlineStore.endpointURL(from: serverURL, path: "/trades/\(sessionId)",
                                                queryItems: [URLQueryItem(name: "uuid", value: uuid)]) else {
            throw .invalidServerURL
        }
        let req = request(url, method: "GET")
        let data = try await send(req, session: session)
        guard let decoded = try? makeDecoder().decode(StatusResponse.self, from: data) else { throw .decoding }
        return decoded
    }

    static func confirm(serverURL: String, sessionId: String, uuid: String,
                         session: URLSession = .shared) async throws(TradeError) -> StatusResponse {
        guard let url = OnlineStore.endpointURL(from: serverURL, path: "/trades/\(sessionId)/confirm") else {
            throw .invalidServerURL
        }
        let req = try request(url, method: "POST", body: ConfirmPayload(uuid: uuid))
        let data = try await send(req, session: session)
        guard let decoded = try? makeDecoder().decode(StatusResponse.self, from: data) else { throw .decoding }
        return decoded
    }

    /// Takes back a confirm — the only way to genuinely back out of a trade after tapping Confirm,
    /// not just stop polling locally (which would leave the server thinking I already confirmed, so
    /// the trade could still complete on the counterpart's side the moment they confirm too). The
    /// server 409s once the trade has actually completed — see trades.ts's own doc comment.
    static func unconfirm(serverURL: String, sessionId: String, uuid: String,
                           session: URLSession = .shared) async throws(TradeError) -> StatusResponse {
        guard let url = OnlineStore.endpointURL(from: serverURL, path: "/trades/\(sessionId)/unconfirm") else {
            throw .invalidServerURL
        }
        let req = try request(url, method: "POST", body: ConfirmPayload(uuid: uuid))
        let data = try await send(req, session: session)
        guard let decoded = try? makeDecoder().decode(StatusResponse.self, from: data) else { throw .decoding }
        return decoded
    }

    /// Lists sessions still waiting for a second player — mirrors `BattleClient.openBattles`.
    /// Browse is now the primary way into a trade too, not just a shared link — see trading-overhaul.md.
    static func openTrades(serverURL: String, session: URLSession = .shared) async throws(TradeError) -> [OpenTrade] {
        guard let url = OnlineStore.endpointURL(from: serverURL, path: "/trades/open") else { throw .invalidServerURL }
        let req = request(url, method: "GET")
        let data = try await send(req, session: session)
        guard let decoded = try? makeDecoder().decode(OpenListResponse.self, from: data) else { throw .decoding }
        return decoded.trades
    }
}
