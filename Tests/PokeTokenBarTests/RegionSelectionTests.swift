import XCTest
@testable import PokeTokenBar

// MARK: 지역 필터 (region-selection.md)
//
// 등급 보증(eggTier)과 같은 자리·같은 방식으로 후보를 좁히는 필터라, 같은 두 경로(가중 인덱스 경로 +
// REST 폴백)를 각각 검증한다. SeededRNG / hatchIfNeeded 등은 CompanionTests.swift 의 내부 헬퍼 재사용.

/// 관동·성도·하나에 한 종씩 배치한 인덱스 — 지역 필터가 실제로 후보를 좁히는지 검증.
private struct RegionSpanningProvider: PokeProviding {
    static let entries = [
        BaseSpecies(id: 1, captureRate: 45),     // Kanto
        BaseSpecies(id: 152, captureRate: 45),   // Johto
        BaseSpecies(id: 494, captureRate: 45),   // Unova
    ]
    func baseSpeciesIndex() async throws -> [BaseSpecies] { Self.entries }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { Self.entries.first { $0.id == id } }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        guard let e = Self.entries.first(where: { $0.id == baseSpeciesID }) else { throw URLError(.badURL) }
        return EvoLine(baseID: e.id, tree: EvoNode(speciesID: e.id, children: []),
                       rarity: .common, names: [e.id: ["en": "M\(e.id)"]])
    }
}

/// GraphQL 인덱스가 죽고 REST 만 사는 상황 — 모든 id 가 base. chooseBaseViaREST 가 지역 range 안에서만
/// 굴리는지는 이 provider 로만 확인할 수 있다(가중 경로는 인덱스가 이미 후보를 정해 놓기 때문).
private struct RestOnlyAnyIDProvider: PokeProviding {
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw URLError(.badServerResponse) }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { BaseSpecies(id: id, captureRate: 45) }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .common, names: [baseSpeciesID: ["en": "M\(baseSpeciesID)"]])
    }
}

@MainActor
final class RegionSelectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("region-\(UUID().uuidString).json")
    }

    /// 부화 직전 알(임계 충족) + 지역 필터. seed 로 롤을 바꾼다.
    private func eggStore(region: Region?, seed: UInt64, provider: any PokeProviding) -> CompanionStore {
        let f = url()
        let regionJSON = region.map { "\"\($0.rawValue)\"" } ?? "null"
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":10000000,\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"active\":null,\"dex\":[],\"collectedFinals\":[],"
            + "\"eggUsage\":\(PokemonBalance.eggHatchThreshold),\"eggRegion\":\(regionJSON)}"
        try? json.data(using: .utf8)!.write(to: f)
        return CompanionStore(provider: provider, clock: { self.now }, fileURL: f, rng: SeededRNG(seed: seed))
    }

    func testWeightedRollRespectsRegionFilter() async {
        var pickedIDs: [Int] = []
        for seed in UInt64(1)...20 {
            let s = eggStore(region: .kanto, seed: seed, provider: RegionSpanningProvider())
            await s.hatchIfNeeded()
            if let id = s.trainingMon?.baseID { pickedIDs.append(id) }
        }
        XCTAssertEqual(pickedIDs.count, 20, "20회 모두 부화해야 필터가 실제로 검증된다")
        XCTAssertTrue(pickedIDs.allSatisfy { Region.kanto.includes(speciesID: $0) },
                      "관동 알에서 관동 밖 종(\(pickedIDs)) 부화")
    }

    /// 대조군 — 지역 제한이 없으면 풀 전체(관동·성도·하나)에서 나온다.
    func testWeightedRollWithoutRegionCanHatchOutsideKanto() async {
        var sawNonKanto = false
        for seed in UInt64(1)...20 {
            let s = eggStore(region: nil, seed: seed, provider: RegionSpanningProvider())
            await s.hatchIfNeeded()
            if let id = s.trainingMon?.baseID, !Region.kanto.includes(speciesID: id) { sawNonKanto = true; break }
        }
        XCTAssertTrue(sawNonKanto, "대조군이 관동 밖을 한 번도 안 뽑으면 결함 조건이 살아있지 않은 것")
    }

    func testRestFallbackRollsWithinRegionRange() async {
        var pickedIDs: [Int] = []
        for seed in UInt64(1)...20 {
            let s = eggStore(region: .johto, seed: seed, provider: RestOnlyAnyIDProvider())
            await s.hatchIfNeeded()
            if let id = s.trainingMon?.baseID { pickedIDs.append(id) }
        }
        XCTAssertEqual(pickedIDs.count, 20, "20회 모두 부화해야 폴백 경로가 실제로 검증된다")
        XCTAssertTrue(pickedIDs.allSatisfy { Region.johto.includes(speciesID: $0) },
                      "REST 폴백이 성도 밖 종(\(pickedIDs)) 을 뽑음 — 여전히 animatedSpeciesIDs 전체를 굴리고 있는 것")
    }

    func testRegionFilterSurvivesSave() {
        var imported = CompanionState()
        imported.eggRegion = .sinnoh
        imported.usedSinceInstall = 1_000_000
        let rebased = SaveTransfer.rebasedForThisDevice(imported, current: CompanionState(),
                                                        todayTokensByProvider: ["test": 0], todayDate: "d", hasUsageData: true)
        XCTAssertEqual(rebased.eggRegion, .sinnoh, "저장·이전 후에도 지역 필터 유지")
    }

    /// 실사용에서 잡힌 결함의 트리거 브랜치: 지역 A 로 이미 프리패치(pendingHatchID)해 둔 알 상태에서
    /// 지역을 B 로 바꾸면, hatchIfNeeded 는 pendingHatchID 를 무조건 신뢰하고 그대로 부화시킨다 —
    /// 그러면 화면엔 "B" 필터가 걸려 있는데 실제로는 A 종이 나와 필터가 조용히 깨진다.
    /// setEggRegion 이 지역이 바뀔 때 pendingHatchID 를 동기적으로 버리는지 직접 검증한다.
    func testChangingRegionDuringIncubationDiscardsStalePendingHatch() {
        let f = url()
        // 관동에서 이미 롤해 둔 프리패치(pendingHatchID:1)를 가진 알 상태를 그대로 파일로 구성.
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":10000000,\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"active\":null,\"dex\":[],\"collectedFinals\":[],"
            + "\"eggUsage\":0,\"eggRegion\":\"kanto\",\"pendingHatchID\":1}"
        try? json.data(using: .utf8)!.write(to: f)
        let s = CompanionStore(provider: RegionSpanningProvider(), clock: { self.now }, fileURL: f, rng: SeededRNG(seed: 1))
        XCTAssertEqual(s.state.pendingHatchID, 1, "테스트 전제 확인 — 관동 pre-roll이 세이브에 있어야 한다")
        s.setEggRegion(.johto)
        XCTAssertNil(s.state.pendingHatchID,
                     "지역을 바꿨는데 옛 지역 pre-roll이 남아있음 — 그대로 부화하면 필터가 깨진다")
    }

    /// 모르는 rawValue(구버전/미래 세이브 손상)는 제한 없음으로 안전하게 강등된다 — eggTier 와 같은 방향.
    func testUnknownRegionDecodesAsNoRestriction() throws {
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":0,\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"dex\":[],\"collectedFinals\":[],\"eggRegion\":\"kalos\"}"
        let decoded = try JSONDecoder().decode(CompanionState.self, from: json.data(using: .utf8)!)
        XCTAssertNil(decoded.eggRegion)
    }
}
