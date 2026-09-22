import Foundation

/// Polling orchestration for a spectated battle — deliberately its own store, not folded into
/// `BattleStore`, because it shares none of that store's real concerns: no roster, no `choose`, no
/// gym-badge scoring, no leave-on-cancel (spectating has zero write surface server-side — see
/// spectator.md — so there's nothing to tell the server when a viewer stops watching, unlike a
/// participant abandoning a live session). Forcing this into `BattleStore` would just mean half its
/// fields/methods never apply here.
@MainActor
@Observable
final class SpectatorStore {
    enum Phase: Equatable {
        case idle
        case connecting
        case watching(sessionId: String, view: BattleClient.SpectatorView)
        case failed(BattleClient.BattleError)
    }

    private(set) var phase: Phase = .idle
    private let session: URLSession
    private let pollIntervalNanoseconds: UInt64
    private var pollTask: Task<Void, Never>?

    init(session: URLSession = .shared, pollIntervalNanoseconds: UInt64 = 2_000_000_000) {
        self.session = session
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
    }

    func start(serverURL: String, sessionId: String) {
        stop()
        phase = .connecting
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce(serverURL: serverURL, sessionId: sessionId)
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: self.pollIntervalNanoseconds)
            }
        }
    }

    private func pollOnce(serverURL: String, sessionId: String) async {
        do {
            let view = try await BattleClient.spectate(serverURL: serverURL, sessionId: sessionId, session: session)
            phase = .watching(sessionId: sessionId, view: view)
            if view.status == "completed" { pollTask?.cancel() }
        } catch BattleClient.BattleError.server(status: 404) {
            fail(.server(status: 404))
        } catch BattleClient.BattleError.server(status: 409) {
            // Not started yet (nobody's joined the battle being watched) — same "not fatal, keep
            // trying" shape a transient network failure gets below; a join can still land any poll.
        } catch {
            // Transient network/decoding hiccup — retry on the next tick, same as BattleStore.pollOnce.
        }
    }

    private func fail(_ error: BattleClient.BattleError) {
        pollTask?.cancel()
        pollTask = nil
        phase = .failed(error)
    }

    /// No server call — see the type doc comment for why there's nothing to tell it.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
        phase = .idle
    }
}
