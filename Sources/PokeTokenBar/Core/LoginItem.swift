import Foundation
import ServiceManagement

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

/// Launch at login, registered as the app itself (`SMAppService.mainApp`). Ported from upstream
/// 38e3e553 (#474).
///
/// Earlier builds registered a LaunchAgent instead: `…poketokenbar.login` (RunAtLoad), or
/// `…poketokenbar.autorestart` (RunAtLoad + KeepAlive) when the user opted into crash restart.
/// On current macOS launchd execs a self-signed or ad-hoc signed binary directly and AMFI kills it
/// with a launch constraint violation: `SMAppService.agent.status` reads `.enabled` while
/// `launchctl print` shows `spawn failed`, `OS_REASON_CODESIGNING`. Manual launches go through
/// LaunchServices and never hit this, which is why it went unnoticed. Both agents were dead, so the
/// crash-restart option went with them; a login item carries less persistence anyway.
///
/// The agent plists stay in the bundle only so `SMAppService` can still query and unregister them.
@MainActor
struct LoginItem {
    static let legacyLabels = [
        "io.github.chattymin.poketokenbar.login",
        "io.github.chattymin.poketokenbar.autorestart",
    ]

    let mainApp: any LoginItemService
    let legacyAgents: [any LoginItemService]
    /// This process was started by one of the legacy agents. Unregistering that agent can terminate
    /// the process it launched, so its cleanup waits for an ordinary launch.
    let launchedByLegacyAgent: Bool
    let openLoginItemsSettings: () -> Void

    static var system: LoginItem {
        LoginItem(
            mainApp: SMAppService.mainApp,
            legacyAgents: legacyLabels.map { SMAppService.agent(plistName: "\($0).plist") },
            launchedByLegacyAgent: AppEnv.xpcServiceName.map(legacyLabels.contains) ?? false,
            openLoginItemsSettings: SMAppService.openSystemSettingsLoginItems
        )
    }

    var status: SMAppService.Status { mainApp.status }
    /// A leftover legacy registration still counts, so the user can see it and turn it off.
    var isEnabled: Bool { status == .enabled || legacyAgents.contains { $0.status == .enabled } }

    func setEnabled(_ enabled: Bool) throws {
        if !enabled {
            if !launchedByLegacyAgent { try legacyAgents.forEach(unregisterIfNeeded) }
            try unregisterIfNeeded(mainApp)
            if launchedByLegacyAgent { try legacyAgents.forEach(unregisterIfNeeded) }
            return
        }

        do {
            try registerMainAppIfNeeded()
        } catch {
            // register() can report a denial when the system already requires approval.
            guard status == .requiresApproval else { throw error }
        }
        if status == .requiresApproval {
            openLoginItemsSettings()
        } else {
            try removeLegacyAgentsAfterActivation()
        }
    }

    /// Run once at launch: an enabled legacy agent becomes a login item. A legacy agent that is not
    /// enabled (denied or awaiting approval) is not consent to start the app, so nothing is registered.
    func migrateFromLegacyAgentIfNeeded() {
        do {
            if legacyAgents.contains(where: { $0.status == .enabled }) { try registerMainAppIfNeeded() }
            try removeLegacyAgentsAfterActivation()
        } catch {
            AppLog.write("login item migration failed: \(error)")
        }
    }

    func removeLegacyAgentsAfterActivation() throws {
        guard status == .enabled, !launchedByLegacyAgent else { return }
        try legacyAgents.forEach(unregisterIfNeeded)
    }

    private func registerMainAppIfNeeded() throws {
        if !isRegistered(status) { try mainApp.register() }
    }

    private func unregisterIfNeeded(_ service: any LoginItemService) throws {
        if isRegistered(service.status) { try service.unregister() }
    }

    private func isRegistered(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }
}
