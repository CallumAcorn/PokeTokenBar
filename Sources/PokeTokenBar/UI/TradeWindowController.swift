import AppKit
import SwiftUI

/// Owns the standalone trade window — same shape as `BattleWindowController` (a real titled
/// `NSWindow`, not the 360pt popover strip): a multi-mon roster grid + token stake needs real
/// screen real estate a popover screen can't give it, the same reason battling moved out first.
///
/// Closing the window only hides it (`performClose`, `isReleasedWhenClosed = false`) — it never
/// touches `TradeStore`. A trade in progress (an open invite waiting to be joined, an offer under
/// review) keeps polling in the background regardless of whether this window is visible, same as
/// `BattleWindowController`'s own reasoning.
@MainActor
final class TradeWindowController {
    private var window: NSWindow?
    private let companion: CompanionStore
    private let trade: TradeStore
    private let online: OnlineStore

    init(companion: CompanionStore, trade: TradeStore, online: OnlineStore) {
        self.companion = companion
        self.trade = trade
        self.online = online
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView:
            TradeView(onClose: { [weak self] in self?.window?.performClose(nil) })
                .environment(companion)
                .environment(trade)
                .environment(online))
        let w = NSWindow(contentViewController: hosting)
        w.title = L(companion.language).tradeTitle
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.isReleasedWhenClosed = false   // this controller keeps owning it — reopen must reuse, not recreate
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
