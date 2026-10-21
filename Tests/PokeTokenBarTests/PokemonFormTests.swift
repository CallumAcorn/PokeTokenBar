import XCTest
@testable import PokeTokenBar

// Ported from upstream 04b12da9 (#376) and 4bfae978 (#345), adapted to the fork's PC party,
// `dexUnlocked`, the per-species representative pin and `FormNameStore` names.

private enum FormTestError: Error { case offline }

private func node(_ id: Int, _ children: [EvoNode] = []) -> EvoNode { EvoNode(speciesID: id, children: children) }

/// Burmy (#412) branches into Wormadam (#413, cloaks) and Mothim (#414, single look).
private let burmyLine = EvoLine(baseID: 412, tree: node(412, [node(413), node(414)]), rarity: .common,
                                names: [412: ["en": "Burmy", "fr": "Cheniti"], 413: ["en": "Wormadam"],
                                        414: ["en": "Mothim"]])
private let shayminLine = EvoLine(baseID: 492, tree: node(492), rarity: .legendary,
                                  names: [492: ["en": "Shaymin", "fr": "Shaymin"]])
private let dittoLine = EvoLine(baseID: 132, tree: node(132), rarity: .rare, names: [132: ["en": "Ditto"]])
private let shellosLine = EvoLine(baseID: 422, tree: node(422, [node(423)]), rarity: .common,
                                  names: [422: ["en": "Shellos"], 423: ["en": "Gastrodon"]])

private struct FormTestProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        switch baseSpeciesID {
        case 412: return burmyLine
        case 492: return shayminLine
        case 422: return shellosLine
        case PokemonOdds.dittoSpeciesID: return dittoLine
        default: throw FormTestError.offline
        }
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw FormTestError.offline }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw FormTestError.offline }
}

@MainActor
final class PokemonFormTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let sky = PokemonForm("sky"), land = PokemonForm("land")
    private let sandy = PokemonForm("sandy"), plant = PokemonForm("plant"), trash = PokemonForm("trash")

    private func store(_ state: CompanionState, seed: UInt64 = 7) throws -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("forms-\(UUID().uuidString).json")
        try JSONEncoder().encode(state).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let date = now
        return CompanionStore(provider: FormTestProvider(), clock: { date }, fileURL: url,
                              rng: SeededRNG(seed: seed), dittoDisguiseRollingEnabled: false)
    }

    private func burmy(_ path: [Int], form: PokemonForm?, shiny: Bool = false) -> DexEntry {
        DexEntry(baseID: 412, finalID: path.last!, chainOrder: path, rarity: .common, caughtAt: now,
                 isShiny: shiny, nature: .brave, form: form)
    }

    private func mon(_ path: [Int], form: PokemonForm?, shiny: Bool = false) -> MonState {
        MonState(baseID: path[0], pathIDs: path, stageIndex: path.count - 1, usedAtStage: 0,
                 rarity: .common, totalForms: path.count, isShiny: shiny, form: form)
    }

    /// `dexUnlocked` is what "owns this species" reads; a real save fills it as stages are reached.
    private func unlocked(_ state: CompanionState) -> CompanionState {
        var s = state
        s.dexUnlocked = CompanionState.backfilledDexUnlocked(existing: [:], dex: s.dex, party: s.party)
        return s
    }

    // MARK: Catalog

    func testCatalogListsDefaultFirstWithinTheHatchableRange() {
        for (speciesID, entries) in PokemonForm.catalog {
            XCTAssertTrue(PokemonAssets.animatedSpeciesIDs.contains(speciesID), "#\(speciesID)")
            XCTAssertGreaterThanOrEqual(entries.count, 2, "#\(speciesID)")
            XCTAssertEqual(Set(entries.map(\.form)).count, entries.count, "#\(speciesID) repeats a form")
            XCTAssertEqual(entries.first?.formID, speciesID, "#\(speciesID) default is the species' own form")
            XCTAssertTrue(entries.dropFirst().allSatisfy { $0.formID > 10000 }, "#\(speciesID)")
        }
        XCTAssertEqual(PokemonForm.forms(speciesID: PokemonForm.unownSpeciesID).count, 28)
        XCTAssertEqual(PokemonForm.forms(speciesID: 493).count, 18)
        XCTAssertEqual(PokemonForm.forms(speciesID: 492), [land, sky])
        XCTAssertFalse(PokemonForm.hasForms(speciesID: 414), "Mothim's cloaks share one sprite")
        XCTAssertFalse(PokemonForm.hasForms(speciesID: 172), "Spiky-eared Pichu has no Gen V animation")
        XCTAssertFalse(PokemonForm.hasForms(speciesID: 592), "Gender differences are not forms")
    }

    func testLinesCarryFormsFromTheirBaseEvenWhenTheBaseLooksTheSame() {
        XCTAssertEqual(PokemonForm.formSpecies(baseID: 412), [412, 413])
        XCTAssertEqual(PokemonForm.lineForms(baseID: 412), [plant, sandy, trash])
        XCTAssertEqual(PokemonForm.formSpecies(baseID: 420), [421])
        XCTAssertEqual(PokemonForm.lineForms(baseID: 420), [PokemonForm("overcast"), PokemonForm("sunshine")])
        XCTAssertEqual(PokemonForm.lineForms(baseID: 554), [PokemonForm("standard"), PokemonForm("zen")])
        XCTAssertEqual(PokemonForm.lineForms(baseID: 1), [])
        XCTAssertEqual(PokemonForm.resolved(baseID: 420, form: nil), PokemonForm("overcast"))
        XCTAssertNil(PokemonForm.resolved(speciesID: 420, form: PokemonForm("sunshine")), "Cherubi has one look")
    }

    func testFormResolvesPerSpeciesOfTheLine() {
        XCTAssertEqual(PokemonForm.resolved(speciesID: 412, form: sandy), sandy)
        XCTAssertEqual(PokemonForm.resolved(speciesID: 413, form: sandy), sandy)
        XCTAssertNil(PokemonForm.resolved(speciesID: 414, form: sandy))
        XCTAssertEqual(PokemonForm.resolved(speciesID: 492, form: nil), land)
        XCTAssertEqual(PokemonForm.resolved(speciesID: 492, form: PokemonForm("future")), land)
        XCTAssertNil(PokemonForm.resolved(speciesID: 25, form: sky))
    }

    // MARK: Sprites

    func testVarietyFormsUseTheVarietyPNGAndTheFormGIF() {
        let base = SpriteStore.spriteBase
        func url(_ id: Int, animated: Bool, shiny: Bool, facing: SpriteFacing = .front, form: PokemonForm?) -> String? {
            SpriteStore.spriteURL(speciesID: id, animated: animated, shiny: shiny, facing: facing, form: form)?.absoluteString
        }
        XCTAssertEqual(url(492, animated: false, shiny: false, form: sky), "\(base)/10006.png")
        XCTAssertEqual(url(492, animated: false, shiny: true, form: sky), "\(base)/shiny/10006.png")
        XCTAssertEqual(url(492, animated: true, shiny: true, form: sky),
                       "\(base)/versions/generation-v/black-white/animated/shiny/492-sky.gif")
        XCTAssertEqual(url(412, animated: false, shiny: false, form: sandy), "\(base)/412-sandy.png")
        XCTAssertEqual(url(492, animated: false, shiny: false, form: land), "\(base)/492.png")
        XCTAssertEqual(url(414, animated: true, shiny: false, form: sandy),
                       "\(base)/versions/generation-v/black-white/animated/414.gif")
        XCTAssertEqual(url(412, animated: true, shiny: false, facing: .back, form: sandy),
                       "\(base)/versions/generation-v/black-white/animated/back/412-sandy.gif")
    }

    func testCacheKeysSeparateFormsAndKeepDefaultKeys() {
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 492, animated: false, shiny: false, form: sky), "492-sky-s")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 492, animated: true, shiny: true, form: sky), "492-sky-sha")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 492, animated: false, shiny: false, form: land),
                       SpriteStore.cacheKey(speciesID: 492, animated: false, shiny: false))
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 413, animated: false, shiny: false, facing: .back, form: sandy),
                       "413-sandy-bks")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: true, shiny: false), "25-a",
                       "caches written before forms existed stay valid")
    }

    func testSpriteViewReloadsWhenOnlyTheFormChanges() {
        XCTAssertTrue(SpriteView.needsReload(loadedID: 201, loadedShiny: false, id: 201, shiny: false,
                                             loadedForm: PokemonForm("a"), form: PokemonForm("b")))
        XCTAssertFalse(SpriteView.needsReload(loadedID: 201, loadedShiny: false, id: 201, shiny: false,
                                              loadedForm: PokemonForm("b"), form: PokemonForm("b")))
    }

    func testMenuSpriteKeyChangesWithThePinnedForm() {
        XCTAssertNotEqual(AppDelegate.menuSpriteKey(id: 201, shiny: false, floor: 0.1, form: PokemonForm("a")),
                          AppDelegate.menuSpriteKey(id: 201, shiny: false, floor: 0.1, form: PokemonForm("b")))
        XCTAssertEqual(AppDelegate.menuSpriteKey(id: 492, shiny: false, floor: 0.1, form: land),
                       AppDelegate.menuSpriteKey(id: 492, shiny: false, floor: 0.1))
    }

    /// Opt-in: every catalogued sprite, normal and shiny, still exists on PokéAPI.
    func testEveryCataloguedSpriteExistsOnPokeAPI() async throws {
        guard ProcessInfo.processInfo.environment["PTB_PARITY"] == "1" else {
            throw XCTSkip("set PTB_PARITY=1 to check PokéAPI sprites for every form")
        }
        for (speciesID, forms) in PokemonForm.catalog.mapValues({ $0.map(\.form) }) {
            for form in forms {
                for animated in [false, true] {
                    for shiny in [false, true] {
                        let url = try XCTUnwrap(SpriteStore.spriteURL(speciesID: speciesID, animated: animated,
                                                                      shiny: shiny, form: form))
                        var request = URLRequest(url: url)
                        request.httpMethod = "HEAD"
                        let (_, response) = try await URLSession.shared.data(for: request)
                        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, "\(url)")
                    }
                }
            }
        }
    }

    // MARK: Saves

    func testUpstreamUnownKeysAreRead() throws {
        let json = """
        {"pendingHatchID":201,"pendingUnownForm":"k","representativeSpeciesID":201,"representativeUnownForm":"q",
         "party":[{"id":"m1","baseID":201,"pathIDs":[201],"stageIndex":0,"usedAtStage":0,"rarity":"common",
                   "totalForms":1,"unownForm":"z"}],
         "dex":[{"baseID":201,"finalID":201,"chainOrder":[201],"rarity":"common","unownForm":"q"}]}
        """
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertEqual(state.pendingForm, PokemonForm("k"))
        XCTAssertEqual(state.party.first?.form, PokemonForm("z"))
        XCTAssertEqual(state.dex.first?.form, PokemonForm("q"))
        XCTAssertEqual(state.representativeForm, PokemonForm("q"))

        let reencoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        XCTAssertEqual((reencoded["party"] as? [[String: Any]])?.first?["form"] as? String, "z")
        XCTAssertEqual(reencoded["representativeForm"] as? String, "q")
        XCTAssertEqual(reencoded["pendingForm"] as? String, "k")
    }

    func testStoredFormIsNormalizedAgainstTheLine() throws {
        let json = """
        {"party":[{"id":"m1","baseID":412,"pathIDs":[412,413],"stageIndex":1,"usedAtStage":0,"rarity":"common",
                   "totalForms":2,"form":"sky"}],
         "dex":[{"baseID":1,"finalID":1,"chainOrder":[1],"rarity":"common","form":"sandy"}]}
        """
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertEqual(state.party.first?.form, plant, "A form from another line falls back to the line default")
        XCTAssertNil(state.dex.first?.form, "Lines without forms store none")
    }

    /// The trust boundary resolves forms built in memory too (a trade payload or a restored mon),
    /// not only those that went through `Decodable`.
    func testSanitizeResolvesFormsAndDropsAPreRollFormWithoutASpecies() {
        var state = CompanionState()
        var stray = mon([1], form: nil)
        stray.form = sandy
        state.party = [stray]
        var row = burmy([412], form: nil)
        row.form = sky
        state.dex = [row]
        state.pendingForm = sky
        let clean = SaveTransfer.sanitized(state)
        XCTAssertNil(clean.party.first { $0.id == stray.id }?.form)
        XCTAssertEqual(clean.dex.first?.form, plant)
        XCTAssertNil(clean.pendingForm, "No pre-rolled species, so no pre-rolled form")
    }

    /// A pre-roll saved before forms existed has no form: it must stay nil so the hatch rolls one,
    /// not decode or sanitize into the default (every Burmy would hatch with the Plant Cloak).
    func testAPreRollWithoutAStoredFormStaysUnresolved() throws {
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(#"{"pendingHatchID":412}"#.utf8))
        XCTAssertNil(state.pendingForm)
        XCTAssertNil(SaveTransfer.sanitized(state).pendingForm)
    }

    func testRestoringAMonFromTheCatchLogKeepsItsForm() {
        let row = burmy([412, 413], form: sandy)
        let restored = CompanionState.restoredPartyFromCatchLog(party: [], dex: [row])
        XCTAssertEqual(restored.party.first?.form, sandy)
    }

    // MARK: Collection

    func testEvolutionKeepsTheCloakAndMothimKeepsItsSingleLook() {
        var state = CompanionState()
        state.party = [mon([412, 413], form: sandy)]
        state.dex = [burmy([412, 414], form: sandy)]
        XCTAssertEqual(state.collectedForms(speciesID: 412), [sandy])
        XCTAssertEqual(state.collectedForms(speciesID: 413), [sandy])
        XCTAssertEqual(state.collectedForms(speciesID: 414), [])
    }

    func testLineFormCountsOnlyOnceEverySpeciesShowingItIsOwned() {
        var state = CompanionState()
        state.dex = [burmy([412, 414], form: sandy)]
        XCTAssertFalse(state.collectedLineForms(baseID: 412).contains(sandy), "Sandy Wormadam is still missing")
        state.dex.append(burmy([412, 413], form: sandy))
        XCTAssertEqual(state.collectedLineForms(baseID: 412), [sandy])
        XCTAssertEqual(state.collectedLineForms(baseID: 201), [])
    }

    /// Upstream 4bfae978: collected appearances are chosen one by one, and shine is per appearance.
    func testCollectedFormsAndTheirShineArePerAppearance() throws {
        var state = CompanionState()
        state.dex = [burmy([412, 413], form: sandy), burmy([412, 413], form: plant, shiny: true),
                     burmy([412, 414], form: trash)]
        let s = try store(unlocked(state))
        XCTAssertEqual(s.dexSpecies.map(\.id), [412, 413, 414], "the main dex keeps one cell per species")
        XCTAssertEqual(s.collectedForms(speciesID: 413), [plant, sandy])
        XCTAssertEqual(s.collectedForms(speciesID: 412), [plant, sandy, trash])
        XCTAssertTrue(s.collectedForms(speciesID: 414).isEmpty)
        XCTAssertTrue(s.ownsShinyForm(speciesID: 413, form: plant))
        XCTAssertFalse(s.ownsShinyForm(speciesID: 413, form: sandy), "plant's shine does not colour sandy")
    }

    func testPinningAFormNeedsThatFormCollected() throws {
        var state = CompanionState()
        state.dex = [burmy([412, 413], form: sandy)]
        let s = try store(unlocked(state))
        XCTAssertFalse(s.setRepresentative(413, form: trash), "Trash Wormadam is not owned")
        XCTAssertNil(s.representativeSpeciesID)
        XCTAssertTrue(s.setRepresentative(413, form: sandy))
        XCTAssertEqual(s.currentSpeciesID, 413)
        XCTAssertEqual(s.currentForm, sandy)
        s.clearRepresentative()
        XCTAssertNil(s.representativeForm)
        XCTAssertTrue(s.setRepresentative(413), "without a form named, the first collected one")
        XCTAssertEqual(s.representativeForm, sandy, "not the uncollected default plant cloak")
    }

    func testReconcileDropsAPinnedFormTheSaveNoLongerHas() {
        var state = CompanionState()
        state.dex = [burmy([412, 413], form: sandy)]
        state = unlocked(state)
        state.representativeSpeciesID = 413
        state.representativeForm = trash
        state.reconcileRepresentativeSelection()
        XCTAssertEqual(state.representativeSpeciesID, 413)
        XCTAssertEqual(state.representativeForm, sandy)
    }

    // MARK: Hatch

    func testHatchUsesThePreparedFormOfAnyLine() async throws {
        var state = CompanionState()
        state.pendingHatchID = 492
        state.pendingForm = sky
        state.eggUsage = PokemonBalance.eggHatchThreshold
        let s = try store(state)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.trainingMon?.baseID, 492)
        XCTAssertEqual(s.trainingMon?.form, sky)
        XCTAssertEqual(s.trainingForm, sky)
        XCTAssertEqual(s.state.dex.last?.form, sky, "the catch log row records the appearance")
        XCTAssertNil(s.state.pendingForm)
    }

    func testEvolutionNamesTheFormLikeHatchAndGraduation() async throws {
        let east = PokemonForm("east")
        var state = CompanionState()
        state.language = .en
        state.pendingHatchID = 422
        state.pendingForm = east
        state.eggUsage = PokemonBalance.eggHatchThreshold
        let s = try store(state)
        await s.hatchIfNeeded()
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 2, stageIndex: 0))
        XCTAssertEqual(s.trainingMon?.currentID, 423)
        XCTAssertEqual(s.justEvolvedTo, "Gastrodon [East]")
        XCTAssertEqual(s.state.dex.last?.form, east)
    }

    func testHatchWithoutPreparationRollsAmongTheLineForms() async throws {
        var seen = Set<PokemonForm>()
        for seed in UInt64(1)...24 {
            let s = try store(CompanionState(), seed: seed)
            await s.hatch(baseID: 412)
            let form = try XCTUnwrap(s.trainingMon?.form)
            XCTAssertTrue(PokemonForm.lineForms(baseID: 412).contains(form))
            seen.insert(form)
        }
        XCTAssertEqual(seen, Set(PokemonForm.lineForms(baseID: 412)))
    }

    func testLinesWithoutFormsHatchWithoutOne() async throws {
        let s = try store(CompanionState())
        await s.hatch(baseID: PokemonOdds.dittoSpeciesID)
        XCTAssertEqual(s.trainingMon?.baseID, PokemonOdds.dittoSpeciesID)
        XCTAssertNil(s.trainingMon?.form)
    }

    func testRevealedDittoDropsTheDisguiseForm() async throws {
        let json = """
        {"installBaselineSet":true,"usedSinceInstall":1000000000,"lastDate":"d1","dex":[],"collectedFinals":[],
         "active":{"baseID":412,"pathIDs":[412],"stageIndex":0,"usedAtStage":900000000,"rarity":"common",
                   "totalForms":2,"form":"sandy","dittoDisguise":412,"dittoRevealed":false}}
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("form-ditto-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let date = now
        let s = CompanionStore(provider: FormTestProvider(), clock: { date }, fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertEqual(s.currentForm, sandy)
        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                 limitWarning: false, hasUsageData: true)
        for _ in 0..<200 where !(s.trainingMon?.dittoRevealed ?? false) { await Task.yield() }
        XCTAssertEqual(s.trainingMon?.baseID, PokemonOdds.dittoSpeciesID)
        XCTAssertNil(s.trainingMon?.form)
        XCTAssertNil(s.currentForm)
    }

    // MARK: Names

    func testFormNamesComeFromTheProviderAndSkipUnown() async {
        let names = FormNameStore(provider: { id in id == 10064 ? ["fr": "Forme Céleste", "en": "Sky Forme"] : nil })
        XCTAssertEqual(PokemonForm.label(speciesID: 492, form: sky, language: .fr, names: names), "Sky",
                       "Identifier until PokéAPI answers")
        await names.load(speciesID: 492)
        XCTAssertEqual(PokemonForm.label(speciesID: 492, form: sky, language: .fr, names: names), "Forme Céleste")
        await names.load(speciesID: PokemonForm.unownSpeciesID)
        XCTAssertEqual(PokemonForm.label(speciesID: 201, form: PokemonForm("question"), language: .fr, names: names), "?")
        XCTAssertNil(PokemonForm.label(speciesID: 25, form: sky, language: .fr, names: names))
    }

    func testUnnamedUsualLooksUseLocalizedNormalForm() {
        let names = FormNameStore(provider: { _ in nil })
        for id in [351, 479, 646, 649] {
            XCTAssertEqual(PokemonForm.label(speciesID: id, form: nil, language: .en, names: names), "Normal Form")
        }
        XCTAssertEqual(PokemonForm.label(speciesID: 479, form: PokemonForm("heat"), language: .fr, names: names),
                       "Heat", "Named forms keep the identifier until PokéAPI answers")
    }

    func testDisplayNameShowsOnlyNonDefaultFormsExceptUnown() {
        XCTAssertEqual(PokemonForm.displayName("Shaymin", speciesID: 492, form: sky, label: "Forme Céleste"),
                       "Shaymin [Forme Céleste]")
        XCTAssertEqual(PokemonForm.displayName("Shaymin", speciesID: 492, form: land, label: "Forme Terrestre"),
                       "Shaymin")
        XCTAssertEqual(PokemonForm.displayName("Zarbi", speciesID: 201, form: PokemonForm("a"), label: nil), "Zarbi [A]")
        XCTAssertEqual(PokemonForm.displayName("Pikachu", speciesID: 25, form: sky, label: "Sky"), "Pikachu")
    }
}
