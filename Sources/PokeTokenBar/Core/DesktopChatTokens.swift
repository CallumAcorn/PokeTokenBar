import Foundation

/// Claude desktop's own running token counter for chat — `buddy-tokens.json` in its user-data
/// directory: `{"tokens-today": {"date": "YYYY-MM-DD", "tokens": N}}`.
///
/// Why this exists. Claude Chat (and Design, which now lives in chats as artifacts) runs entirely
/// server-side and writes no local transcript, so the app can only see it through the five-hour
/// window percentage — and that source depends on a Keychain OAuth token that only the standalone
/// `claude` CLI ever refreshes. For anyone who works in the desktop app, that token expires within
/// hours and every chat is invisible until the next manual login. This counter needs no login, no
/// token and no network: the desktop app keeps it itself.
///
/// What it measures (observed, not documented — it is another app's private file): it moves by tens
/// of thousands of tokens for a single chat turn, so it counts the whole request rather than only
/// the reply, and it does **not** move for Claude Code activity in the desktop's Code tab (a
/// 12,000-output-token Code message left it unchanged), so crediting it alongside the local Claude
/// Code transcripts does not double count.
///
/// It is *measured*, not estimated, which is why it can feed growth and the wallet without the
/// calibration spread that makes the window-percentage estimate unsafe to display.
enum DesktopChatTokens {
    struct Reading: Equatable, Sendable {
        /// The counter's own day bucket. Kept as the file wrote it — whether the desktop app rolls
        /// that over at local or UTC midnight is not documented, so nothing here assumes either.
        let date: String
        let tokens: Int
    }

    /// A day of chat cannot honestly reach this; anything above is a corrupt or hostile file, and
    /// the bound keeps every sum of readings far inside Int range.
    static let maxPlausibleTokens = 10_000_000_000

    /// The file is ~70 bytes. Refuse anything large instead of reading it whole.
    static let maxFileBytes = 4096

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/buddy-tokens.json")
    }

    /// Pure parse — separated from I/O so it can be tested without touching anyone's files.
    static func parse(_ data: Data) -> Reading? {
        guard data.count <= maxFileBytes,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let today = root["tokens-today"] as? [String: Any],
              let date = today["date"] as? String, isDayKey(date),
              let number = today["tokens"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value <= Double(maxPlausibleTokens) else { return nil }
        return Reading(date: date, tokens: Int(value))
    }

    /// Current reading, or nil when the file is absent, unreadable or malformed.
    ///
    /// Gated on `AppEnv.isBundledApp` so the unit-test process never reads a developer's real
    /// application-support directory, the same rule the rest of the app's live readers follow.
    static func read(url: URL = defaultURL, requireBundledApp: Bool = true) -> Reading? {
        if requireBundledApp, !AppEnv.isBundledApp { return nil }
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size <= maxFileBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    /// Tokens to credit for this reading given where the previous one left off, or nil when there is
    /// nothing to credit.
    ///
    /// - First sight (no cursor) seeds without crediting: the app was not watching, and counting a
    ///   whole day it never observed is exactly the retroactive claim the Claude Code ledger refuses.
    /// - Same day bucket: credit the increase. A *decrease* is a restart or reset of the counter, not
    ///   negative usage, so it credits nothing and the caller simply moves the cursor down.
    /// - New day bucket: the counter started again from zero, so everything in it is new.
    static func delta(lastDate: String?, lastTokens: Int?, reading: Reading) -> Int? {
        guard let lastDate, let lastTokens else { return nil }
        let gained = lastDate == reading.date ? reading.tokens - lastTokens : reading.tokens
        return gained > 0 ? gained : nil
    }

    /// Whether chat is being measured right now. Checks the opt-in first, so another app's file is
    /// never read for a user who has not asked for non-CLI Claude use to count.
    ///
    /// Readable is not enough: some desktop versions stopped writing the counter, leaving a file
    /// dated months back. Treating that as measuring switched the five-hour estimate off while
    /// nothing else counted chat, so only a counter dated around today counts.
    static func isMeasuring(enabled: Bool = ExternalUsageCredit.isEnabled,
                            read: () -> Reading? = { DesktopChatTokens.read() },
                            now: Date = Date()) -> Bool {
        guard enabled, let reading = read() else { return false }
        return isCurrent(reading, now: now)
    }

    /// The counter's day rollover (local or UTC midnight) is undocumented, so "current" accepts the
    /// local day, the local day before, and the UTC day.
    static func isCurrent(_ reading: Reading, now: Date) -> Bool {
        let local = LocalUsageReader.localDayFormatter()
        let utc = LocalUsageReader.localDayFormatter()
        utc.timeZone = TimeZone(identifier: "UTC")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        return [local.string(from: now), local.string(from: yesterday), utc.string(from: now)]
            .contains(reading.date)
    }

    private static func isDayKey(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0].count == 4 && parts[1].count == 2 && parts[2].count == 2
            && parts.allSatisfy { $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
    }
}

extension DesktopChatTokens {
    /// Provider id for the displayed totals. Deliberately kept out of `UsageStore.todayTokensByProvider`
    /// (the per-provider game ledger) and out of the calibration log — see those call sites.
    static let providerID = "claude_desktop_chat"
}

/// What the app has observed from the counter, attributed to the **local** day it was observed on.
///
/// The counter carries its own day bucket and the desktop app's choice of local or UTC midnight is
/// undocumented. Displayed totals and the game credit both come from *increases seen while watching*,
/// filed under the local day they were seen, so neither depends on which convention the app uses.
struct DesktopChatLedgerState: Codable, Equatable, Sendable {
    var cursorDate: String?
    var cursorTokens: Int?
    /// Local day (`yyyy-MM-dd`) → tokens observed that day.
    var days: [String: Int] = [:]
    /// Observed but not yet handed to the game. Handed over (and zeroed) by `take()`.
    var uncredited = 0

    private static let keptDays = 62

    mutating func observe(_ reading: DesktopChatTokens.Reading, localDay: String) {
        let hadCursor = cursorDate != nil && cursorTokens != nil
        if let gained = DesktopChatTokens.delta(lastDate: cursorDate, lastTokens: cursorTokens, reading: reading) {
            days[localDay, default: 0] += gained
            uncredited += gained
        } else if !hadCursor, reading.date == localDay {
            // First sight. Today's usage so far is real and measured, so it belongs in the displayed
            // totals, but the app was not watching, so it is not credited to the game.
            days[localDay, default: 0] += reading.tokens
        }
        cursorDate = reading.date
        cursorTokens = reading.tokens
        if days.count > Self.keptDays {
            let keep = Set(days.keys.sorted().suffix(Self.keptDays))
            days = days.filter { keep.contains($0.key) }
        }
    }

    /// The ledger is read back from UserDefaults, which is outside the app's control, and its values
    /// feed unchecked `+=` in the game. Clamp them to what one counter reading can be, or a corrupt
    /// value would trap on overflow and, being saved, on every launch after.
    func sanitized() -> DesktopChatLedgerState {
        let cap = DesktopChatTokens.maxPlausibleTokens
        func clamp(_ v: Int) -> Int { min(max(0, v), cap) }
        var s = self
        s.cursorTokens = cursorTokens.map(clamp)
        s.days = days.mapValues(clamp)
        s.uncredited = clamp(uncredited)
        return s
    }

    mutating func take() -> Int {
        defer { uncredited = 0 }
        return uncredited
    }

    /// Inclusive range over `yyyy-MM-dd` keys, which sort lexicographically.
    func total(from: String, through: String) -> Int {
        days.reduce(0) { $1.key >= from && $1.key <= through ? $0 + $1.value : $0 }
    }
}

/// Persisted, thread-safe wrapper. The provider observes during its fetch; the game takes what has
/// not yet been credited after the refresh. A per-device read position into another app's file, so it
/// lives in UserDefaults rather than the save and must not travel with a save transfer.
final class DesktopChatLedger: @unchecked Sendable {
    static let shared = DesktopChatLedger()

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var state: DesktopChatLedgerState
    private static let key = "desktopChatLedger"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(DesktopChatLedgerState.self, from: data) {
            state = saved.sanitized()
        } else {
            state = DesktopChatLedgerState()
        }
    }

    func observe(_ reading: DesktopChatTokens.Reading?, localDay: String = LocalUsageReader.todayKey()) {
        guard let reading else { return }
        lock.lock(); defer { lock.unlock() }
        state.observe(reading, localDay: localDay)
        persist()
    }

    func takeUncredited() -> Int {
        lock.lock(); defer { lock.unlock() }
        let taken = state.take()
        if taken != 0 { persist() }
        return taken
    }

    func total(from: String, through: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return state.total(from: from, through: through)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.key) }
    }
}

/// Claude desktop's chat counter as a usage provider, so chat shows up in Today / This week / This
/// month next to Claude Code. Token-only: the counter has no input/output/cache split and no price.
///
/// Gated on the same opt-in as crediting the game, so nothing reads another app's file unless the
/// user has asked for non-Claude-Code use to count.
struct LocalDesktopChatProvider: UsageProvider {
    let id = DesktopChatTokens.providerID
    let displayName = "Claude Chat"
    let reportsCost = false

    var ledger: DesktopChatLedger = .shared
    var reader: @Sendable () -> DesktopChatTokens.Reading? = { DesktopChatTokens.read() }

    func fetchDaily() async throws -> DailyUsage? {
        guard ExternalUsageCredit.isEnabled else { return nil }
        ledger.observe(reader())
        let today = LocalUsageReader.todayKey()
        let total = ledger.total(from: today, through: today)
        guard total > 0 else { return nil }
        return DailyUsage(date: today, inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0,
                          cacheReadTokens: 0, totalTokens: total, totalCost: 0)
    }

    func fetchEnrichment() async -> ProviderEnrichment {
        guard ExternalUsageCredit.isEnabled else { return ProviderEnrichment() }
        let now = Date()
        let format = LocalUsageReader.localDayFormatter()
        let today = format.string(from: now)
        let weekStart = format.string(from: LocalUsageReader.startOfWeek(now))
        let monthStart = format.string(from: LocalUsageReader.startOfMonth(now))
        var result = ProviderEnrichment()
        result.blocksOK = true   // no five-hour block for chat; nothing to show, nothing stale to keep
        result.weekTotal = PeriodUsage(period: weekStart, totalTokens: ledger.total(from: weekStart, through: today), totalCost: 0)
        result.monthTotal = PeriodUsage(period: LocalUsageReader.monthKey(now),
                                        totalTokens: ledger.total(from: monthStart, through: today), totalCost: 0)
        // The same calendar axis the log-based providers get, filled from the ledger, so chat shows in
        // the monthly trend on the right days.
        result.monthDaily = LocalUsageReader.monthDailySeries(entries: [], now: now).map { day in
            DailyUsage(date: day.date, inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0,
                       totalTokens: ledger.total(from: day.date, through: day.date), totalCost: 0)
        }
        result.periodsOK = true
        return result
    }
}
