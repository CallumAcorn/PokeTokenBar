import XCTest
@testable import PokeTokenBar

// MARK: 하이퍼트레이닝 (병뚜껑)

/// 라인 로딩이 필요 없는 테스트용 provider — VitaminTests 와 같은 이유(진행 자체는 MonState 필드만
/// 건드리고, applyUsage 내부의 진화 판정은 currentLine 이 없으면 조용히 건너뛴다).
private struct HyperTrainNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class HyperTrainingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let trainingID = "ht-train"
    private let benchID = "ht-bench"

    /// 훈련 중인 개체(trainingID) + 벤치 개체(benchID) + 병뚜껑 재고를 지정한 상태 파일 로드.
    private func store(silver: Int = 1, gold: Int = 1) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ht-\(UUID().uuidString).json")
        let party = "[{\"id\":\"\(trainingID)\",\"baseID\":1,\"pathIDs\":[1],\"stageIndex\":0,\"usedAtStage\":0,"
            + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":false},"
            + "{\"id\":\"\(benchID)\",\"baseID\":4,\"pathIDs\":[4],\"stageIndex\":0,\"usedAtStage\":0,"
            + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":false}]"
        let inv = "{\"bottlecapSilver\":\(silver),\"bottlecapGold\":\(gold)}"
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":0,\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"party\":\(party),\"trainingSlotID\":\"\(trainingID)\",\"dex\":[],\"collectedFinals\":[],\"inventory\":\(inv)}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: HyperTrainNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 3))
    }

    private func use(_ s: CompanionStore, _ today: Int) {
        s.update(todayTokensByProvider: ["test": today], todayDate: "d", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
    }

    private func mon(_ s: CompanionStore, _ id: String) -> MonState? { s.state.party.first { $0.id == id } }

    /// The core contract: starting hyper training consumes the bottlecap immediately, progress rides
    /// the *same* usage delta that also levels the actively-training mon (not a competing resource),
    /// it works on a benched mon (not gated by the single trainingSlotID), and completion overrides
    /// `effectiveIVs` to 31 for the trained stat without ever touching the real `ivs` roll.
    func testStartHyperTrainingOnBenchedMonAccumulatesFromTheSameDeltaAsTrainingAndMaxesOnlyEffectiveIVs() {
        let s = store(silver: 1)
        XCTAssertTrue(s.canStartHyperTraining(.bottlecapSilver, target: .stat(.attack), on: benchID))
        XCTAssertTrue(s.startHyperTraining(.bottlecapSilver, target: .stat(.attack), on: benchID))
        XCTAssertEqual(s.itemCount(.bottlecapSilver), 0, "consumed at start, not completion")
        XCTAssertFalse(s.canStartHyperTraining(.bottlecapSilver, target: .stat(.attack), on: benchID), "no stock left")

        use(s, 0)   // seeds the provider ledger (no delta yet), same as CompanionTests' base()
        use(s, Bottlecap.thresholdPerStat / 2)
        XCTAssertEqual(mon(s, benchID)?.hyperTrainProgress, Bottlecap.thresholdPerStat / 2)
        XCTAssertFalse(mon(s, benchID)?.hyperTrainedStats.contains(.attack) ?? true, "below threshold — not done yet")
        XCTAssertEqual(mon(s, trainingID)?.usedAtStage, Bottlecap.thresholdPerStat / 2,
                       "the same delta still levels the active training mon — hyper training doesn't steal it")

        use(s, Bottlecap.thresholdPerStat)
        let trained = mon(s, benchID)
        XCTAssertTrue(trained?.hyperTrainedStats.contains(.attack) ?? false, "threshold crossed -> completed")
        XCTAssertNil(trained?.hyperTrainTarget, "target cleared on completion")
        XCTAssertNil(trained?.ivs, "the real IV roll is never written")
        XCTAssertEqual(trained?.effectiveIVs.attack, 31, "effectiveIVs reports the maxed stat instead")
        XCTAssertNotEqual(trained?.effectiveIVs.defense, 31, "only the trained stat is overridden")
    }

    /// Gold trains all six stats at once — no per-stat picker.
    func testGoldBottlecapTargetsAllSixStats() {
        let s = store(gold: 1)
        XCTAssertTrue(s.startHyperTraining(.bottlecapGold, target: .all, on: trainingID))
        use(s, 0)
        use(s, Bottlecap.thresholdAll)
        let trained = mon(s, trainingID)
        XCTAssertEqual(trained?.hyperTrainedStats, Set(StatKind.allCases))
        XCTAssertEqual(trained?.effectiveIVs.speed, 31)
    }

    func testCannotStartWithoutStockOrOnAnAlreadyTrainedStat() {
        let s = store(silver: 0, gold: 0)
        XCTAssertFalse(s.canStartHyperTraining(.bottlecapSilver, target: .stat(.hp), on: trainingID), "no stock")
        XCTAssertFalse(s.startHyperTraining(.bottlecapSilver, target: .stat(.hp), on: trainingID))
    }

    func testCannotStartASecondHyperTrainWhileOneIsInProgress() {
        let s = store(silver: 2)
        XCTAssertTrue(s.startHyperTraining(.bottlecapSilver, target: .stat(.hp), on: trainingID))
        XCTAssertFalse(s.canStartHyperTraining(.bottlecapSilver, target: .stat(.speed), on: trainingID))
        XCTAssertFalse(s.startHyperTraining(.bottlecapSilver, target: .stat(.speed), on: trainingID))
        XCTAssertEqual(s.itemCount(.bottlecapSilver), 1, "the rejected second start doesn't consume stock")
    }
}
