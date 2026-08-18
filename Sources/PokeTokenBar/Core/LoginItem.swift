import ServiceManagement

/// 로그인 시 실행, 그리고 **선택적으로** 크래시/비정상 종료 시 자동 재실행(launchd KeepAlive).
///
/// 배경: `SMAppService.mainApp`(로그인아이템)은 **크래시 시 시스템이 재실행하지 않는다**(Apple 명시).
/// 그래서 KeepAlive 를 가진 LaunchAgent 로 대체했다 — launchd 가 워치독으로 동작해 앱이 비정상
/// 종료(크래시·OOM SIGKILL 등 exit≠0)되면 자동 재실행한다.
///
/// This fork splits that into two agents, because "start me at login" and "restart me whenever I
/// exit non-zero" are different amounts of persistence and the user should be able to choose.
/// A KeepAlive agent is the shape endpoint security tooling flags: a process that reappears after
/// being killed. Crash recovery is a real feature, so it stays available, but it is now a separate
/// opt-in rather than something bundled into the login toggle.
///
/// - `plistName` (`…poketokenbar.login`) — RunAtLoad only. Keeps the **existing** label so anyone
///   already registered stays registered across the upgrade; only the plist contents change.
/// - `autoRestartPlistName` (`…poketokenbar.autorestart`) — RunAtLoad **+** KeepAlive.
///
/// Exactly one is ever registered. plist 는 앱 번들 `Contents/Library/LaunchAgents/` 에 있어야
/// 한다(build-app.sh 가 둘 다 생성).
@MainActor
enum LoginItem {
    static let plistName = "io.github.chattymin.poketokenbar.login.plist"
    static let label = "io.github.chattymin.poketokenbar.login"
    static let autoRestartPlistName = "io.github.chattymin.poketokenbar.autorestart.plist"
    static let autoRestartLabel = "io.github.chattymin.poketokenbar.autorestart"

    private static var agent: SMAppService { SMAppService.agent(plistName: plistName) }
    private static var autoRestartAgent: SMAppService { SMAppService.agent(plistName: autoRestartPlistName) }

    /// 현재 "로그인 시 실행" 활성 여부 — 두 에이전트 중 하나라도 등록돼 있으면 true.
    static var isEnabled: Bool {
        agent.status == .enabled || autoRestartAgent.status == .enabled
    }

    /// 크래시 자동 재실행(KeepAlive) 활성 여부.
    static var isAutoRestartEnabled: Bool { autoRestartAgent.status == .enabled }

    /// 로그인 실행 토글. `autoRestart` 는 KeepAlive 워치독 사용 여부.
    ///
    /// 등록은 **항상 한 쪽만** 유지한다 — 먼저 반대쪽을 해제한 뒤 원하는 쪽을 등록해서, 두 에이전트가
    /// 동시에 살아 인스턴스가 둘 뜨는 상태(SingleInstance 가 뒤늦게 정리해야 하는 상태)를 만들지 않는다.
    static func setEnabled(_ on: Bool, autoRestart: Bool = isAutoRestartEnabled) throws {
        guard on else {
            try? autoRestartAgent.unregister()
            try? agent.unregister()
            return
        }
        let wanted = autoRestart ? autoRestartAgent : agent
        let other = autoRestart ? agent : autoRestartAgent
        // 반대쪽 해제 실패는 무시한다 — 미등록 상태에서의 unregister 는 throw 하지만 결과는 원하는 대로다.
        try? other.unregister()
        // 이미 등록돼 있으면 다시 등록하지 않는다. SMAppService 는 중복 register 에 에러를 돌려줄 수 있고,
        // 그러면 설정 화면이 "실패"로 보고 토글을 되돌린다 — 상태는 멀쩡한데 UI 만 튕기는 회귀가 된다.
        guard wanted.status != .enabled else { return }
        try wanted.register()
    }

    /// KeepAlive 만 토글 — 로그인 실행이 이미 켜져 있을 때 에이전트를 갈아끼운다.
    /// 꺼져 있으면 선택만 기억하면 되므로(다음에 켤 때 반영) 아무것도 등록하지 않는다.
    static func setAutoRestart(_ on: Bool) throws {
        guard isEnabled else { return }
        try setEnabled(true, autoRestart: on)
    }

    /// 구버전(`SMAppService.mainApp` 로그인아이템) → 에이전트로 **1회 이관**.
    /// 안전: mainApp 이 켜져 있을 때만 이관하고, **에이전트 등록이 성공한 뒤에만 mainApp 을 해제**한다
    /// (등록 실패 시 mainApp 을 유지 → 구동작 보존, "로그인 실행"을 잃지 않는다). 멱등(반복 호출 무해).
    ///
    /// 이관 대상은 KeepAlive 가 **없는** 쪽이다 — 사용자가 고른 적 없는 워치독 지속성을 업그레이드가
    /// 조용히 켜 주지는 않는다. 필요하면 설정에서 켜면 된다.
    static func migrateFromLegacyLoginItemIfNeeded() {
        let legacy = SMAppService.mainApp
        guard legacy.status == .enabled else { return }   // 구 로그인아이템 미사용 → 이관 불필요
        do {
            if !isEnabled { try agent.register() }   // 에이전트 먼저 등록
            try legacy.unregister()                   // 성공 후에만 구 항목 해제
            AppLog.write("login item migrated: mainApp → login agent (no KeepAlive)")
        } catch {
            AppLog.write("login item migration failed (mainApp 유지): \(error)")
        }
    }
}
