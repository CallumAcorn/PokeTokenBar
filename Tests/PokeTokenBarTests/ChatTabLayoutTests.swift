import XCTest
import SwiftUI
@testable import PokeTokenBar

/// Claude Chat is a supplemental provider, so it is not in `registeredProviderIDs` and upstream's
/// ProviderTabLayoutTests do not count it. When it has data it still adds a twelfth tab, so repeat the
/// same single-row and fits-the-popover guards with it present.
@MainActor
final class ChatTabLayoutTests: XCTestCase {
    private func snapshot(_ id: String, _ name: String) -> ProviderSnapshot {
        ProviderSnapshot(providerID: id, displayName: name, today: nil, activeBlock: nil,
                         weekTotal: nil, monthTotal: nil, fetchedAt: Date())
    }

    private var everyProviderPlusChat: [ProviderSnapshot] {
        [("claude_code", "Claude Code"), ("codex", "Codex"), ("gemini", "Gemini"),
         ("antigravity", "Antigravity"), ("opencode", "OpenCode"), ("hermes", "Hermes Agent"),
         ("cursor", "Cursor"), ("grok", "Grok"), ("copilot", "Copilot"), ("kiro", "Kiro"),
         ("pi", "Pi"), (DesktopChatTokens.providerID, "Claude Chat")]
            .map { snapshot($0.0, $0.1) }
    }

    private func bar(_ snapshots: [ProviderSnapshot]) -> ProviderTabBar {
        ProviderTabBar(snapshots: snapshots, selectedID: snapshots.first?.providerID, onSelect: { _ in })
    }

    private func rendered(_ view: some View, proposing width: CGFloat) -> CGSize {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 600))
    }

    func testTabBarStaysSingleRowWithChatAsATwelfthTab() {
        let baseline = rendered(bar(Array(everyProviderPlusChat.prefix(2))), proposing: PopoverMetrics.contentWidth).height
        let full = rendered(bar(everyProviderPlusChat), proposing: PopoverMetrics.contentWidth).height
        XCTAssertEqual(full, baseline, accuracy: 0.5)
    }

    func testTabBarWithChatFitsThePopover() {
        XCTAssertLessThanOrEqual(rendered(bar(everyProviderPlusChat), proposing: PopoverMetrics.contentWidth).width,
                                 PopoverMetrics.contentWidth)
    }

    func testTheChatTabAloneFitsThePopover() {
        let chat = snapshot(DesktopChatTokens.providerID, "Claude Chat")
        XCTAssertLessThanOrEqual(rendered(bar([chat]), proposing: PopoverMetrics.contentWidth).width,
                                 PopoverMetrics.contentWidth)
    }

    /// The registry-wide invariants must keep treating chat as out of scope: it has no scan folders.
    func testChatIsNotInTheFileScanningRegistry() {
        let store = UsageStore(autoRefresh: false,
                               defaults: UserDefaults(suiteName: "ChatTabLayoutTests.\(UUID().uuidString)")!)
        XCTAssertFalse(store.registeredProviderIDs.contains(DesktopChatTokens.providerID))
    }
}
