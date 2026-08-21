import Foundation

/// 표시 상태 — 사용량/burn 으로 결정(스프라이트 모션 강도·상태 문구).
enum CompanionStateKind: String, Sendable {
    case egg, idle, working, focus, tired, sleep, levelUp
}

/// 앱 언어. 포켓몬 이름은 PokéAPI 다국어 names 에서 가져온다.
enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case ko, en, ja, es
    /// PokéAPI language.name 후보(첫 매칭 사용)
    var apiCodes: [String] {
        switch self {
        case .ko: return ["ko"]
        case .en: return ["en"]
        case .ja: return ["ja-Hrkt", "ja"]
        case .es: return ["es"]
        }
    }
    var label: String {
        switch self { case .ko: return "한국어"; case .en: return "English"; case .ja: return "日本語"; case .es: return "Español" }
    }

    var displayLocale: Locale { Locale(identifier: rawValue) }

    /// byLang(langCode→name) 에서 이 언어의 이름을 고른다(apiCodes 첫 매칭 → 영어 폴백).
    func resolveName(_ byLang: [String: String]) -> String? {
        for code in apiCodes { if let n = byLang[code] { return n } }
        return byLang["en"]
    }

    /// 신규 설치 기본 언어 — 시스템 선호 언어에서 유추(글로벌 출시: 한국어 강제 금지).
    /// ko/ja/es 만 매칭, 그 외 전부 영어(fallback-of-fallback). 기존 사용자는 저장된 언어를 그대로 쓴다.
    static var systemDefault: AppLanguage {
        switch Locale.preferredLanguages.first?.prefix(2).lowercased() {
        case "ko": return .ko
        case "ja": return .ja
        case "es": return .es
        default:   return .en
        }
    }
}

/// 희귀도 — PokéAPI capture_rate / is_legendary 로 판정.
enum Rarity: String, Codable, Sendable {
    case common, uncommon, rare, legendary
    /// 등급 크기(높을수록 희귀) — 두 `Rarity` 를 비교하기 위한 순위.
    /// **목록 정렬용이 아니다**: 포획 로그는 기록 시각순, 도감은 도감 번호순이고 희귀도는 필터로만 좁힌다.
    /// 유일한 소비자는 프리미엄 알의 보증 관문(`hatch` 의 `line.rarity.sortRank < tier.sortRank`) —
    /// 뽑힌 등급이 산 보증보다 낮은지 판정한다. 순서가 뒤집히면 고급/희귀 알이 조용히 낮은 등급을
    /// 통과시키므로 `testSortRankOrdersRarityAscendingByValue` 가 순서를 고정한다.
    var sortRank: Int {
        switch self {
        case .common:    return 0
        case .uncommon:  return 1
        case .rare:      return 2
        case .legendary: return 3
        }
    }
    /// 이 등급의 capture_rate 상한 — 이 값 이하면 그 종은 이 등급 **이상**이다.
    /// `from(captureRate:…)` 의 분류 임계이자, 프리미엄 알이 부화 후보를 미리 거르는 기준이다.
    /// 두 곳에 임계를 따로 적으면 한쪽만 바뀌었을 때 등급 보증이 조용히 깨지므로 **여기가 단일 소스**다.
    ///
    /// nil = capture_rate 로 표현할 수 없는 등급. 전설은 `is_legendary`/`is_mythical` 로만 판정되는데
    /// 부화 후보 인덱스(`BaseSpecies`)에는 그 플래그가 없다 → 전설 **전용** 알은 만들 수 없다(팔지도 않는다).
    /// 반대로 전설은 전원 capture_rate ≤ 45 라 하한을 *위로만* 벗어나므로, 고급/희귀 알의 capture_rate
    /// 필터에는 자연스럽게 포함된다("고급 이상"·"희귀 이상" 규칙이 그대로 성립).
    var captureRateCeiling: Int? {
        switch self {
        case .rare:      return 45
        case .uncommon:  return 120
        case .common:    return 255
        case .legendary: return nil
        }
    }
    /// capture_rate 가 이 등급 이상을 뜻하는지 — 전설은 capture_rate 로 판정할 수 없어 항상 false.
    func includes(captureRate: Int) -> Bool {
        guard let ceiling = captureRateCeiling else { return false }
        return captureRate <= ceiling
    }
    static func from(captureRate: Int, isLegendary: Bool, isMythical: Bool) -> Rarity {
        if isLegendary || isMythical { return .legendary }
        if Rarity.rare.includes(captureRate: captureRate) { return .rare }
        if Rarity.uncommon.includes(captureRate: captureRate) { return .uncommon }
        return .common
    }
}

/// 토큰 경제 — 실측 평균(~253M/일) 기준.
/// 졸업 총량 T 는 같은 희귀도면 진화 단계 수와 무관하게 동일.
/// 형태 k개 라인에서 i번째 형태 성장 비용 = T·i / (k(k+1)/2) → 합 = T, 단계↑일수록 비용↑.
enum PokemonBalance {
    /// 알 부화 임계 — 이만큼 토큰을 써야 알이 깨진다(즉시 부화 대신 기대감). 초과분은 부화체 성장에 이월.
    static let eggHatchThreshold = 5_000_000

    static func graduationTotal(_ rarity: Rarity) -> Int {
        switch rarity {
        case .common:    return    750_000_000
        case .uncommon:  return  1_875_000_000
        case .rare:      return  3_000_000_000
        case .legendary: return  6_000_000_000
        }
    }
    /// stageIndex(0-based)에서 다음 단계/졸업까지 필요한 토큰.
    static func phaseThreshold(rarity: Rarity, totalForms k: Int, stageIndex: Int) -> Int {
        let kk = max(1, k)
        let i = stageIndex + 1                         // 1-based
        let total = Double(graduationTotal(rarity))
        let denom = Double(kk * (kk + 1)) / 2.0
        return Int((total * Double(i) / denom).rounded())
    }

    /// 이 개체가 지금까지 누적 투입한 토큰 — 이미 통과한 단계들의 phaseThreshold 합 + 현재 단계 진행분.
    /// usedAtStage 는 단계마다 이월(진화 시 초과분만 남김)되므로, 레벨 표시엔 이 누적값을 써야 한다.
    static func cumulativeXP(rarity: Rarity, totalForms: Int, stageIndex: Int, usedAtStage: Int) -> Int {
        var sum = 0
        for i in 0..<max(0, stageIndex) { sum += phaseThreshold(rarity: rarity, totalForms: totalForms, stageIndex: i) }
        return sum + max(0, usedAtStage)
    }

    /// 표시 전용 레벨(Lv.1~100) — 진화 타이밍에는 관여하지 않는다(그건 여전히 phaseThreshold 가 정한다).
    /// 부화 직후 1, 졸업(누적 = graduationTotal) 무렵 100 에 도달하도록 기존 밸런스 상수를 그대로 재사용한다.
    static func level(rarity: Rarity, totalForms: Int, stageIndex: Int, usedAtStage: Int) -> Int {
        let total = graduationTotal(rarity)
        guard total > 0 else { return 1 }
        let xp = cumulativeXP(rarity: rarity, totalForms: totalForms, stageIndex: stageIndex, usedAtStage: usedAtStage)
        let frac = min(1.0, Double(xp) / Double(total))
        return 1 + Int((99.0 * frac).rounded(.down))
    }
}

/// 인벤토리 아이템 종류 — rawValue 로 CompanionState.inventory 에 저장.
/// 비타민 6종(hpUp/protein/iron/calcium/zinc/carbos) = 본가 EV 증가 아이템, 스탯 1개당 1종.
enum ItemKind: String, Codable, Sendable, CaseIterable {
    case rareCandy
    case mint
    case shinyCharm
    case hpUp, protein, iron, calcium, zinc, carbos

    /// PokéAPI 아이템 스프라이트 파일명(.../sprites/items/{name}.png). nil = 스프라이트 없음(이모지 폴백만).
    var spriteName: String? {
        switch self {
        case .rareCandy: return "rare-candy"
        case .mint: return nil   // PokéAPI 에 민트 스프라이트 없음(8세대 아이템) → 이모지 폴백
        case .shinyCharm: return "shiny-charm"
        case .hpUp: return "hp-up"
        case .protein: return "protein"
        case .iron: return "iron"
        case .calcium: return "calcium"
        case .zinc: return "zinc"
        case .carbos: return "carbos"
        }
    }
    /// 스프라이트 로딩 전/미제공/실패 시 폴백 이모지.
    var fallbackEmoji: String {
        switch self {
        case .rareCandy: return "🍬"
        case .mint: return "🌿"
        case .shinyCharm: return "✨"
        case .hpUp, .protein, .iron, .calcium, .zinc, .carbos: return "💊"
        }
    }
    /// 상점 판매가(재화 = 사용한 토큰). nil = 상점 미판매.
    var shopPrice: Int? {
        switch self {
        case .rareCandy: return RareCandy.price
        case .mint: return Mint.price
        case .shinyCharm: return ShinyCharm.price
        case .hpUp, .protein, .iron, .calcium, .zinc, .carbos: return Vitamin.price
        }
    }
    /// 보유형(패시브) 아이템 — 소비하지 않고 보유하는 동안 상시 효과. 1회 구매(재구매 불가), 가방엔 "적용 중" 표시.
    var isPassive: Bool {
        switch self {
        case .rareCandy, .mint, .hpUp, .protein, .iron, .calcium, .zinc, .carbos: return false
        case .shinyCharm: return true
        }
    }
    /// 이 비타민이 올리는 EV 필드 — 비타민이 아니면 nil(useVitamin 이 이걸로 대상 여부도 판정).
    var vitaminStat: WritableKeyPath<StatSpread, Int>? {
        switch self {
        case .hpUp: return \.hp
        case .protein: return \.attack
        case .iron: return \.defense
        case .calcium: return \.specialAttack
        case .zinc: return \.specialDefense
        case .carbos: return \.speed
        case .rareCandy, .mint, .shinyCharm: return nil
        }
    }
}

/// 비타민(EV 증가 아이템) 밸런스 상수 — 본가 규칙: 1개당 +10 EV, 스탯당 252·합계 510 상한.
enum Vitamin {
    static let evGain = 10
    static let evCapPerStat = 252
    static let evCapTotal = 510
    /// 상점 구매가 — 사탕(500M)보다 훨씬 싸게: EV 는 사탕처럼 레벨을 올리지 않는 순수 코스메틱에
    /// 가까운 전투 스탯 보정이라(이 앱엔 아직 전투가 없다) 가벼운 가격으로 둔다. 민트(100M)와 동급.
    static let price = 100_000_000
}

/// 이상한 사탕 밸런스 상수.
/// Growth credit for work that leaves no local transcript — Claude Web, Design, Cowork and
/// Desktop chat. Those surfaces write nothing locally, so the only evidence they ran is the
/// account-wide limit window moving.
///
/// The naive version of this double-counts: Claude Code moves the same window, so its usage would
/// grow the companion twice, once as real tokens and once again as window movement. Attributing
/// only the *residual* would need a tokens-per-percent constant, and a first measurement put that
/// at a 4x spread, which is not good enough to subtract with.
///
/// So credit is taken only from intervals where **local token counts did not move at all**. Any
/// window movement across such an interval cannot have come from a local CLI, so no subtraction
/// and no calibration is required. Intervals mixing both are skipped entirely, which under-counts
/// — the safe direction, and it still captures the case this exists for: a Design or Web session
/// with the CLIs idle.
enum ExternalUsageCredit {
    static let defaultsKey = "creditExternalUsage"

    /// Opt-in. It awards growth the app cannot show a token count for, so it should be a choice.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? false
    }

    /// Provisional conversion, from the median of 9 same-source intervals measured over 21 hours
    /// (684k to 2.75M tokens per 1%, median 1.28M). The 4x spread rules this out as a *displayed*
    /// token figure, but it is adequate for driving growth, where being within an order of
    /// magnitude is enough. Phase 1 of the calibration study replaces this with a fitted value.
    static let tokensPerPercent = 1_280_000

    /// A single percentage point is large, so cap one interval's award. Without this, a window
    /// reset misread as a rise, or a plan change, could graduate a companion in one poll.
    static let maxCreditPerInterval = 5 * tokensPerPercent

    /// XP to award for one interval, or nil when the interval is not eligible.
    ///
    /// Pure so the eligibility rules are testable without a store, a clock or a network.
    /// - `previousPercent`/`previousLocalTokens` nil means no baseline yet: establish one, award
    ///   nothing. That is also what happens on the first poll after launch.
    static func credit(previousPercent: Double?, currentPercent: Double?,
                       previousLocalTokens: Int?, currentLocalTokens: Int) -> Int? {
        guard let previousPercent, let currentPercent, let previousLocalTokens else { return nil }
        // Local activity in this interval — cannot separate the two sources without calibration.
        guard currentLocalTokens == previousLocalTokens else { return nil }
        let delta = currentPercent - previousPercent
        guard delta > 0, delta.isFinite else { return nil }        // reset, idle, or garbage
        let xp = Int(delta * Double(tokensPerPercent))
        return min(max(0, xp), maxCreditPerInterval)
    }
}

enum RareCandy {
    /// 사용 시 현재 포켓몬에 주입하는 XP(토큰 환산). 최소 진화 임계(커먼 1형태 125M)보다 작아
    /// 사탕 1개는 최대 1단계만 올린다(연쇄·졸업 폭주 없음). applyUsage 로 주입 → 이월/진화/졸업 자동.
    static let xp = 100_000_000
    /// 주간 한도 100% 도달 시 지급 개수(세션급은 1개).
    static let weeklyGrant = 5
    /// 상점 구매가(재화 = 사용한 토큰: usedSinceInstall − spentTokens). XP 값어치(100M)의 5배.
    /// 토큰이 "성장 미터 + 상점 지갑"으로 이중 사용되는 구조라, 가격을 XP 와 같게 두면 구매가 사실상
    /// 공짜 추가성장(150M 써서 250M 성장)이 된다. 500M 로 두면 그 값 모으는 500M 패시브 성장 + 사탕
    /// 100M = 실질 보너스 +20% 로 억제된다. 무료 획득(한도 100% 보상)이 항상 이득이도록 값어치보다 비싸게.
    static let price = 500_000_000
}

/// 민트 밸런스 상수.
enum Mint {
    /// 상점 구매가. 성격 변경은 순수 코스메틱(성장·능력치 무관)이라 밸런스 근거가 없어 "느낌" 값 —
    /// 사탕(500M)의 1/5로 싸게 둬서 성격을 마음에 들 때까지 굴려보는 가벼운 재미. 성장을 안 줘서
    /// 이중계산 이슈도 없음(가격 = 순수 소비).
    static let price = 100_000_000
}

/// 이로치 부적 밸런스 상수 — 보유형(1회 구매·영구, 소비 안 됨).
enum ShinyCharm {
    /// 상점 구매가. 앞으로의 모든 부화에 적용되는 영구 럭 업그레이드라 프리미엄(레어 1마리 졸업분=3B).
    static let price = 3_000_000_000
    /// 보유 시 이로치 부화 확률 분모 — 1/64 → 1/48 (+33%). 본가 '반짝이 부적'(이로치 확률↑) 오마주.
    /// ×2(1/32)는 과해 절제. 이미 부화한 개체엔 소급 없음(이로치는 부화 순간 확정).
    static let shinyDenominator: UInt64 = 48
}

/// 새 알(리롤) 밸런스 상수 — 상점 구매 시 현재 포켓몬을 폐기하고 새 알로 되돌린다.
enum FreshEgg {
    /// 상점 구매가. 마음에 안 드는 부화를 리롤하는 프리미엄(쌓인 토큰의 활용처). 폐기 개체는 졸업이
    /// 아니라 그냥 사라지므로 도감·확률(collectedFinals)에 무영향 — "뽑은 적 없던 것처럼". 새 알은
    /// 처음부터 재인큐베이션(5M) 필요 + 성장(usedAtStage) 소멸이라 스팸/파밍이 자연 억제된다.
    static let price = 1_000_000_000

    /// 상점에서 파는 알 — 보증 없음(기본) → 고급 이상 → 희귀 이상. `nil` = 등급 보증 없는 기존 알.
    /// **전설 전용 알은 팔지 않는다**(등급 하한을 capture_rate 로 표현할 수 없고, 최고 등급을 확정
    /// 상품으로 만들지 않는다). 전설은 고급/희귀 알에서 자연 가중대로 섞여 나온다 — 희귀 알 기준 약 10%.
    static let shopTiers: [Rarity?] = [nil, .uncommon, .rare]

    /// 등급 보증 알의 가격 — 배율은 새 상수를 짓지 않고 **기존 졸업 총량 표**를 그대로 쓴다
    /// (common 750M : uncommon 1.875B : rare 3B = 1 : 2.5 : 4 → 1B / 2.5B / 4B).
    ///
    /// 확률 배율(고급 7.16% : 희귀 6.98% ≈ 1 : 2.03)로 매기면 안 된다 — 그러면 같은 값으로 고급 알
    /// 2개를 사는 쪽이 희귀+ 기대 1.039마리·전설 0.104마리로 희귀 알 1개(1.000·0.100)를 모든 축에서
    /// 앞질러 상위 티어가 완전 열등재가 된다. 졸업량 배율이라야 상위 티어가 희귀+ 1마리당 4.00B 로
    /// 하위 반복 구매(4.81B)보다 싸다.
    static func price(guaranteeing tier: Rarity?) -> Int {
        guard let tier else { return price }
        let multiplier = Double(PokemonBalance.graduationTotal(tier)) / Double(PokemonBalance.graduationTotal(.common))
        return Int((Double(price) * multiplier).rounded())
    }
}

/// 상점 표시 한 줄 — 판매 아이템(ItemKind) 또는 알 리롤(즉시 액션이라 ItemKind 가 아님).
/// `egg` 의 연관값은 **보증 등급 하한**(nil = 보증 없는 기존 알).
/// CompanionStore.shopEntries 가 이 둘을 가격 오름차순으로 병합해 뷰가 단일 목록으로 그린다.
enum ShopEntry: Hashable, Sendable {
    case item(ItemKind)
    case egg(Rarity?)

    var price: Int {
        switch self {
        case .item(let kind): return kind.shopPrice ?? 0
        case .egg(let tier): return FreshEgg.price(guaranteeing: tier)
        }
    }
}

/// 사탕 지급 대상 한도 창의 분류 — session=1개·weekly=weeklyGrant.
enum WindowClass: Sendable { case session, weekly }

/// 사탕 지급 판정 입력 — 프로바이더 무관 한도 창 1개. (UsageStore.candyEligibleWindows 가 생성)
struct CandyWindow: Sendable {
    let key: String          // 안정 식별자(tier 추적) — resets_at 등 휘발 필드 금지
    let name: String         // 표시용(알림 "왜 받는지")
    let kind: WindowClass    // session=1개 · weekly=5개
    let utilization: Double  // 0~100+
}

/// 사탕 지급 1건(순수 판정 결과) — 부수효과(인벤토리·알림)와 분리해 테스트 가능하게.
struct CandyGrant: Equatable, Sendable {
    let windowKey: String
    let windowName: String   // 알림 "왜 받는지"
    let count: Int
}

/// 현재 서비스가 제공하는 움직이는 포켓몬 스프라이트 범위.
/// PokéAPI 의 Gen-V animated 에셋은 전국도감 #1...649까지만 존재한다.
enum PokemonAssets {
    static let animatedSpeciesIDs = 1...649

    static func hasAnimatedSprite(speciesID: Int) -> Bool {
        animatedSpeciesIDs.contains(speciesID)
    }
}

/// 알 후보 풀을 한 세대(지역)로 제한하는 필터. 종 ID 가 세대별로 연속 구간이라 새 데이터 없이
/// 순수 ID 범위로 표현한다(chooseBase/chooseBaseViaREST 가 이 range 로 후보를 좁힌다).
/// **상한은 설계다, 버그가 아니다**: 애니메이션 스프라이트가 전국도감 #649(하나)까지만 있어
/// 6세대 이후는 새 스프라이트 에셋 없이 이 기능으로 다다를 수 없다.
enum Region: String, Codable, Sendable, Hashable, CaseIterable {
    case kanto, johto, hoenn, sinnoh, unova

    var speciesRange: ClosedRange<Int> {
        switch self {
        case .kanto:  return 1...151
        case .johto:  return 152...251
        case .hoenn:  return 252...386
        case .sinnoh: return 387...493
        case .unova:  return 494...649
        }
    }

    func includes(speciesID: Int) -> Bool { speciesRange.contains(speciesID) }
}

/// PokéAPI evolution-chain 을 파싱한 트리. 분기(evolves_to 다수)를 children 으로.
struct EvoNode: Codable, Sendable {
    let speciesID: Int
    let children: [EvoNode]

    /// 최장 경로 길이(형태 수). 분기는 보통 같은 깊이라 대표값으로 사용.
    var depth: Int { 1 + (children.map(\.depth).max() ?? 0) }
    func node(withID id: Int) -> EvoNode? {
        if speciesID == id { return self }
        for c in children { if let f = c.node(withID: id) { return f } }
        return nil
    }
    /// 이 노드에서 도달 가능한 모든 최종체 id
    var finalIDs: [Int] {
        children.isEmpty ? [speciesID] : children.flatMap(\.finalIDs)
    }

    /// self(뿌리)에서 target 까지의 조상 경로(뿌리→target 순서, target 포함). 없으면 nil.
    /// 도감 종 개요(DexSpeciesDetailView)가 개체의 pathIDs 없이도 CompanionStore.lineItems 를
    /// 재사용할 수 있게 해준다 — "이 종에 도달했다"는 도감 언락 자체가 그 경로 전체를 지나왔다는
    /// 증거라(진화는 항상 앞으로만 가므로) 조상 구간을 전부 .done 취급해도 안전하다.
    func pathToNode(_ target: Int) -> [Int]? {
        if speciesID == target { return [speciesID] }
        for c in children {
            if let sub = c.pathToNode(target) { return [speciesID] + sub }
        }
        return nil
    }

    /// 서비스에 GIF 에셋이 있는 종만 남긴 진화 트리. 지원하지 않는 종부터 그 하위 체인도 제외한다.
    func keepingAnimatedSprites() -> EvoNode? {
        guard PokemonAssets.hasAnimatedSprite(speciesID: speciesID) else { return nil }
        return EvoNode(speciesID: speciesID, children: children.compactMap { $0.keepingAnimatedSprites() })
    }
}

enum EvoLineItemContent: Equatable, Sendable {
    case species(Int)
    case mystery
}

enum EvoLineItemState: Equatable, Sendable {
    case done
    case current
    case future
}

struct EvoLineItem: Equatable, Sendable {
    let content: EvoLineItemContent
    let state: EvoLineItemState

    init(_ content: EvoLineItemContent, _ state: EvoLineItemState) {
        self.content = content
        self.state = state
    }
}

/// 부화 시 확정되는 라인 정보(트리 + 희귀도 + 다국어 이름).
struct EvoLine: Sendable {
    let baseID: Int
    let tree: EvoNode
    let rarity: Rarity
    /// speciesID → (langCode → name)
    let names: [Int: [String: String]]
    var totalForms: Int { tree.depth }

    init(baseID: Int, tree: EvoNode, rarity: Rarity, names: [Int: [String: String]]) {
        self.baseID = baseID
        self.tree = tree.keepingAnimatedSprites() ?? EvoNode(speciesID: baseID, children: [])
        self.rarity = rarity
        self.names = names
    }

    func localizedName(_ id: Int, _ lang: AppLanguage) -> String {
        lang.resolveName(names[id] ?? [:]) ?? "#\(id)"   // 폴백 순서는 AppLanguage.resolveName 단일 소스
    }
}

/// 능력치 5종 — HP 는 성격 보정을 받지 않아(본가 규칙) 이 열거형엔 없다.
enum Stat: String, Codable, Sendable, CaseIterable {
    case attack, defense, specialAttack, specialDefense, speed
}

/// 성격 — 본가 25종. 부화 시 확정. `Phase B`(stats.md)부터 실제 능력치 보정(±10%)을 갖는다 —
/// 그전엔 개체 아이덴티티 표시용 코스메틱 필드였다.
enum PokemonNature: String, Codable, Sendable, CaseIterable {
    case hardy, lonely, brave, adamant, naughty
    case bold, docile, relaxed, impish, lax
    case timid, hasty, serious, jolly, naive
    case modest, mild, quiet, bashful, rash
    case calm, gentle, sassy, careful, quirky

    /// 오르는 능력치(+10%) — 중립 성격(하디/도사일/시리어스/배시풀/퀄키)은 nil.
    var boostedStat: Stat? { modifiers.0 }
    /// 내리는 능력치(-10%) — 중립 성격은 nil.
    var loweredStat: Stat? { modifiers.1 }
    private var modifiers: (Stat?, Stat?) {
        switch self {
        case .hardy, .docile, .serious, .bashful, .quirky: return (nil, nil)
        case .lonely:  return (.attack, .defense)
        case .brave:   return (.attack, .speed)
        case .adamant: return (.attack, .specialAttack)
        case .naughty: return (.attack, .specialDefense)
        case .bold:    return (.defense, .attack)
        case .relaxed: return (.defense, .speed)
        case .impish:  return (.defense, .specialAttack)
        case .lax:     return (.defense, .specialDefense)
        case .timid:   return (.speed, .attack)
        case .hasty:   return (.speed, .defense)
        case .jolly:   return (.speed, .specialAttack)
        case .naive:   return (.speed, .specialDefense)
        case .modest:  return (.specialAttack, .attack)
        case .mild:    return (.specialAttack, .defense)
        case .quiet:   return (.specialAttack, .speed)
        case .rash:    return (.specialAttack, .specialDefense)
        case .calm:    return (.specialDefense, .attack)
        case .gentle:  return (.specialDefense, .defense)
        case .sassy:   return (.specialDefense, .speed)
        case .careful: return (.specialDefense, .specialAttack)
        }
    }

    /// 본가 공식 번역 명칭 (ko/en/ja/es).
    func name(_ lang: AppLanguage) -> String {
        let names: (String, String, String, String)
        switch self {
        case .hardy:   names = ("노력", "Hardy", "がんばりや", "Fuerte")
        case .lonely:  names = ("외로움", "Lonely", "さみしがり", "Huraña")
        case .brave:   names = ("용감", "Brave", "ゆうかん", "Audaz")
        case .adamant: names = ("고집", "Adamant", "いじっぱり", "Firme")
        case .naughty: names = ("개구쟁이", "Naughty", "やんちゃ", "Pícara")
        case .bold:    names = ("대담", "Bold", "ずぶとい", "Osada")
        case .docile:  names = ("온순", "Docile", "すなお", "Dócil")
        case .relaxed: names = ("무사태평", "Relaxed", "のんき", "Plácida")
        case .impish:  names = ("장난꾸러기", "Impish", "わんぱく", "Agitada")
        case .lax:     names = ("촐랑", "Lax", "のうてんき", "Floja")
        case .timid:   names = ("겁쟁이", "Timid", "おくびょう", "Miedosa")
        case .hasty:   names = ("성급", "Hasty", "せっかち", "Activa")
        case .serious: names = ("성실", "Serious", "まじめ", "Seria")
        case .jolly:   names = ("명랑", "Jolly", "ようき", "Alegre")
        case .naive:   names = ("천진난만", "Naive", "むじゃき", "Ingenua")
        case .modest:  names = ("조심", "Modest", "ひかえめ", "Modesta")
        case .mild:    names = ("의젓", "Mild", "おっとり", "Afable")
        case .quiet:   names = ("냉정", "Quiet", "れいせい", "Mansa")
        case .bashful: names = ("수줍음", "Bashful", "てれや", "Tímida")
        case .rash:    names = ("덜렁", "Rash", "うっかりや", "Alocada")
        case .calm:    names = ("차분", "Calm", "おだやか", "Serena")
        case .gentle:  names = ("얌전", "Gentle", "おとなしい", "Amable")
        case .sassy:   names = ("건방", "Sassy", "なまいき", "Grosera")
        case .careful: names = ("신중", "Careful", "しんちょう", "Cauta")
        case .quirky:  names = ("변덕", "Quirky", "きまぐれ", "Rara")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2; case .es: return names.3 }
    }
}

/// 능력치 6종 값 묶음 — IV(0~31, 부화 시 확정)와 EV(0~252, 소비 아이템으로 누적)에 재사용.
struct StatSpread: Codable, Sendable, Equatable {
    var hp = 0, attack = 0, defense = 0, specialAttack = 0, specialDefense = 0, speed = 0
}

/// 본가 3세대+ 실전 능력치 계산 — 기준치(PokéAPI base stat) + IV + EV + 레벨 + 성격 보정.
enum StatCalc {
    struct Computed: Sendable {
        let hp, attack, defense, specialAttack, specialDefense, speed: Int
    }

    private static func core(_ base: Int, _ iv: Int, _ ev: Int, level: Int) -> Int {
        (2 * base + iv + ev / 4) * level / 100
    }

    static func compute(base: BaseStats, ivs: StatSpread, evs: StatSpread, level: Int,
                        nature: PokemonNature?) -> Computed {
        func other(_ base: Int, _ iv: Int, _ ev: Int, _ stat: Stat) -> Int {
            let raw = core(base, iv, ev, level: level) + 5
            guard let nature else { return raw }
            if nature.boostedStat == stat { return Int((Double(raw) * 1.1).rounded(.down)) }
            if nature.loweredStat == stat { return Int((Double(raw) * 0.9).rounded(.down)) }
            return raw
        }
        return Computed(
            hp: core(base.hp, ivs.hp, evs.hp, level: level) + level + 10,
            attack: other(base.attack, ivs.attack, evs.attack, .attack),
            defense: other(base.defense, ivs.defense, evs.defense, .defense),
            specialAttack: other(base.specialAttack, ivs.specialAttack, evs.specialAttack, .specialAttack),
            specialDefense: other(base.specialDefense, ivs.specialDefense, evs.specialDefense, .specialDefense),
            speed: other(base.speed, ivs.speed, evs.speed, .speed))
    }

    /// 이 스탯이 낼 수 있는 실전값의 최소~최대 — 레벨 100, IV/EV/성격 전부 최악 vs 최선일 때.
    /// 도감 종 개요("이 종은 어디까지 나올 수 있나")용 — 이미 확정된 개체 하나의 값이 아니라 종 전체의
    /// 잠재 범위를 보여주는 별개 질문이라 compute() 를 그대로 쓰지 않고 같은 core() 를 양 극단에 적용한다.
    static func statRange(base: Int, level: Int = 100, isHP: Bool) -> (min: Int, max: Int) {
        let worst = core(base, 0, 0, level: level) + (isHP ? level + 10 : 5)
        let best = core(base, 31, 252, level: level) + (isHP ? level + 10 : 5)
        guard !isHP else { return (worst, best) }
        return (Int(Double(worst) * 0.9), Int((Double(best) * 1.1).rounded(.down)))
    }

    /// 구버전 저장(도입 전에 부화한 개체)용 결정적 대체값의 공통 기반 — 이미 완성된 시드 문자열을
    /// 섞는다(namespace 는 호출부가 붙인다 — legacyIVs 는 원래 입력을 그대로 유지해 이미 화면에
    /// 보이던 대체값이 이 리팩터로 바뀌지 않게 한다). Swift 기본 `Hasher`는 실행마다 시드가 달라
    /// (해시 DoS 방지) 매번 다른 값이 나오므로 못 쓴다 — 여기선 고정 FNV-1a, 같은 입력은 항상 같은
    /// 시드(재실행해도 안 바뀜).
    private static func legacySeed(_ s: String) -> UInt64 {
        var seed: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { seed = (seed ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
        return seed
    }
    /// splitmix64 한 걸음 — seed 를 전진시키고 그 걸음의 값을 낸다(연속 호출하면 서로 다른 값이 나온다).
    private static func legacyDraw(_ seed: inout UInt64) -> UInt64 {
        seed = seed &+ 0x9E37_79B9_7F4A_7C15
        var z = seed
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 구버전 저장(IV 도입 전에 부화한 개체)용 대체 IV — 부화 시 굴리는 진짜 IV 롤
    /// (CompanionStore.hatchCore)과 별개 경로라 rng 시퀀스에 관여하지 않는다 — 기존 개체를 다시
    /// 세이브에 쓰는 마이그레이션이 필요 없다(그때그때 계산).
    static func legacyIVs(monID: String) -> StatSpread {
        var seed = legacySeed(monID)
        func draw() -> Int { Int(legacyDraw(&seed) % 32) }
        return StatSpread(hp: draw(), attack: draw(), defense: draw(), specialAttack: draw(),
                          specialDefense: draw(), speed: draw())
    }

    /// 구버전 저장(특성 도입 전에 부화한 개체)용 대체 특성 — legacyIVs 와 같은 결정적 해시(다른
    /// namespace 라 같은 개체라도 IV 대체값과는 무관한 값이 나온다), 종의 실제 특성 후보
    /// (candidates, 부화 시 실제로 굴리는 것과 같은 목록) 중 하나를 고른다. candidates 가 비면
    /// (baseStats 미로딩/조회 실패) nil — 로딩되면 화면이 다시 그려 채워진다.
    static func legacyAbility(monID: String, candidates: [PokemonAbility]) -> String? {
        guard !candidates.isEmpty else { return nil }
        var seed = legacySeed(monID + "-ability")
        return candidates[Int(legacyDraw(&seed) % UInt64(candidates.count))].name
    }
}

/// 게임 밸런스 — 개체 롤 확률.
enum PokemonOdds {
    /// 색이 다른 포켓몬(shiny) 부화 확률 분모 — 1/64 (본가 1/4096 은 데스크톱 앱 규모에선 평생 못 봄).
    static let shinyDenominator: UInt64 = 64
    /// 메타몽 위장 확률 분모 — common·≥2형태 부화에 한해 1/128 (GO 변장 메타몽 추정 1/50~70보다 귀하게).
    static let dittoDisguiseDenominator: UInt64 = 128
    /// 메타몽 종 id — 위장 리빌 전용(일반 부화 풀에서 제외).
    static let dittoSpeciesID = 132
}

/// 포켓몬 개체가 세이브에 합류한 경로 — 알/거래. 거래는 상대 표시 이름을 함께 담는다(알 수 없으면 nil).
enum AcquisitionSource: Codable, Sendable, Equatable {
    case egg
    case trade(from: String?)
}

/// 현재 키우는 포켓몬. PC(파티) 배열의 원소 — `id` 로 개체를 식별한다(진화해도 고정).
struct MonState: Codable, Sendable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var baseID: Int
    var pathIDs: [Int]      // 실제 진화 경로(분기 선택 반영)
    var plannedPathIDs: [Int] // 사전에 선택한 전체 진화 경로
    var stageIndex: Int     // pathIDs 내 현재 위치
    var usedAtStage: Int    // 현재 형태에서 누적 사용량
    var rarity: Rarity
    var totalForms: Int
    var isShiny = false             // 부화 시 확정, 진화해도 유지
    var nature: PokemonNature?      // 부화 시 확정 (구버전 저장은 nil)
    /// 특성 슬러그(PokéAPI, 예: "static") — 부화 시 그 종의 실제 특성 후보에서 확정 롤, 평생 고정.
    /// nature 와 같은 처리(구버전 저장/도입 전 부화 개체는 nil) — 대체 롤 없이 그냥 "미상"으로 둔다.
    var ability: String?
    /// 개체값(IV, 스탯당 0~31) — 부화 시 확정, 평생 고정. IV 도입 전 부화 개체는 nil — `effectiveIVs`
    /// 가 `StatCalc.legacyIVs(monID:)`로 대체한다(세이브 마이그레이션 없이 그때그때 계산).
    var ivs: StatSpread?
    /// 노력치(EV, 스탯당 0~252) — 아이템(비타민)으로 누적, 부화 시 전부 0.
    var evs = StatSpread()
    // 메타몽 위장 — nil=일반. 값=정체 메타몽, 이 종으로 위장 중(위장 구간엔 baseID 와 동일, 리빌 후에도 원 위장체 보존).
    var dittoDisguise: Int?
    var dittoRevealed = false       // 위장 → 리빌(정체 공개) 전환 여부
    var acquiredAt: Date = Date()   // 파티 합류 시각(구버전 세이브는 마이그레이션 시각으로 근사)
    var acquiredVia: AcquisitionSource = .egg
    /// User-set — while true, applyUsage still accumulates usedAtStage (XP/level keep climbing) but
    /// never acts on crossing a threshold (no evolve, no graduate). Lets someone keep a form they
    /// like without losing progress toward it.
    var evolutionLocked = false
    /// User-set — this individual gets its own floating desktop pet window (PC detail screen).
    /// Multiple party members can be floating at once, independent of who's training.
    var isFloating = false
    // pathIDs 가 비면(손상된 상태 파일) baseID 로 폴백 — 렌더마다 읽히므로 out-of-bounds 크래시 방지.
    var currentID: Int { pathIDs.isEmpty ? baseID : pathIDs[min(stageIndex, pathIDs.count - 1)] }
    /// 표시 전용 레벨(Lv.1~100) — PokemonBalance.level 참고.
    var level: Int { PokemonBalance.level(rarity: rarity, totalForms: totalForms, stageIndex: stageIndex, usedAtStage: usedAtStage) }
    /// 화면/계산에 실제로 쓸 IV — 진짜 부화 롤(ivs)이 있으면 그것, 없으면(구버전 개체) id 로 결정적 대체.
    var effectiveIVs: StatSpread { ivs ?? StatCalc.legacyIVs(monID: id) }
    /// 화면에 실제로 보여줄 특성 — 진짜 부화 롤(ability)이 있으면 그것, 없으면(특성 도입 전 개체)
    /// 종의 실제 특성 후보에서 id 로 결정적 대체. candidates 는 호출부가 이미 들고 있는
    /// baseStats.abilities(그 종의 진짜 후보 목록)를 그대로 넘긴다 — effectiveIVs 와 달리 이건
    /// 종 데이터가 있어야 뽑을 수 있어 MonState 혼자서는 계산 못 한다(파라미터로 받는 이유).
    func effectiveAbility(candidates: [PokemonAbility]) -> String? {
        ability ?? StatCalc.legacyAbility(monID: id, candidates: candidates)
    }

    init(id: String = UUID().uuidString, baseID: Int, pathIDs: [Int], plannedPathIDs: [Int]? = nil,
         stageIndex: Int, usedAtStage: Int, rarity: Rarity, totalForms: Int, isShiny: Bool = false,
         nature: PokemonNature? = nil, ability: String? = nil, ivs: StatSpread? = nil, evs: StatSpread = StatSpread(),
         dittoDisguise: Int? = nil, dittoRevealed: Bool = false,
         acquiredAt: Date = Date(), acquiredVia: AcquisitionSource = .egg, evolutionLocked: Bool = false,
         isFloating: Bool = false) {
        self.id = id
        self.baseID = baseID
        self.pathIDs = pathIDs
        if let plannedPathIDs, !plannedPathIDs.isEmpty {
            self.plannedPathIDs = plannedPathIDs
        } else {
            self.plannedPathIDs = pathIDs
        }
        self.stageIndex = stageIndex
        self.usedAtStage = usedAtStage
        self.rarity = rarity
        self.totalForms = totalForms
        self.isShiny = isShiny
        self.nature = nature
        self.ability = ability
        self.ivs = ivs
        self.evs = evs
        self.dittoDisguise = dittoDisguise
        self.dittoRevealed = dittoRevealed
        self.acquiredAt = acquiredAt
        self.acquiredVia = acquiredVia
        self.evolutionLocked = evolutionLocked
        self.isFloating = isFloating
    }

    // 하위호환 디코딩: shiny/nature/id/acquiredAt/acquiredVia 는 구버전 저장에 없음 → 기본값.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        baseID = try c.decode(Int.self, forKey: .baseID)
        pathIDs = try c.decode([Int].self, forKey: .pathIDs)
        // 빈 pathIDs 는 손상 상태 → 디코드 실패시켜 전체 CompanionState 가 기본(알)로 폴백되게 한다.
        guard !pathIDs.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .pathIDs, in: c, debugDescription: "empty pathIDs")
        }
        if let savedPlan = try c.decodeIfPresent([Int].self, forKey: .plannedPathIDs), !savedPlan.isEmpty {
            plannedPathIDs = savedPlan
        } else {
            plannedPathIDs = pathIDs
        }
        let decodedStageIndex = try c.decode(Int.self, forKey: .stageIndex)
        stageIndex = min(max(0, decodedStageIndex), pathIDs.count - 1)
        usedAtStage = try c.decode(Int.self, forKey: .usedAtStage)
        rarity = try c.decode(Rarity.self, forKey: .rarity)
        totalForms = try c.decode(Int.self, forKey: .totalForms)
        isShiny = try c.decodeIfPresent(Bool.self, forKey: .isShiny) ?? false
        nature = try c.decodeIfPresent(PokemonNature.self, forKey: .nature)
        ability = try c.decodeIfPresent(String.self, forKey: .ability)
        // 구버전(IV/EV 도입 전) 저장은 둘 다 없음 — ivs는 nil 유지(effectiveIVs가 대체), evs는 0이 정답.
        ivs = try c.decodeIfPresent(StatSpread.self, forKey: .ivs)
        evs = try c.decodeIfPresent(StatSpread.self, forKey: .evs) ?? StatSpread()
        dittoDisguise = try c.decodeIfPresent(Int.self, forKey: .dittoDisguise)
        dittoRevealed = try c.decodeIfPresent(Bool.self, forKey: .dittoRevealed) ?? false
        acquiredAt = (try? c.decodeIfPresent(Date.self, forKey: .acquiredAt)) ?? Date()
        acquiredVia = (try? c.decodeIfPresent(AcquisitionSource.self, forKey: .acquiredVia)) ?? .egg
        evolutionLocked = (try? c.decodeIfPresent(Bool.self, forKey: .evolutionLocked)) ?? false
        isFloating = (try? c.decodeIfPresent(Bool.self, forKey: .isFloating)) ?? false
    }
}

/// 도감 항목 — 라인 전체(초기→최종) 순서 보존.
struct DexEntry: Codable, Sendable, Identifiable {
    var id = UUID().uuidString
    var baseID: Int
    var finalID: Int
    var chainOrder: [Int]   // 초기→최종 종 id
    var rarity: Rarity
    var caughtAt: Date?
    var isShiny = false
    var nature: PokemonNature?
    /// 진화 체인 각 종의 다국어 이름(speciesID → langCode → name). 졸업 시 로드된 라인에서 저장 →
    /// 도감의 단계별 스프라이트 밑 이름 표시가 네트워크 없이 즉시 + 언어 전환 대응. 구버전 저장분엔
    /// 없어(nil) 뷰가 line fetch 로 조회 후 백필한다.
    var names: [Int: [String: String]]?
    /// 이 로그 행이 가리키는 살아있는 파티 개체 — nil 이면 그 개체가 더는 없거나(구버전 졸업 기록) 마이그레이션
    /// 이전 데이터. `CompanionStore.isTrainingLogEntry` 가 "지금 훈련 중인 개체"를 판별하는 데 쓴다.
    var monID: String?
    /// 이 개체가 세이브에 합류한 경로(알/거래) — 포획 로그 행에 "알로/거래로" 표시용.
    var source: AcquisitionSource = .egg

    init(id: String = UUID().uuidString,
         baseID: Int, finalID: Int, chainOrder: [Int], rarity: Rarity,
         caughtAt: Date?, isShiny: Bool = false, nature: PokemonNature? = nil,
         names: [Int: [String: String]]? = nil, monID: String? = nil, source: AcquisitionSource = .egg) {
        self.id = id
        self.baseID = baseID
        self.finalID = finalID
        self.chainOrder = chainOrder
        self.rarity = rarity
        self.caughtAt = caughtAt
        self.isShiny = isShiny
        self.nature = nature
        self.names = names
        self.monID = monID
        self.source = source
    }

    // 하위호환 디코딩 (MonState 와 동일 이유).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        baseID = try c.decode(Int.self, forKey: .baseID)
        finalID = try c.decode(Int.self, forKey: .finalID)
        chainOrder = try c.decode([Int].self, forKey: .chainOrder)
        rarity = try c.decode(Rarity.self, forKey: .rarity)
        caughtAt = try c.decodeIfPresent(Date.self, forKey: .caughtAt)
        isShiny = try c.decodeIfPresent(Bool.self, forKey: .isShiny) ?? false
        nature = try c.decodeIfPresent(PokemonNature.self, forKey: .nature)
        // try? — 구버전(최종체 단일 [String:String]) 형식이 남아 있어도 종별 맵 디코딩 실패 시 nil 로
        // 강등(항목 전체 로드는 유지). 뷰가 line 조회로 백필한다.
        names = (try? c.decodeIfPresent([Int: [String: String]].self, forKey: .names)) ?? nil
        monID = (try? c.decodeIfPresent(String.self, forKey: .monID)) ?? nil
        source = (try? c.decodeIfPresent(AcquisitionSource.self, forKey: .source)) ?? .egg
    }
}

/// 도감(종 단위) 영구 언락 기록 — 한 번 도달하면 그 개체를 나중에 잃어도(거래 등) 지워지지 않는다.
/// `baseID` 는 이름 백필(`provider.line(baseSpeciesID:)`) 조회에 필요해 별도 보관한다.
struct DexUnlock: Codable, Sendable {
    let baseID: Int
    let rarity: Rarity
    var names: [String: String]?
    var isShiny: Bool
}

/// 배열 항목별 격리 디코딩 래퍼 — 손상된 한 항목이 배열 전체(및 상위 상태) 디코드를 실패시키지 않게.
/// 각 항목을 `try?` 로 감싸므로 실패 항목은 `value == nil` 이 되고 배열 디코드 자체는 성공한다.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? decoder.singleValueContainer().decode(T.self) }
}

private extension KeyedDecodingContainer {
    /// 관대 디코드 — 키 없음/null/타입 불일치를 모두 기본값으로 흡수한다. 한 필드 손상이 상태 전체
    /// (도감·인벤토리)를 날리지 않게(부분 복원 > 전면 리셋). 최상위가 JSON 객체가 아닌 전면 손상은 여전히 throw.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key, default def: T) -> T {
        (try? decode(type, forKey: key)) ?? def
    }
    func lenientOptional<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decode(type, forKey: key)
    }
}

/// 구버전 세이브의 `active` 키만 읽기 위한 별도 CodingKey — `CompanionState` 에서 `active` 는 더 이상
/// 저장 프로퍼티가 아니라 합성 CodingKeys 에 없다. 같은 디코더에서 별도 keyed container 를 여는 것은
/// 표준 Codable 패턴(같은 JSON 객체를 두 키 집합으로 각각 읽음)이라 안전하다.
private enum LegacyCompanionKeys: String, CodingKey { case active }

/// 영속 상태(Application Support JSON). 포켓몬 전환 — 이전 커스텀 캐릭터 상태는 폐기(새로 시작).
struct CompanionState: Codable, Sendable {
    // 토큰: 설치 이후만 측정
    var installBaselineSet = false
    var usedSinceInstall = 0
    // 상점에서 쓴 토큰 누적(재화 지출 원장). 쓸 수 있는 재화 = usedSinceInstall − spentTokens.
    // 성장 미터(usedSinceInstall)는 불변 — 구매는 이 값만 올려 잔액을 깎는다(성장 되감김 없음).
    var spentTokens = 0
    // 현재 알이 생긴 뒤 쓴 토큰(부화 인큐베이션). 누적(usedSinceInstall)과 별개 — 졸업 후 새 알마다 0.
    var eggUsage = 0
    // 현재 알이 보증하는 등급 하한(프리미엄 알). nil = 보증 없음(무료 알·기본 알).
    // ★영속이어야 한다 — 구매 시점엔 종을 못 정한다(롤에 네트워크가 필요). 보증을 상태에 적어 두고
    // 롤이 그것을 읽어야 오프라인·재시작을 건너서도 산 것을 받는다. 부화·졸업 때 nil 로 소비된다.
    var eggTier: Rarity?
    // 알 후보 풀을 한 지역(세대)으로 제한하는 필터. nil = 제한 없음(기본, 기존 동작 그대로).
    // eggTier 와 달리 구매로 소비되지 않는 상시 선호도 — 상점에서 바꾸기 전까지 이후 모든 롤(현재
    // 품고 있는 알 포함)에 계속 적용된다.
    var eggRegion: Region?
    // 알 상태에서 미리 롤해둔 부화 종(프리패칭) — 부화 순간 네트워크 딜레이 제거. 재시작에도 유지.
    var pendingHatchID: Int?
    /// 오늘 사용량 적립 기준값 — 프로바이더별로 독립 관리한다.
    ///
    /// `nil`은 aggregate `claimedTodayTokens`만 가지고 있던 구버전 세이브가 아직 첫 유효
    /// snapshot을 기준으로 seed되지 않았다는 뜻이다. 첫 update에서 현재 프로바이더 값을
    /// 기준값으로만 저장하고, 과거 사용량은 소급 지급하지 않는다. 빈 map은 이미 seed된 뒤
    /// 오늘 보고한 프로바이더가 없는 정상 상태와 구분되어야 하므로 `nil`과 별도로 유지한다.
    /// 키는 `UsageProvider.id`를 그대로 사용한다.
    var claimedTodayTokensByProvider: [String: Int]? = nil
    var lastDate = ""
    // PC — 소유한 모든 포켓몬. 훈련 중(토큰 사용량을 받는) 개체는 trainingSlotID 로 가리킨다.
    var party: [MonState] = []
    var trainingSlotID: String?
    // 포획 로그 — 개체가 파티에 합류한 시점(알/거래) 1행. dexEntriesSorted 가 시각순으로 보여준다.
    var dex: [DexEntry] = []
    // 도감(종 단위) 영구 언락 — 한 번 도달한 종은 그 개체를 나중에 잃어도(거래) 지워지지 않는다.
    var dexUnlocked: [Int: DexUnlock] = [:]
    // 소유한 (base,final) 쌍 — 분기 다양성용
    var collectedFinals: Set<String> = []
    var language: AppLanguage = .systemDefault   // 신규 설치 = 시스템 로케일
    // 인벤토리 (ItemKind.rawValue → 개수)
    var inventory: [String: Int] = [:]
    // 사탕 지급 엣지 상태(창 key → 지급한 tier). ★영속 — notifiedTier(인메모리)와 달리 재시작 무한지급 방지.
    var candyGrantTier: [String: Int] = [:]
    // 사탕 지급 첫 실행 시드 완료 — 업데이트 직후 이미 100%였던 창의 소급 지급 차단.
    var candyFeatureSeeded = false

    init() {}

    // 하위호환 + 손상 복원 디코딩: 누락 키·타입 불일치·일부 손상 필드를 모두 기본값으로 흡수한다 —
    // 한 필드가 깨져도 상태 전체(도감·인벤토리)를 날리지 않는다(부분 복원). 최상위가 JSON 객체가 아닌
    // 전면 손상만 throw → load() 가 원본을 .corrupt 로 백업하고 fresh 로 시작.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        installBaselineSet = c.lenient(Bool.self, forKey: .installBaselineSet, default: false)
        usedSinceInstall   = c.lenient(Int.self, forKey: .usedSinceInstall, default: 0)
        spentTokens        = c.lenient(Int.self, forKey: .spentTokens, default: 0)
        eggUsage           = c.lenient(Int.self, forKey: .eggUsage, default: 0)
        // 모르는 rawValue 는 nil(보증 없음)로 강등 — 관대 디코딩의 안전한 방향(있지도 않은 보증을 만들지 않는다).
        eggTier            = c.lenientOptional(Rarity.self, forKey: .eggTier)
        // 모르는 rawValue 는 nil(제한 없음)로 강등 — eggTier 와 같은 안전한 방향.
        eggRegion          = c.lenientOptional(Region.self, forKey: .eggRegion)
        pendingHatchID     = c.lenientOptional(Int.self, forKey: .pendingHatchID)
        if c.contains(.claimedTodayTokensByProvider) {
            claimedTodayTokensByProvider = c.lenient([String: Int].self,
                                                      forKey: .claimedTodayTokensByProvider,
                                                      default: [:])
        } else {
            // 구버전의 aggregate claimedTodayTokens 키는 의도적으로 읽지 않는다. 프로바이더별
            // 분해가 불가능하므로 다음 CompanionStore.update에서 현재 snapshot을 기준점으로 seed한다.
            claimedTodayTokensByProvider = nil
        }
        lastDate           = c.lenient(String.self, forKey: .lastDate, default: "")
        // 도감(포획 로그)은 항목별 격리 — 손상 항목 하나가 로그 전체를 날리지 않게. party/dexUnlocked
        // 마이그레이션이 이 값을 참조하므로 그보다 먼저 디코딩한다.
        dex                = c.lenient([Lossy<DexEntry>].self, forKey: .dex, default: []).compactMap(\.value)
        if c.contains(.party) {
            // 신규 포맷 — party/trainingSlotID/dexUnlocked 를 그대로 읽는다.
            party          = c.lenient([Lossy<MonState>].self, forKey: .party, default: []).compactMap(\.value)
            trainingSlotID = c.lenientOptional(String.self, forKey: .trainingSlotID)
            dexUnlocked    = c.lenient([Int: DexUnlock].self, forKey: .dexUnlocked, default: [:])
        } else {
            // 구버전 세이브 — 단일 active 를 party 의 첫 원소로 승격하고, 기존 dex(졸업 기록) +
            // active 의 도달분을 접어 dexUnlocked 를 1회성으로 재구성한다(최선 근사 — 실제 합류
            // 시각은 없어 마이그레이션 시각/nil 로 대체).
            let legacy = try decoder.container(keyedBy: LegacyCompanionKeys.self)
            let legacyActive = legacy.lenientOptional(MonState.self, forKey: .active)
            party = legacyActive.map { [$0] } ?? []
            trainingSlotID = legacyActive?.id
            dexUnlocked = CompanionState.migratedDexUnlocked(fromLegacyDex: dex, legacyActive: legacyActive)
            if let a = legacyActive {
                // 위장 중인 메타몽은 리빌 전까지 이로치를 숨긴다(판정 단일 소스, graduate()/activeDexEntry 와 동일 규칙).
                let effectiveShiny = a.isShiny && !(a.dittoDisguise != nil && !a.dittoRevealed)
                // pathIDs 전체가 아니라 실제 도달분만 — migratedDexUnlocked(바로 위)가 이 mon 에 쓰는 것과
                // 같은 슬라이스. 안 그러면 이 로그 행의 chainOrder 가 미도달 단계까지 "도달"로 주장하게 되고,
                // (backfilledDexUnlocked 처럼) 이후 그 chainOrder 를 신뢰하는 소비자가 그걸 그대로 새게 된다.
                let reachedPath = Array(a.pathIDs.prefix(a.stageIndex + 1))
                dex.append(DexEntry(baseID: a.baseID, finalID: a.currentID, chainOrder: reachedPath,
                                     rarity: a.rarity, caughtAt: nil, isShiny: effectiveShiny,
                                     nature: a.nature, names: nil, monID: a.id, source: .egg))
            }
        }
        collectedFinals    = c.lenient(Set<String>.self, forKey: .collectedFinals, default: [])
        language           = c.lenient(AppLanguage.self, forKey: .language, default: .systemDefault)
        inventory          = c.lenient([String: Int].self, forKey: .inventory, default: [:])
        candyGrantTier     = c.lenient([String: Int].self, forKey: .candyGrantTier, default: [:])
        candyFeatureSeeded = c.lenient(Bool.self, forKey: .candyFeatureSeeded, default: false)
    }

    /// 구버전 세이브 1회 마이그레이션 — 졸업 기록(dex) 각 항목의 chainOrder 전 종 + 구버전 active 의
    /// 도달분(pathIDs[0...stageIndex])을 접어 종 단위 영구 언락 맵을 재구성한다. dexSpecies 가 기존에
    /// 라이브로 하던 접기와 동일한 로직 — 마이그레이션 시점에 한 번 영속화한다는 점만 다르다.
    static func migratedDexUnlocked(fromLegacyDex dex: [DexEntry], legacyActive: MonState?) -> [Int: DexUnlock] {
        var out: [Int: DexUnlock] = [:]
        for entry in dex {
            for id in entry.chainOrder {
                var u = out[id] ?? DexUnlock(baseID: entry.baseID, rarity: entry.rarity, names: nil, isShiny: false)
                if let n = entry.names?[id] { u.names = n }
                if entry.isShiny { u.isShiny = true }
                out[id] = u
            }
        }
        if let a = legacyActive {
            let effectiveShiny = a.isShiny && !(a.dittoDisguise != nil && !a.dittoRevealed)
            for id in a.pathIDs.prefix(a.stageIndex + 1) {
                var u = out[id] ?? DexUnlock(baseID: a.baseID, rarity: a.rarity, names: nil, isShiny: false)
                if effectiveShiny { u.isShiny = true }
                out[id] = u
            }
        }
        return out
    }

    /// `dexUnlocked` 를 `dex`(포획 로그)·`party` 에서 다시 접어 **빠진 항목만** 채운다(있는 항목은
    /// 안 건드림 — union, never downgrade). 정상 흐름(hatch/evolve/graduate)에서는 매번
    /// `unlockSpecies` 가 그때그때 갱신하므로 이 함수가 할 일이 없지만, 손편집·외부 시드 스크립트·
    /// 과거 마이그레이션 공백처럼 `dexUnlocked` 가 `dex`/`party` 보다 뒤처진 세이브를 만나면 그 자리에서
    /// 따라잡는다. `migratedDexUnlocked` 와 같은 접기 로직 — 그건 구버전 1회 마이그레이션 전용, 이건
    /// `SaveTransfer.sanitized` 에서 **매 로드마다** 돌려 소스가 무엇이었든 자가 치유되게 한다.
    static func backfilledDexUnlocked(existing: [Int: DexUnlock], dex: [DexEntry],
                                      party: [MonState]) -> [Int: DexUnlock] {
        var out = existing
        func fold(_ id: Int, baseID: Int, rarity: Rarity, names: [String: String]?, isShiny: Bool) {
            var u = out[id] ?? DexUnlock(baseID: baseID, rarity: rarity, names: nil, isShiny: false)
            if let names { u.names = names }
            if isShiny { u.isShiny = true }
            out[id] = u
        }
        for entry in dex {
            // 거래로 받은 로그는 받은 형태(finalID)만 실제로 "본" 것이다 — 이전 진화 단계는 보낸 쪽이
            // 겪은 역사지 받는 쪽이 목격한 게 아니다(addTradedMon 과 같은 규칙). chainOrder 전체를
            // 신뢰할 수 있는 건 egg 로그뿐 — 그 개체가 진화하는 걸 이 세이브의 주인이 직접 지켜봤다.
            let witnessed: [Int]
            if case .trade = entry.source { witnessed = [entry.finalID] } else { witnessed = entry.chainOrder }
            for id in witnessed {
                fold(id, baseID: entry.baseID, rarity: entry.rarity, names: entry.names?[id], isShiny: entry.isShiny)
            }
        }
        for mon in party {
            let effectiveShiny = mon.isShiny && !(mon.dittoDisguise != nil && !mon.dittoRevealed)
            let witnessed: [Int]
            if case .trade = mon.acquiredVia { witnessed = [mon.currentID] } else { witnessed = Array(mon.pathIDs.prefix(mon.stageIndex + 1)) }
            for id in witnessed {
                fold(id, baseID: mon.baseID, rarity: mon.rarity, names: nil, isShiny: effectiveShiny)
            }
        }
        return out
    }
}

// NOTE: 부화 후보는 더 이상 하드코딩하지 않는다 — CompanionStore.chooseBase() 가
// PokéAPI 전수(1~5세대)를 capture_rate 가중 rejection sampling 으로 선정한다.
