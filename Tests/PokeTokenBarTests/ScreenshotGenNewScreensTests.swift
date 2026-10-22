import XCTest
import SwiftUI
@testable import PokeTokenBar

/// README images for the Pokédex (search and forms), a species' forms, the Day Care and the usage
/// recap, rendered from the production views with a demo save. **Skipped by default**:
///
///     PTB_SCREENSHOT_DIR=assets swift test --filter ScreenshotGenNewScreensTests
///
/// The demo save and ledger are invented, so no one's real usage, spend or collection reaches the
/// public repo. Sprites are fetched into the normal sprite cache first: `SpriteView` seeds from that
/// cache synchronously, and `.task` never runs inside `ImageRenderer`.
@MainActor
final class ScreenshotGenNewScreensTests: XCTestCase {
    private static let languages: [(AppLanguage, String)] = [(.en, ""), (.ko, "-ko"), (.ja, "-ja")]
    private static let now = ISO8601DateFormatter().date(from: "2026-08-31T12:00:00Z")!

    private static let names: [Int: [String: String]] = [
        1: ["en": "Bulbasaur", "ko": "이상해씨", "ja": "フシギダネ"],
        4: ["en": "Charmander", "ko": "파이리", "ja": "ヒトカゲ"],
        25: ["en": "Pikachu", "ko": "피카츄", "ja": "ピカチュウ"],
        133: ["en": "Eevee", "ko": "이브이", "ja": "イーブイ"],
        151: ["en": "Mew", "ko": "뮤", "ja": "ミュウ"],
        201: ["en": "Unown", "ko": "안농", "ja": "アンノーン"],
        412: ["en": "Burmy", "ko": "도롱충이", "ja": "ミノムッチ"],
        413: ["en": "Wormadam", "ko": "도롱마담", "ja": "ミノマダム"],
        479: ["en": "Rotom", "ko": "로토무", "ja": "ロトム"],
        492: ["en": "Shaymin", "ko": "쉐이미", "ja": "シェイミ"],
        585: ["en": "Deerling", "ko": "사철록", "ja": "シキジカ"],
        586: ["en": "Sawsbuck", "ko": "바라철록", "ja": "メブキジカ"],
    ]
    private static let unownLetters = ["a", "b", "c", "k", "o", "q", "u", "z", "exclamation", "question"]
        .map { PokemonForm($0) }

    // MARK: Generators

    func testGenerateNewScreenScreenshots() async throws {
        guard let directory = ProcessInfo.processInfo.environment["PTB_SCREENSHOT_DIR"] else {
            throw XCTSkip("PTB_SCREENSHOT_DIR unset: assets are generated only for releases")
        }
        let (store, usage) = try Self.demoStores()
        try await Self.warmSprites(store.state)
        let out = URL(fileURLWithPath: directory)

        for (language, suffix) in Self.languages {
            store.setLanguage(language)
            let unown = try XCTUnwrap(store.dexSpecies.first { $0.id == PokemonForm.unownSpeciesID })
            let shots: [(String, AnyView)] = [
                ("screenshot-dex-search", AnyView(DexGridView(store: store, link: .constant(nil))
                    .frame(height: 284, alignment: .top).clipped())),
                ("screenshot-forms", AnyView(
                    DexSpeciesDetailView(store: store, species: unown, onClose: {}, scrolls: false)
                        .frame(height: 226, alignment: .top).clipped())),
                ("screenshot-day-care", AnyView(DayCareView(store: store, onClose: {}, scrolls: false))),
                ("screenshot-recap", AnyView(RecapCard(content: RecapContent(
                    store: usage, companion: store, scope: .month, offset: 0, now: Self.now,
                    calendar: RecapPeriod.calendar())))),
            ]
            for (name, view) in shots {
                let data = try Self.render(view, language: language)
                let url = out.appendingPathComponent("\(name)\(suffix).png")
                try data.write(to: url)
                print("wrote \(url.path) (\(data.count) bytes)")
            }
        }
    }

    // MARK: Demo save

    private static func entry(_ path: [Int], form: String? = nil, shiny: Bool = false, daysAgo: Int) -> DexEntry {
        DexEntry(baseID: path[0], finalID: path.last!, chainOrder: path, rarity: path[0] == 151 ? .legendary : .common,
                 caughtAt: now.addingTimeInterval(-Double(daysAgo) * 86_400), isShiny: shiny, nature: .modest,
                 names: Dictionary(uniqueKeysWithValues: path.compactMap { id in names[id].map { (id, $0) } }),
                 form: form.map { PokemonForm($0) })
    }

    private static func demoStores() throws -> (CompanionStore, UsageStore) {
        var state = CompanionState()
        state.installBaselineSet = true
        state.usedSinceInstall = 4_200_000_000
        state.lastDate = "2026-08-31"
        state.language = .en
        state.dex = [
            entry([1], daysAgo: 40), entry([4], daysAgo: 38), entry([25], shiny: true, daysAgo: 35),
            entry([151], daysAgo: 30), entry([479], form: "heat", daysAgo: 29), entry([492], form: "sky", daysAgo: 27),
            entry([585, 586], form: "autumn", daysAgo: 12), entry([585], form: "spring", daysAgo: 9),
            entry([412, 413], form: "trash", daysAgo: 6),
        ] + unownLetters.enumerated().map { index, letter in
            entry([201], form: letter.rawValue, daysAgo: 60 - index)
        }

        var eevee = MonState(baseID: 133, pathIDs: [133], stageIndex: 0, usedAtStage: 0, rarity: .common,
                             totalForms: 1, nature: .calm, gender: .female)
        eevee.id = "demo-eevee"
        var pikachu = MonState(baseID: 25, pathIDs: [25], stageIndex: 0, usedAtStage: 0, rarity: .common,
                               totalForms: 1, nature: .jolly, gender: .male)
        pikachu.id = "demo-pikachu"
        let burmy = MonState(baseID: 412, pathIDs: [412], plannedPathIDs: [412, 413], stageIndex: 0,
                             usedAtStage: 40_000_000, rarity: .common, totalForms: 2, nature: .bold,
                             gender: .female, form: PokemonForm("sandy"))
        state.party = [eevee, pikachu, burmy]
        state.trainingSlotID = burmy.id
        state.dex.append(entry([412], form: "sandy", daysAgo: 2))
        state.dex.append(entry([133], daysAgo: 20))
        state.dayCare = [DayCareSlot(
            slot: 0, parentIDs: [eevee.id, pikachu.id],
            traits: InheritedTraits(babySpeciesID: 133, parentIVs: [StatSpread(), StatSpread()], inheritedIVCount: 3,
                                    everstoneNature: .calm, hiddenAbilityParent: false, parentMoves: [], masuda: false),
            babyRarity: .common, target: 400_000_000, progress: 260_000_000, usedEverstone: true,
            babyNames: names[133])]
        state.dexUnlocked = CompanionState.backfilledDexUnlocked(existing: [:], dex: state.dex, party: state.party)
        state.representativeSpeciesID = PokemonForm.unownSpeciesID
        state.representativeForm = PokemonForm("q")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shots-\(UUID().uuidString).json")
        try JSONEncoder().encode(state).write(to: url)
        let clock = now
        let store = CompanionStore(provider: OfflineShotsProvider(), clock: { clock }, fileURL: url)

        let suite = "shots-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        var ledger = UsageLedger()
        let daily = [0, 0, 3_100_000, 4_800_000, 2_050_000, 5_600_000, 1_240_000, 480_000, 0, 4_100_000,
                     6_900_000, 3_300_000, 5_100_000, 900_000, 0, 140_000, 4_400_000, 2_600_000, 6_100_000,
                     3_900_000, 1_700_000, 0, 2_200_000, 5_400_000, 4_700_000, 3_050_000, 6_400_000, 2_800_000,
                     0, 1_900_000, 5_800_000]
        // July a little quieter than August, so the comparison reads like a real month.
        let july = daily.reversed().enumerated().map { index, tokens in
            DailyUsage(date: String(format: "2026-07-%02d", index + 1), inputTokens: 0, outputTokens: 0,
                       cacheCreationTokens: 0, cacheReadTokens: 0, totalTokens: tokens * 4 / 5, totalCost: 0)
        }
        ledger.merge(july
            + daily.enumerated().map { index, tokens in
                DailyUsage(date: String(format: "2026-08-%02d", index + 1), inputTokens: 0, outputTokens: 0,
                           cacheCreationTokens: 0, cacheReadTokens: 0, totalTokens: tokens, totalCost: 0)
            })
        ledger.save(to: defaults)
        return (store, UsageStore(providers: [], autoRefresh: false, defaults: defaults))
    }

    // MARK: Rendering

    private static func warmSprites(_ state: CompanionState) async throws {
        var wanted: Set<String> = []
        for entry in state.dex { for id in entry.chainOrder { wanted.insert("\(id)|\(entry.form?.rawValue ?? "")|\(entry.isShiny)") } }
        for mon in state.party { for id in mon.plannedPathIDs { wanted.insert("\(id)|\(mon.form?.rawValue ?? "")|false") } }
        for letter in unownLetters { wanted.insert("201|\(letter.rawValue)|true") }
        for key in wanted {
            let parts = key.split(separator: "|", omittingEmptySubsequences: false)
            let id = Int(parts[0])!
            let form = parts[1].isEmpty ? nil : PokemonForm(String(parts[1]))
            _ = await SpriteStore.shared.data(speciesID: id, animated: false, shiny: false, form: form)
            if parts[2] == "true" {
                _ = await SpriteStore.shared.data(speciesID: id, animated: false, shiny: true, form: form)
            }
        }
        _ = await SpriteLoader.eggImage()
    }

    /// Same frame as the existing README shots: popover width at 2x on the dark popover grey.
    private static func render(_ view: AnyView, language: AppLanguage) throws -> Data {
        let content = view
            .padding(.horizontal, PopoverMetrics.padding)
            .padding(.vertical, 14)
            .frame(width: PopoverMetrics.width, alignment: .topLeading)
            .background(Color(red: 41 / 255, green: 41 / 255, blue: 42 / 255))
            .environment(PopoverNavigation())
            .environment(\.colorScheme, .dark)
            .environment(\.locale, language.displayLocale)
        // An offscreen window rather than `ImageRenderer`: the latter draws AppKit-backed controls
        // (search field, toggles, menus, progress bars) as placeholders.
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: .darkAqua)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backingType = .buffered
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let pixels = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        let rep = try XCTUnwrap(pixels)
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}

private struct OfflineShotsProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}
