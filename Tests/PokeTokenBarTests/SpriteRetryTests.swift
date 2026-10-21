import XCTest
@testable import PokeTokenBar

/// A sprite whose GIF failed to download used to stay frozen on its static frame until relaunch.
/// The retry loop's timing, without the network.
@MainActor
final class SpriteRetryTests: XCTestCase {
    func testRetriesUntilTheDownloadWorks() async {
        var attempts = 0
        var waits: [Duration] = []
        let result = await SpriteStore.retrying(wait: { waits.append($0) }) { () async -> Int? in
            attempts += 1
            return attempts == 4 ? 42 : nil
        }
        XCTAssertEqual(result, 42)
        XCTAssertEqual(waits, [.seconds(2), .seconds(4), .seconds(8)])
    }

    /// The wait stops growing at five minutes, so a long outage costs about 12 requests an hour
    /// per visible sprite rather than upstream's 120.
    func testTheWaitIsCappedAtFiveMinutes() async {
        var attempts = 0
        var waits: [Duration] = []
        _ = await SpriteStore.retrying(wait: { waits.append($0) }) { () async -> Int? in
            attempts += 1
            return attempts == 12 ? 1 : nil
        }
        XCTAssertEqual(waits.max(), SpriteStore.maxAnimationRetryDelay)
        XCTAssertEqual(waits.suffix(3), [.seconds(300), .seconds(300), .seconds(300)])
    }

    /// A cancelled view stops retrying: the wait throws and the loop gives up.
    func testCancellationStopsRetrying() async {
        var attempts = 0
        let result = await SpriteStore.retrying(wait: { _ in throw CancellationError() }) { () async -> Int? in
            attempts += 1
            return nil
        }
        XCTAssertNil(result)
        XCTAssertEqual(attempts, 1)
    }
}
