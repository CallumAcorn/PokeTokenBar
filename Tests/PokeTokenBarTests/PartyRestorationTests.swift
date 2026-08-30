import XCTest
@testable import PokeTokenBar

/// Restoring individuals that the old model discarded on graduation.
///
/// The current model keeps a graduated Pokémon in the PC and only frees the training slot. The old
/// one discarded `active` outright, and the `active` → `party` migration carried only the mon alive
/// at that moment — so anything graduated earlier survives as a catch-log row with no PC entry,
/// which contradicts what the new model promises.
///
/// Measured on a real save: a Seedot line graduated on 21 Aug was in the Pokédex and in
/// `collectedFinals`, but absent from the PC.
final class PartyRestorationTests: XCTestCase {

    private func entry(base: Int, chain: [Int], monID: String? = nil,
                       shiny: Bool = false, rarity: Rarity = .common) -> DexEntry {
        DexEntry(baseID: base, finalID: chain.last ?? base, chainOrder: chain, rarity: rarity,
                 caughtAt: Date(timeIntervalSince1970: 1_700_000_000), isShiny: shiny,
                 nature: nil, names: nil, monID: monID, source: .egg)
    }

    private func mon(id: String, base: Int, chain: [Int]) -> MonState {
        MonState(id: id, baseID: base, pathIDs: chain, stageIndex: chain.count - 1,
                 usedAtStage: 0, rarity: .common, totalForms: chain.count)
    }

    func testRestoresAGraduatedIndividualMissingFromThePC() {
        let restored = CompanionState.restoredPartyFromCatchLog(
            party: [], dex: [entry(base: 273, chain: [273, 274, 275])])
        XCTAssertEqual(restored.party.count, 1)
        XCTAssertEqual(restored.party.first?.baseID, 273)
        XCTAssertEqual(restored.party.first?.currentID, 275, "restored at its final form")
        XCTAssertEqual(restored.party.first?.totalForms, 3)
    }

    /// A log row pointing at a live party member is already represented — restoring it would
    /// duplicate the Pokémon currently being trained.
    func testDoesNotDuplicateALiveIndividual() {
        let live = mon(id: "abc", base: 163, chain: [163, 164])
        let restored = CompanionState.restoredPartyFromCatchLog(
            party: [live], dex: [entry(base: 163, chain: [163, 164], monID: "abc")])
        XCTAssertEqual(restored.party.count, 1)
        XCTAssertEqual(restored.party.first?.id, "abc")
    }

    /// [회귀] 위 테스트는 로그 행에 `monID` 가 **이미 박혀 있는** 경우만 밟는다. 실제 프로덕션 경로는
    /// `monID == nil` 인 행이 복원되는 쪽이고, `sanitized()` 는 **매 로드마다** 돈다. 복원이 만든 개체의
    /// id 를 그 행에 되쓰지 않으면 행은 영원히 nil 이라, 로드할 때마다 같은 행이 개체를 하나씩 더 만든다.
    /// (실측: 씨몬 라인 하나가 PC 에 3마리로 늘어 있었다 = 그 사이 로드 3회.)
    func testRepeatedLoadsDoNotDuplicateARestoredIndividual() {
        var s = CompanionState()
        s.dex = [entry(base: 273, chain: [273, 274, 275])]

        let once = SaveTransfer.sanitized(s)
        let twice = SaveTransfer.sanitized(once)
        let thrice = SaveTransfer.sanitized(twice)

        XCTAssertEqual(once.party.count, 1, "첫 로드는 빠진 개체를 복원해야 한다")
        XCTAssertEqual(twice.party.count, 1, "두 번째 로드가 같은 로그 행으로 개체를 또 만들었다")
        XCTAssertEqual(thrice.party.count, 1, "로드마다 무한히 늘어난다")
    }

    private func clone(base: Int, chain: [Int], at: Date, used: Int = 0) -> MonState {
        var m = MonState(id: UUID().uuidString, baseID: base, pathIDs: chain,
                         stageIndex: chain.count - 1, usedAtStage: used, rarity: .common,
                         totalForms: chain.count)
        m.acquiredAt = at
        return m
    }

    /// [회귀] 고친 코드는 더 만들지 않지만 **이미 저장된** 클론은 남는다. 사용자 실측 형태 그대로:
    /// 같은 로그 행에서 나온 씨몬 3마리가 id 만 다르고 `acquiredAt` 까지 마이크로초 단위로 같다.
    func testCollapsesClonesAlreadyPresentInTheSave() {
        let caught = Date(timeIntervalSince1970: 1_700_000_000)
        var s = CompanionState()
        s.dex = [entry(base: 273, chain: [273, 274, 275])]
        s.party = (0..<3).map { _ in clone(base: 273, chain: [273, 274, 275], at: caught) }

        let fixed = SaveTransfer.sanitized(s)
        XCTAssertEqual(fixed.party.count, 1, "이미 저장된 클론이 접히지 않았다")
        XCTAssertEqual(SaveTransfer.sanitized(fixed).party.count, 1, "복구 후 재로드가 다시 늘렸다")
    }

    /// 파괴적 동작의 안전판. 구버전 마이그레이션 세이브는 여러 개체가 **마이그레이션 시각을 공유**한다
    /// (`acquiredAt` 주석 참조). 로그 링크라는 증거 없이 시각만 보고 지우면 멀쩡한 개체가 사라진다.
    func testDoesNotCollapseWithoutLinkEvidence() {
        let migrated = Date(timeIntervalSince1970: 1_700_000_000)
        var s = CompanionState()
        s.party = [clone(base: 273, chain: [273, 274, 275], at: migrated),
                   clone(base: 273, chain: [273, 274, 275], at: migrated)]

        let out = SaveTransfer.sanitized(s)
        XCTAssertEqual(out.party.count, 2, "링크 증거가 없으면 아무것도 지우면 안 된다")
    }

    /// The case that makes the `monID != nil` guard load-bearing: a row that names an individual
    /// which is no longer in the party means it was **traded away**, not discarded on graduation.
    /// Restoring it would hand the user back a Pokémon they gave to someone else.
    func testDoesNotResurrectATradedAwayIndividual() {
        let restored = CompanionState.restoredPartyFromCatchLog(
            party: [], dex: [entry(base: 25, chain: [172, 25, 26], monID: "gone")])
        XCTAssertTrue(restored.party.isEmpty, "a traded individual must not come back")
    }

    /// An empty chain cannot make a decodable MonState — `MonState.init(from:)` rejects empty
    /// pathIDs, so restoring one would create state that fails to load next launch.
    func testSkipsAnEmptyChain() {
        let restored = CompanionState.restoredPartyFromCatchLog(
            party: [], dex: [entry(base: 1, chain: [])])
        XCTAssertTrue(restored.party.isEmpty)
    }

    func testRestoredIndividualCarriesShinyAndRarity() {
        let restored = CompanionState.restoredPartyFromCatchLog(
            party: [], dex: [entry(base: 133, chain: [133, 134], shiny: true, rarity: .rare)])
        XCTAssertEqual(restored.party.first?.isShiny, true)
        XCTAssertEqual(restored.party.first?.rarity, .rare)
    }

    /// Restoration runs on load, and must not change which Pokémon is being trained.
    func testSanitizeRestoresWithoutTouchingTheTrainingSlot() {
        var s = CompanionState()
        let live = mon(id: "live", base: 163, chain: [163, 164])
        s.party = [live]
        s.trainingSlotID = "live"
        s.dex = [entry(base: 163, chain: [163, 164], monID: "live"),
                 entry(base: 273, chain: [273, 274, 275])]

        let clean = SaveTransfer.sanitized(s)
        XCTAssertEqual(clean.party.count, 2, "the graduated individual should be back in the PC")
        XCTAssertEqual(clean.trainingSlotID, "live", "restoration must not change what is training")
        XCTAssertTrue(clean.dexUnlocked.keys.contains(275),
                      "restored individuals fold into dexUnlocked — restoration runs before backfill")
    }
}
