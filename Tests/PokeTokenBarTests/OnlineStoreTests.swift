import XCTest
@testable import PokeTokenBar

final class OnlineStoreTests: XCTestCase {
    func testHealthURLAddsHTTPSSchemeForBareDomain() {
        XCTAssertEqual(OnlineStore.healthURL(from: "trade.example.com")?.absoluteString,
                        "https://trade.example.com/health")
    }

    func testHealthURLKeepsExplicitScheme() {
        XCTAssertEqual(OnlineStore.healthURL(from: "http://localhost:3000")?.absoluteString,
                        "http://localhost:3000/health")
    }

    func testHealthURLTrimsWhitespace() {
        XCTAssertEqual(OnlineStore.healthURL(from: "  trade.example.com  ")?.absoluteString,
                        "https://trade.example.com/health")
    }

    func testHealthURLRejectsEmptyOrInvalidInput() {
        XCTAssertNil(OnlineStore.healthURL(from: ""))
        XCTAssertNil(OnlineStore.healthURL(from: "   "))
        XCTAssertNil(OnlineStore.healthURL(from: "https://"))
    }
}

/// Transport and path rules for the server address.
///
/// The address is not merely something the user types: a `poketokenbar://` invite can carry one,
/// and any web page can open that scheme. So it is attacker-influenced input and gets checked.
final class OnlineStoreAddressPolicyTests: XCTestCase {

    func testPlaintextToRemoteHostIsRefused() {
        XCTAssertNil(OnlineStore.healthURL(from: "http://trade.example.com"),
                     "a trade payload must not go to a remote host in the clear")
        XCTAssertNil(OnlineStore.healthURL(from: "http://192.0.2.10:3000"))
    }

    /// Loopback keeps http — it never leaves the machine, and it is how the server is developed
    /// against locally. Removing this would break a legitimate workflow for no security gain.
    func testLoopbackKeepsPlaintext() {
        XCTAssertEqual(OnlineStore.healthURL(from: "http://localhost:3000")?.absoluteString,
                       "http://localhost:3000/health")
        XCTAssertEqual(OnlineStore.healthURL(from: "http://127.0.0.1:3000")?.absoluteString,
                       "http://127.0.0.1:3000/health")
    }

    /// Anything that is not http/https is refused outright rather than handed to URLSession.
    func testNonHTTPSchemesAreRefused() {
        for input in ["ftp://trade.example.com", "file://trade.example.com",
                      "javascript://trade.example.com", "ws://trade.example.com"] {
            XCTAssertNil(OnlineStore.healthURL(from: input), "\(input) must be refused")
        }
    }

    /// A server hosted under a path prefix must keep it. Overwriting the path outright sent
    /// requests to the wrong place silently, which is worse than failing visibly.
    func testBasePathIsPreserved() {
        XCTAssertEqual(OnlineStore.healthURL(from: "trade.example.com/poke")?.absoluteString,
                       "https://trade.example.com/poke/health")
        XCTAssertEqual(OnlineStore.healthURL(from: "https://trade.example.com/poke/")?.absoluteString,
                       "https://trade.example.com/poke/health")
    }

    func testBareDomainStillDefaultsToHTTPS() {
        XCTAssertEqual(OnlineStore.healthURL(from: "trade.example.com")?.absoluteString,
                       "https://trade.example.com/health")
    }

    func testLoopbackDetection() {
        for h in ["localhost", "LOCALHOST", "127.0.0.1", "::1", "api.localhost"] {
            XCTAssertTrue(OnlineStore.isLoopback(h), "\(h) should be loopback")
        }
        for h in ["example.com", "notlocalhost.com", "127.0.0.1.example.com"] {
            XCTAssertFalse(OnlineStore.isLoopback(h), "\(h) should not be loopback")
        }
    }
}
