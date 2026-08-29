import AppKit
import SwiftUI

/// Owns the standalone battle window — a real titled `NSWindow` (unlike `FloatingPetPanel`'s
/// borderless overlay panel), because a battle screen needs proper window chrome (title bar, close
/// button) and real screen real estate, not the 360pt popover strip.
///
/// Closing the window (the standard red close button, or `onClose`) only hides it, via `NSWindow`'s
/// own default `performClose` behavior (order-out, not dealloc, since `isReleasedWhenClosed =
/// false`) — it never touches `BattleStore`. This matches how the popover already treats an
/// in-progress trade: `PopoverNavigation.reset()` (called every popover open) only resets which
/// *screen* is showing, never `TradeStore`'s phase, so polling keeps running in the background
/// regardless of what's currently visible. A battle behaves the same way — closing the window must
/// not silently abandon a live session your opponent is still playing against.
@MainActor
final class BattleWindowController {
    private var window: NSWindow?
    private let companion: CompanionStore
    private let battle: BattleStore
    private let online: OnlineStore

    init(companion: CompanionStore, battle: BattleStore, online: OnlineStore) {
        self.companion = companion
        self.battle = battle
        self.online = online
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView:
            BattleView(onClose: { [weak self] in self?.window?.performClose(nil) })
                .environment(companion)
                .environment(battle)
                .environment(online))
        let w = NSWindow(contentViewController: hosting)
        w.title = L(companion.language).battleTitle
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.isReleasedWhenClosed = false   // this controller keeps owning it — reopen must reuse, not recreate
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
