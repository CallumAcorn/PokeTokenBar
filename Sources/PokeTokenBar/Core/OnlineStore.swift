import Foundation
import Observation

/// Opt-in connection to a self-hosted PokeTokenBarOnline server (trading, later battles).
/// No server configured = fully offline, unchanged app behavior — this store only exists to
/// remember a URL and ping it; it does not gate anything elsewhere in the app yet.
@MainActor
@Observable
final class OnlineStore {
    enum PingResult: Equatable {
        case idle
        case checking
        case success
        case failure(String)
    }

    var serverURL: String {
        didSet { defaults.set(serverURL, forKey: "onlineServerURL") }
    }
    var displayName: String {
        didSet { defaults.set(displayName, forKey: "onlineDisplayName") }
    }
    /// Account-free identity — only used by the server to tell the two participants of a trade
    /// session apart. Not a secret, so UserDefaults rather than Keychain. Generated once on first
    /// access and persisted (didSet doesn't fire during init, so a freshly generated value is
    /// saved directly here instead).
    var clientUUID: String {
        didSet { defaults.set(clientUUID, forKey: "onlineClientUUID") }
    }
    private(set) var pingResult: PingResult = .idle

    private let defaults: UserDefaults
    private let session: URLSession

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        serverURL = defaults.string(forKey: "onlineServerURL") ?? ""
        displayName = defaults.string(forKey: "onlineDisplayName") ?? ""
        if let existing = defaults.string(forKey: "onlineClientUUID") {
            clientUUID = existing
        } else {
            let id = UUID().uuidString
            defaults.set(id, forKey: "onlineClientUUID")
            clientUUID = id
        }
    }

    func ping() async {
        guard let url = Self.healthURL(from: serverURL) else {
            pingResult = .failure("Invalid URL")
            return
        }
        pingResult = .checking
        do {
            let (_, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                pingResult = .failure("Unexpected response")
                return
            }
            pingResult = .success
        } catch {
            pingResult = .failure(error.localizedDescription)
        }
    }

    /// Normalizes a user-entered host into the server's `/health` endpoint. Users type a bare
    /// domain (`trade.example.com`), not a full URL — default to `https://` when no scheme is
    /// given, same mental model as pointing a game client at a server address.
    /// Takes either a bare domain the user typed (`trade.example.com`) or a full URL, fills in the
    /// default scheme (https), and appends the given path. Every trade API call reuses this same
    /// function — two separate server-address parsing rules would quietly drift if only one got fixed.
    nonisolated static func endpointURL(from input: String, path: String, queryItems: [URLQueryItem] = []) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: withScheme),
              let host = components.host, !host.isEmpty,
              isAllowedScheme(components.scheme, host: host) else { return nil }
        // Preserve a base path so a server hosted under a prefix works. Overwriting the path
        // outright sent `example.com/poke` to `example.com/health`, silently talking to the wrong
        // place instead of failing where the user could see it.
        let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = base + path
        if !queryItems.isEmpty { components.queryItems = queryItems }
        return components.url
    }

    /// Transport policy for the server address.
    ///
    /// A server address can arrive from a `poketokenbar://` link, which any web page can open, so
    /// it is attacker-influenced input rather than something only the user types. Plaintext to a
    /// remote host would put a trade payload on the wire in the clear and is refused here rather
    /// than left to fail opaquely inside ATS.
    ///
    /// Loopback keeps `http`: it never leaves the machine, and running the server locally over
    /// plain HTTP is the normal way to develop against it.
    nonisolated static func isAllowedScheme(_ scheme: String?, host: String) -> Bool {
        switch scheme?.lowercased() {
        case "https": return true
        case "http": return isLoopback(host)
        default: return false
        }
    }

    nonisolated static func isLoopback(_ host: String) -> Bool {
        let h = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return h == "localhost" || h == "127.0.0.1" || h == "::1" || h.hasSuffix(".localhost")
    }

    nonisolated static func healthURL(from input: String) -> URL? {
        endpointURL(from: input, path: "/health")
    }
}
