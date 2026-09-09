import Foundation

/// Phase 0 instrumentation for the "tokens per percent" study.
///
/// Purpose: find out whether a limit-window percentage can be converted into a token figure well
/// enough to attribute usage from surfaces that write no local transcripts (Claude Web, Design,
/// Cowork, Desktop chat). A first measurement over 21 hours of real data gave a **4x spread** in
/// tokens-per-percent on same-source intervals, which is far too loose to display as a number.
/// Three causes were identified, and this log exists to separate them:
///
///  1. **The five-hour window rolls**, so its delta nets additions against expiries and is not an
///     integral. Recording every window lets the analysis use `seven_day`, which does not roll
///     within a day.
///  2. **Cache reads are weighted differently from fresh generation.** Recording the four token
///     kinds separately lets the fit weight them independently rather than lumping them.
///  3. **Models are weighted differently.** Recording the per-model windows shows whether the
///     account meaningfully uses more than one.
///
/// This writes only values the app already holds and already displays. It adds no data source, no
/// network call and no credential read. It deliberately records **no account, org, or device
/// identifier**: `plan` is the subscription tier, which is needed to interpret window sizes and is
/// not an identifier.
///
/// JSONL so the study can be analysed line by line without loading the file whole, and so a torn
/// final line costs one sample rather than the set.
enum CalibrationLog {
    static let defaultsKey = "calibrationLoggingEnabled"

    /// On by default: the log is the only way to reach the Phase 1 decision gate, and it records
    /// nothing that is not already on screen. Turn it off in Settings → Advanced.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    static var fileURL: URL { url }

    private static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("PokeTokenBar.calibration.jsonl")
    }()

    private static let queue = DispatchQueue(label: "poketokenbar.calibration")

    /// Rotation cap. A sample is a few hundred bytes and the default poll is 2 minutes, so a week
    /// lands around 1 MB. 4 MB keeps roughly a month before one generation rotates out.
    private static let maxBytes = 4 * 1024 * 1024

    /// One observation. Field names are short because they repeat on every line.
    /// `Decodable` too — self-calibration (`selfCalibratedTokensPerPercent`) reads this log back.
    struct Sample: Codable {
        var t: Int                       // epoch seconds
        var plan: String?                // subscription tier, for interpreting window size
        var tier: String?
        var fh: Double?                  // five_hour utilisation
        var sd: Double?                  // seven_day
        var sdOpus: Double?
        var sdSonnet: Double?
        var scoped: [ScopedWindow]
        var providers: [ProviderTokens]

        struct ScopedWindow: Codable {
            var kind: String?
            var group: String?
            var model: String?
            var percent: Double?
        }

        struct ProviderTokens: Codable {
            var id: String
            var date: String
            var input: Int
            var output: Int
            var cacheWrite: Int
            var cacheRead: Int
            var total: Int
        }
    }

    /// Append one observation. Cheap and non-blocking; drops silently if disabled or unbundled.
    static func record(_ sample: Sample) {
        guard AppEnv.isBundledApp, isEnabled else { return }
        guard let data = try? JSONEncoder().encode(sample),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"

        queue.async {
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
               size > maxBytes {
                let old = url.deletingPathExtension().appendingPathExtension("old.jsonl")
                try? FileManager.default.removeItem(at: old)
                try? FileManager.default.moveItem(at: url, to: old)
            }
            guard let bytes = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: bytes)
            } else {
                try? bytes.write(to: url)
            }
        }
    }

    /// Build a sample from what the store already has. Pure, so it is testable without touching
    /// the filesystem — the impure part is `record` alone.
    static func makeSample(
        now: Date,
        limits: LimitStatus?,
        snapshots: [(id: String, today: DailyUsage?)]
    ) -> Sample {
        Sample(
            t: Int(now.timeIntervalSince1970),
            plan: limits?.subscriptionType,
            tier: limits?.rateLimitTier,
            fh: limits?.fiveHour?.utilization,
            sd: limits?.sevenDay?.utilization,
            sdOpus: limits?.sevenDayOpus?.utilization,
            sdSonnet: limits?.sevenDaySonnet?.utilization,
            scoped: (limits?.limits ?? []).map {
                Sample.ScopedWindow(kind: $0.kind, group: $0.group,
                                    model: $0.scope?.model?.displayName, percent: $0.percent)
            },
            providers: snapshots.compactMap { entry in
                guard let today = entry.today else { return nil }
                return Sample.ProviderTokens(
                    id: entry.id,
                    date: today.date,
                    input: today.inputTokens,
                    output: today.outputTokens,
                    cacheWrite: today.cacheCreationTokens,
                    cacheRead: today.cacheReadTokens,
                    total: today.totalTokens)
            })
    }

    /// Trust threshold for `selfCalibratedTokensPerPercent`. Below this many usable pairs the
    /// hardcoded `ExternalUsageCredit.tokensPerPercent` is a safer bet than a noisy per-account fit.
    ///
    /// **20, not 5.** Real data says 5 is not enough: measured against one account's 87 usable pairs
    /// (median 2.44M/point, raw ratios spanning 538x), a median over 5 randomly drawn pairs has a
    /// p10→p90 spread of **5.6x in the estimate itself**, which is as wide as the 5.33x spread that
    /// self-calibration was adopted to beat. At 5 pairs the fit is not an improvement on the
    /// constant, it is a differently-wrong number. The same account's first 5 pairs in chronological
    /// order (what a new user actually gets, since early samples cluster) land at 0.17x the
    /// full-history value.
    ///
    /// At 20 pairs that spread tightens to 2.1x, which is a real improvement. This matters more now
    /// that the rate also drives a **displayed** estimate, not only growth: a number on screen has to
    /// clear a higher bar than a pet growing at the wrong speed.
    static let minCalibrationPairs = 20

    /// Median tokens-per-percent from this account's own history, or `nil` when there isn't enough
    /// data yet (the caller falls back to the hardcoded constant). Pure — testable without touching
    /// the filesystem; `loadRecentSamples` is the impure counterpart that feeds it.
    ///
    /// Only pairs where the five-hour window rose **and** local provider tokens rose are used — a
    /// percent rise with flat local tokens is exactly the external-usage case this whole feature
    /// exists to attribute, and folding it into the calibration would teach the fit to explain away
    /// the thing it is supposed to measure.
    static func selfCalibratedTokensPerPercent(samples: [Sample]) -> Double? {
        var ratios: [Double] = []
        for (prev, next) in zip(samples, samples.dropFirst()) {
            guard let prevFH = prev.fh, let nextFH = next.fh else { continue }
            let deltaPercent = nextFH - prevFH
            guard deltaPercent > 0, deltaPercent.isFinite else { continue }
            let deltaTokens = next.providers.reduce(0) { $0 + $1.total }
                             - prev.providers.reduce(0) { $0 + $1.total }
            guard deltaTokens > 0 else { continue }
            ratios.append(Double(deltaTokens) / deltaPercent)
        }
        guard ratios.count >= minCalibrationPairs else { return nil }
        ratios.sort()
        let mid = ratios.count / 2
        return ratios.count.isMultiple(of: 2) ? (ratios[mid - 1] + ratios[mid]) / 2 : ratios[mid]
    }

    /// Read this account's own calibration samples back for `selfCalibratedTokensPerPercent`.
    /// Reads only the live file, not the rotated `.old.jsonl` — missing at most a day or two of
    /// history, never wrong data. Skips any line that fails to decode (a torn final line costs one
    /// sample, same tolerance `record`'s rotation already assumes).
    static func loadRecentSamples() -> [Sample] {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8)
        else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap {
            try? decoder.decode(Sample.self, from: Data($0.utf8))
        }
    }
}
