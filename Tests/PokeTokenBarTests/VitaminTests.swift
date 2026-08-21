import XCTest
@testable import PokeTokenBar

// MARK: 비타민 (EV 증가) + 상점 구매

/// 라인 로딩이 필요 없는 테스트용 provider — 비타민은 currentLine 과 무관(EV 는 MonState 에만 있음).
private struct VitaminNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class VitaminTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let monID = "vit-mon-1"

    /// 활성 포켓몬(id 고정) + 비타민 재고 + 기존 evs 를 지정한 상태 파일 로드.
    private func store(evs: StatSpread = StatSpread(), protein: Int = 1, used: Int = 1_000_000_000) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vitamin-\(UUID().uuidString).json")
        let evsJSON = "{\"hp\":\(evs.hp),\"attack\":\(evs.attack),\"defense\":\(evs.defense),"
            + "\"specialAttack\":\(evs.specialAttack),\"specialDefense\":\(evs.specialDefense),\"speed\":\(evs.speed)}"
        let party = "[{\"id\":\"\(monID)\",\"baseID\":1,\"pathIDs\":[1],\"stageIndex\":0,\"usedAtStage\":50000000,"
            + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":false,\"evs\":\(evsJSON)}]"
        let inv = protein > 0 ? ",\"inventory\":{\"protein\":\(protein)}" : ""
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":\(used),\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"party\":\(party),\"trainingSlotID\":\"\(monID)\",\"dex\":[],\"collectedFinals\":[]\(inv)}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: VitaminNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 7))
    }

    func testUseVitaminRaisesTargetStatByTenAndConsumesStock() {
        let s = store(protein: 2)
        XCTAssertTrue(s.canUseVitamin(.protein, on: monID))
        XCTAssertTrue(s.useVitamin(.protein, for: monID))
        XCTAssertEqual(s.trainingMon?.evs.attack, 10)
        XCTAssertEqual(s.trainingMon?.evs.hp, 0, "다른 스탯은 그대로")
        XCTAssertEqual(s.itemCount(.protein), 1, "재고 1 소모")
    }

    func testUseVitaminClampsAtPerStatCap() {
        let s = store(evs: StatSpread(attack: 245), protein: 1)
        XCTAssertTrue(s.useVitamin(.protein, for: monID))
        XCTAssertEqual(s.trainingMon?.evs.attack, Vitamin.evCapPerStat, "252 상한에서 클램프(245+10 대신 252)")
    }

    func testUseVitaminClampsAtTotalCap() {
        // attack 을 제외한 5스탯 합이 이미 505 — 남은 여유는 5, protein(+10)이 attack 에 5만 더함.
        let evs = StatSpread(hp: 101, attack: 0, defense: 101, specialAttack: 101, specialDefense: 101, speed: 101)
        let s = store(evs: evs, protein: 1)
        XCTAssertTrue(s.useVitamin(.protein, for: monID))
        XCTAssertEqual(s.trainingMon?.evs.attack, 5, "합계 510 상한에서 클램프")
    }

    /// 이미 상한(스탯 252 또는 합계 510)이면 canUseVitamin=false, useVitamin 은 재고를 축내지 않고 실패.
    func testUseVitaminNoOpAtCapDoesNotConsumeStock() {
        let s = store(evs: StatSpread(attack: 252), protein: 1)
        XCTAssertFalse(s.canUseVitamin(.protein, on: monID))
        XCTAssertFalse(s.useVitamin(.protein, for: monID))
        XCTAssertEqual(s.itemCount(.protein), 1, "실패한 사용은 재고를 소모하지 않는다")
        XCTAssertEqual(s.trainingMon?.evs.attack, 252)
    }

    func testUseVitaminWithNoStockFails() {
        let s = store(protein: 0)
        XCTAssertFalse(s.canUseVitamin(.protein, on: monID))
        XCTAssertFalse(s.useVitamin(.protein, for: monID))
    }

    func testUseVitaminOnUnknownMonIDFails() {
        let s = store(protein: 1)
        XCTAssertFalse(s.useVitamin(.protein, for: "no-such-mon"))
        XCTAssertEqual(s.itemCount(.protein), 1, "존재하지 않는 대상이면 재고 불변")
    }

    // MARK: 상점

    func testVitaminShopPriceAndPurchasable() {
        let s = store(protein: 0, used: 1_000_000_000)
        XCTAssertEqual(ItemKind.protein.shopPrice, Vitamin.price)
        XCTAssertTrue(s.canBuy(.protein))
        XCTAssertTrue(s.buy(.protein))
        XCTAssertEqual(s.itemCount(.protein), 1)
    }
}
