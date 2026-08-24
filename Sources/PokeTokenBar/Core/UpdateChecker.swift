import AppKit
import Observation

/// GitHub 릴리스 최신 버전을 확인해 새 버전이 있으면 팝오버에 알린다.
///
/// This fork publishes **tag-only releases with no binaries**. Without an Apple Developer ID a
/// downloadable build is self-signed and un-notarised, so every user would have to defeat
/// Gatekeeper to open it — the exact bypass this fork removed from the upstream cask. Shipping no
/// binary avoids the problem outright: a release is a version marker plus notes, and the user
/// rebuilds from source they can read.
///
/// So the app cannot install an update and does not pretend to. It reports that one exists and
/// shows the commands. The previous `brew upgrade` path is gone: with no binaries there is nothing
/// for brew to fetch, and a cask upgrade was also the last mechanism that could pull a build from
/// somewhere other than this fork.
@MainActor
@Observable
final class UpdateChecker {
    struct Available: Equatable { let version: String; let url: String }

    private(set) var available: Available?

    let currentVersion: String
    /// Update source. **Must be this fork.** Pointing at upstream offered users a "v2.5.2
    /// available" banner whose Update button installed the original project — different code,
    /// none of the hardening here, and a silent downgrade of everything this fork changed.
    /// Guarded mechanically by verify-hardening.sh so it cannot drift back.
    nonisolated static let repo = "CallumAcorn/PokeTokenBar"

    /// Homebrew cask token. Deliberately **not** upstream's `poke-token-bar`: sharing the token
    /// meant `brew upgrade --cask poke-token-bar` would match an upstream install and pull their
    /// build. A distinct token makes the two impossible to confuse.
    nonisolated static let caskToken = "poke-token-bar-hardened"
    private let clock: () -> Date
    private var lastChecked: Date?

    init(currentVersion: String? = nil, clock: @escaping () -> Date = Date.init) {
        self.currentVersion = currentVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        self.clock = clock
    }

    /// 최신 릴리스 조회 → 새 버전이고 사용자가 그 버전을 'skip' 하지 않았으면 available 설정.
    /// minInterval 보다 자주 호출되면 무시(레이트리밋 보호).
    func check(minInterval: TimeInterval = 1800) async {
        if let last = lastChecked, clock().timeIntervalSince(last) < minInterval { return }
        lastChecked = clock()
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let html = json["html_url"] as? String,
              // 응답 필드가 NSWorkspace.open 으로 가므로 https + github.com 만 허용(스킴 하이재킹 방지)
              let htmlURL = URL(string: html), htmlURL.scheme == "https", htmlURL.host == "github.com"
        else { return }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let skipped = UserDefaults.standard.string(forKey: "skippedUpdateVersion")
        if Self.isNewer(latest, than: currentVersion), latest != skipped {
            available = Available(version: latest, url: html)
        } else {
            available = nil
        }
    }

    /// 이 버전은 다시 알리지 않음.
    func skipCurrent() {
        if let v = available?.version { UserDefaults.standard.set(v, forKey: "skippedUpdateVersion") }
        available = nil
    }

    /// Open the release notes for the available version. Named for what it does — there is no
    /// install step to trigger.
    func openReleaseNotes() {
        guard let update = available, let url = URL(string: update.url) else { return }
        NSWorkspace.shared.open(url)
    }

    /// The commands that actually perform an update, for display and copying.
    ///
    /// `checkoutPath` is intentionally a placeholder rather than a guess at where the user cloned:
    /// printing a path that does not exist on their machine is worse than an obvious placeholder.
    nonisolated static func updateCommands(checkoutPath: String = "~/Code/PokeTokenBar") -> String {
        """
        cd \(checkoutPath)
        git pull
        ./scripts/build-app.sh
        """
    }

    // MARK: 버전 비교

    /// Version ordering for this fork's scheme: `MAJOR.MINOR.PATCH` optionally followed by
    /// `-hardened.N`.
    ///
    /// The suffix exists because upstream and this fork would otherwise ship different code under
    /// identical version strings — both sat at 2.5.1 while upstream released its own 2.5.2.
    ///
    /// Naive dot-splitting cannot do this. `"2.5.1-hardened.1".split(".")` yields
    /// `["2","5","1-hardened","1"]`, and `Int("1-hardened")` is nil, so the patch collapses to 0
    /// and the build reads as *older* than plain 2.5.1 — the update banner would then never fire.
    nonisolated static func parseVersion(_ v: String) -> (core: [Int], hardened: Int) {
        let parts = v.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = parts[0].split(separator: ".").map { Int($0) ?? 0 }
        var hardened = 0
        if parts.count > 1 {
            // "hardened.3" -> 3. Any other suffix contributes 0, so it sorts alongside the plain
            // release rather than silently ranking above or below it.
            let tail = parts[1].split(separator: ".")
            if tail.first == "hardened", tail.count > 1, let n = Int(tail[1]) { hardened = n }
        }
        return (core, hardened)
    }

    /// a 가 b 보다 높은 버전인가.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let va = parseVersion(a), vb = parseVersion(b)
        for i in 0..<max(va.core.count, vb.core.count) {
            let x = i < va.core.count ? va.core[i] : 0
            let y = i < vb.core.count ? vb.core[i] : 0
            if x != y { return x > y }
        }
        return va.hardened > vb.hardened
    }
}
