import Foundation

/// 부화 후보 — 진화라인 시작점(base) 종과 공식 희귀도.
struct BaseSpecies: Sendable, Codable {
    let id: Int
    let captureRate: Int    // 3(뮤츠급)~255(캐터피급), 공식 희귀도 신호
}

/// 포켓몬 타입 18종 — rawValue 는 PokéAPI `type.name` 그대로(예: "fire"), 디코드에 그대로 재사용.
enum PokemonType: String, Sendable, Codable, CaseIterable, Equatable {
    case normal, fire, water, electric, grass, ice, fighting, poison, ground
    case flying, psychic, bug, rock, ghost, dragon, dark, steel, fairy
}

/// 특성 후보 하나 — name 은 PokéAPI 슬러그(예: "static"), 표시명은 별도(`abilityNames`)로 조회한다.
/// 특성은 300종이 넘어 타입처럼 닫힌 enum 으로 못 두고, rawValue 도 다국어 이름이 아니라 슬러그다.
struct PokemonAbility: Sendable, Codable, Equatable {
    let name: String
    let isHidden: Bool
}

/// 기준 능력치 + 타입 + 특성 후보 + 신체 치수 — 전부 `/pokemon/{id}` 응답 1건에서 온다
/// (`pokemon-species` 에는 없음).
struct BaseStats: Sendable, Codable, Equatable {
    let hp, attack, defense, specialAttack, specialDefense, speed: Int
    /// 1~2개, 주 타입이 먼저(PokéAPI slot 오름차순).
    var types: [PokemonType] = []
    /// 이 종이 가질 수 있는 특성 후보(일반 + 히든), slot 오름차순. 부화 시 이 중 하나를 확정 롤한다.
    var abilities: [PokemonAbility] = []
    /// 미터 — PokéAPI 는 decimeter(예: 4 → 0.4m) 로 주므로 actor 에서 미리 환산해둔다.
    var heightM: Double = 0
    /// 킬로그램 — PokéAPI 는 hectogram(예: 60 → 6.0kg) 으로 주므로 actor 에서 미리 환산해둔다.
    var weightKg: Double = 0
}

/// 포켓몬 라인 데이터 제공(주입 가능 — 테스트는 스텁 사용).
protocol PokeProviding: Sendable {
    func line(baseSpeciesID: Int) async throws -> EvoLine
    /// 1~5세대 base 전체 인덱스 (GraphQL 1쿼리, 디스크 캐시).
    func baseSpeciesIndex() async throws -> [BaseSpecies]
    /// 단일 종이 base(진화 시작점)면 BaseSpecies, 아니면 nil.
    /// GraphQL 인덱스 엔드포인트 장애 시 REST(pokemon-species)로 부화 후보를 뽑는 폴백용.
    func baseSpecies(id: Int) async throws -> BaseSpecies?
    /// 종/폼의 기준 능력치 — PC 상세 화면 스탯 표시 전용, 부화·진화 로직과 무관.
    func baseStats(speciesID: Int) async throws -> BaseStats
    /// 특성 슬러그(예: "static")의 다국어 표시명(langCode → name). PC 상세 화면·부화 결과 표시 전용.
    func abilityNames(slug: String) async throws -> [String: String]
    /// 도감 설명(langCode → text) — `pokemon-species` 의 flavor_text_entries, 게임판마다 여러 개라
    /// 언어당 하나만(가장 최근 판) 골라 반환한다. 도감 종 개요 화면 전용.
    func flavorText(speciesID: Int) async throws -> [String: String]
    /// 분류(langCode → text, 예: "Mouse Pokémon") — `pokemon-species` 의 genera. 도감 종 개요 화면 전용.
    func genus(speciesID: Int) async throws -> [String: String]
    /// This species' learnset (level-up/TM, per `MoveDataVersion.versionGroup`) — for the PC detail
    /// screen's learn-a-move flow only.
    func learnableMoves(speciesID: Int) async throws -> [LearnableMove]
    /// Detail for a single move (`/move/{id}`) — for displaying known moves/learnset only.
    func moveDetail(id: Int) async throws -> Move
    /// Same, but by PokéAPI slug/display name (`/move/{name}` accepts either) — for resolving a
    /// move an opponent used from the battle log, where only the name is known, never an id.
    func moveDetail(name: String) async throws -> Move
    /// The full TM list for `MoveDataVersion.versionGroup` — for the shop's TM catalog only.
    func tmCatalog() async throws -> [Move]
    /// A species' numeric id from its plain-English display name ("Venusaur") — for resolving an
    /// opponent battle-log mon (team preview only ever reveals a species name, never an id) to a
    /// real sprite, the same "only ever learn it by name" situation `moveDetail(name:)` solves for
    /// moves.
    func speciesID(name: String) async throws -> Int
}

/// 스탯/특성/설명/분류 표시를 지원하지 않는 provider(대부분의 기존 테스트 스텁)의 기본값 — 호출부는
/// 옵셔널로 받아 실패를 조용히 흡수한다(CompanionStore.baseStats/abilityName/flavorText/genus). 실
/// 클라이언트는 아래에서 override.
extension PokeProviding {
    func baseStats(speciesID: Int) async throws -> BaseStats { throw URLError(.unsupportedURL) }
    func abilityNames(slug: String) async throws -> [String: String] { throw URLError(.unsupportedURL) }
    func flavorText(speciesID: Int) async throws -> [String: String] { throw URLError(.unsupportedURL) }
    func genus(speciesID: Int) async throws -> [String: String] { throw URLError(.unsupportedURL) }
    func learnableMoves(speciesID: Int) async throws -> [LearnableMove] { throw URLError(.unsupportedURL) }
    func moveDetail(id: Int) async throws -> Move { throw URLError(.unsupportedURL) }
    func moveDetail(name: String) async throws -> Move { throw URLError(.unsupportedURL) }
    func tmCatalog() async throws -> [Move] { throw URLError(.unsupportedURL) }
    func speciesID(name: String) async throws -> Int { throw URLError(.unsupportedURL) }
}

/// PokéAPI 클라이언트 — 종/진화체인을 런타임 fetch + 파싱. 포켓몬 데이터는 레포에 번들하지 않는다.
/// species 응답은 actor 캐시(다국어 이름 재사용).
actor PokeAPIClient: PokeProviding {
    static let shared = PokeAPIClient()
    private let base = URL(string: "https://pokeapi.co/api/v2")!
    // Lockstep with the union of AppLanguage.apiCodes. "pt" collects nothing today
    // (PokéAPI has no such language) but is listed so it is picked up the moment
    // one appears — omit it and EvoLine.names never carries it, pinning English.
    // AppLanguage.apiCodes 의 합집합과 lockstep. "pt" 는 아직 PokéAPI 에 없어 수집되지 않지만,
    // 추가되는 즉시 잡히도록 함께 둔다(없으면 EvoLine.names 에 안 담겨 영어 폴백이 고정된다).
    private let langCodes = ["ko", "en", "ja-Hrkt", "ja", "es", "fr", "pt"]
    private var speciesCache: [Int: SpeciesDTO] = [:]
    private var lineCache: [Int: EvoLine] = [:]   // 프리패칭 → 부화 순간 네트워크 0
    private var statsCache: [Int: BaseStats] = [:]
    private var abilityNamesCache: [String: [String: String]] = [:]
    private var pokemonDTOCache: [Int: PokemonDTO] = [:]     // shared by baseStats/learnableMoves (same `/pokemon/{id}`)
    private var learnableMovesCache: [Int: [LearnableMove]] = [:]
    private var moveCache: [Int: Move] = [:]
    private var speciesIDByNameCache: [String: Int] = [:]

    /// `/pokemon/{id}` — baseStats (base stats) and learnableMoves (learnset) both split the same
    /// response, so the cache is pooled here (same pattern as species(_:) being split by flavorText/genus).
    private func pokemon(_ id: Int) async throws -> PokemonDTO {
        if let c = pokemonDTOCache[id] { return c }
        let dto: PokemonDTO = try await get(base.appendingPathComponent("pokemon/\(id)"))
        pokemonDTOCache[id] = dto
        return dto
    }

    /// 종/폼의 기준 능력치 + 타입 + 특성 후보(`/pokemon/{id}`) — `pokemon-species`와 별개 엔드포인트라 자체 캐시.
    func baseStats(speciesID id: Int) async throws -> BaseStats {
        if let cached = statsCache[id] { return cached }
        let dto = try await pokemon(id)
        var byName: [String: Int] = [:]
        for entry in dto.stats { byName[entry.stat.name] = entry.base_stat }
        let types = dto.types.sorted { $0.slot < $1.slot }.compactMap { PokemonType(rawValue: $0.type.name) }
        let abilities = dto.abilities.sorted { $0.slot < $1.slot }
            .map { PokemonAbility(name: $0.ability.name, isHidden: $0.is_hidden) }
        let stats = BaseStats(hp: byName["hp"] ?? 0, attack: byName["attack"] ?? 0,
                              defense: byName["defense"] ?? 0, specialAttack: byName["special-attack"] ?? 0,
                              specialDefense: byName["special-defense"] ?? 0, speed: byName["speed"] ?? 0,
                              types: types, abilities: abilities,
                              heightM: Double(dto.height) / 10, weightKg: Double(dto.weight) / 10)
        statsCache[id] = stats
        return stats
    }

    /// 분류(`/pokemon-species/{id}` 의 genera) — flavorText 와 같은 응답이라 캐시 히트면 네트워크 0.
    func genus(speciesID id: Int) async throws -> [String: String] {
        let sp = try await species(id)
        var byLang: [String: String] = [:]
        for g in sp.genera where langCodes.contains(g.language.name) { byLang[g.language.name] = g.genus }
        return byLang
    }

    /// 특성 슬러그의 다국어 표시명(`/ability/{slug}`) — species 이름과 같은 패턴(런타임 조회 + 캐시).
    func abilityNames(slug: String) async throws -> [String: String] {
        if let cached = abilityNamesCache[slug] { return cached }
        let dto: AbilityDTO = try await get(base.appendingPathComponent("ability/\(slug)"))
        var byLang: [String: String] = [:]
        for n in dto.names where langCodes.contains(n.language.name) { byLang[n.language.name] = n.name }
        abilityNamesCache[slug] = byLang
        return byLang
    }

    /// This species' learnset — filters `/pokemon/{id}`'s moves (per version group) down to
    /// `MoveDataVersion.versionGroup` alone, keeping only level-up/TM (egg/tutor are out of scope).
    /// Keyed by "moveID-method" — PokéAPI genuinely lists some moves twice within the same version
    /// group for evolved species (e.g. Charizard's Ember shows up at both level 1 and level 7 in
    /// black-white). The level-1 entry is an evolution-inheritance artifact — it shows up in every
    /// generation's data, always alongside an explicit `order` field, whereas the real/canonical
    /// level (7 here — what every in-game and community reference actually lists) carries no
    /// `order`. We don't parse `order`, so the higher level is kept as a proxy: the artifact entries
    /// are consistently *lower* than the canonical one. Keeping duplicates would double-render the
    /// row (ForEach id collision), let auto-learn append the same move twice, and — worse — make the
    /// whole learnset look unlocked from level 1, defeating the level gate entirely. Pure/static so
    /// it's testable without a network call.
    static func parseLearnableMoves(from moves: [MoveEntryDTO]) -> [LearnableMove] {
        var byKey: [String: LearnableMove] = [:]
        for entry in moves {
            let moveID = Self.id(from: entry.move.url ?? "")
            guard moveID > 0 else { continue }
            for vgd in entry.version_group_details where vgd.version_group.name == MoveDataVersion.versionGroup {
                let method: LearnMethod
                switch vgd.move_learn_method.name {
                case "level-up": method = .levelUp
                case "machine":  method = .machine
                default: continue
                }
                let level = method == .levelUp ? vgd.level_learned_at : 0
                let key = "\(moveID)-\(method.rawValue)"
                if let existing = byKey[key] {
                    if level > existing.level { byKey[key] = LearnableMove(moveID: moveID, method: method, level: level) }
                } else {
                    byKey[key] = LearnableMove(moveID: moveID, method: method, level: level)
                }
            }
        }
        return Array(byKey.values)
    }

    func learnableMoves(speciesID id: Int) async throws -> [LearnableMove] {
        if let cached = learnableMovesCache[id] { return cached }
        let dto = try await pokemon(id)
        let out = Self.parseLearnableMoves(from: dto.moves)
        learnableMovesCache[id] = out
        return out
    }

    /// Detail for a single move (`/move/{id}`) — same pattern as species/ability names (runtime lookup + cache).
    func moveDetail(id: Int) async throws -> Move {
        if let cached = moveCache[id] { return cached }
        let dto: MoveDTO = try await get(base.appendingPathComponent("move/\(id)"))
        let move = Self.move(from: dto, id: id, langCodes: langCodes)
        moveCache[id] = move
        return move
    }

    /// By PokéAPI slug/display name — `/move/{name}` accepts either, same as `/move/{id}`. Only
    /// caller that doesn't already have the id (a battle log line names the move, never its id).
    /// Checks the existing id-keyed cache for a name match first (free if this move was already
    /// fetched some other way this session, e.g. it's one of this side's own known moves) before
    /// hitting the network.
    func moveDetail(name: String) async throws -> Move {
        let slug = Self.slug(fromDisplayName: name)
        if let cached = moveCache.values.first(where: { $0.name == slug }) { return cached }
        let dto: MoveDTO = try await get(base.appendingPathComponent("move/\(slug)"))
        let move = Self.move(from: dto, id: dto.id, langCodes: langCodes)
        moveCache[dto.id] = move
        return move
    }

    /// PokéAPI's move name field is already its slug ("thunder-shock") — but the battle log only
    /// ever gives the human display name ("Thunder Shock"), so this reverses the same lowercase-and-
    /// hyphenate convention PokéAPI itself uses. Not airtight for every punctuation edge case
    /// (apostrophes are dropped outright, e.g. "King's Shield" -> "kings-shield") — for a purely
    /// cosmetic type-color lookup, a failed fetch just means the default neutral effect plays
    /// instead, not a functional break.
    /// 표시명 → PokéAPI 슬러그.
    ///
    /// 마지막 필터가 신뢰경계다. 이 함수의 입력은 **배틀 로그 줄에서 온 종명**이고, 그 로그는 서버가
    /// 준다(초대 링크가 서버를 지정할 수 있으므로 서버 자체가 신뢰 대상이 아니다). 결과는
    /// `appendingPathComponent` 로 URL 경로에 들어가므로, `/` 나 `..` 가 남아 있으면 의도하지 않은
    /// 경로 세그먼트가 만들어진다. 호스트는 고정이라 피해는 PokéAPI 안에서 끝나지만, 경계에서 문자
    /// 집합을 좁히는 편이 호출부마다 따지는 것보다 싸다.
    ///
    /// 부수 효과로 **정확도도 올라간다** — 실제 종명에 섞인 구두점이 여기서 떨어지면서 PokéAPI 의
    /// 슬러그와 일치하게 된다: "Mr. Mime" → `mr-mime`, "Type: Null" → `type-null`.
    /// (`Nidoran♀` 처럼 슬러그가 아예 다른 규칙인 경우는 여전히 못 맞춘다 — 조회가 실패해 그 호출부만
    /// 스프라이트 없이 지나간다.)
    static func slug(fromDisplayName name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        return name.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: " ", with: "-")
            .filter { allowed.contains($0) }
    }

    private static func move(from dto: MoveDTO, id: Int, langCodes: [String]) -> Move {
        var byLang: [String: String] = [:]
        for n in dto.names where langCodes.contains(n.language.name) { byLang[n.language.name] = n.name }
        return Move(id: id, name: dto.name, type: PokemonType(rawValue: dto.type.name) ?? .normal,
                   power: dto.power, accuracy: dto.accuracy, pp: dto.pp,
                   damageClass: MoveDamageClass(rawValue: dto.damage_class.name) ?? .status,
                   names: byLang)
    }

    // MARK: TM catalog (the full TM list for the version group)

    private var tmCatalogCache: [Move]?
    private static let tmCatalogFile: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tm-catalog.json")
    }()
    private struct TMCatalogSnapshot: Codable { let fetchedAt: Date; let entries: [Move] }

    /// The full TM list (~100) for `MoveDataVersion.versionGroup` — one GraphQL query (same pattern as baseSpeciesIndex).
    /// Priority: memory → disk (30-day TTL) → fetch (refreshes disk on success) → stale disk (offline fallback).
    func tmCatalog() async throws -> [Move] {
        if let c = tmCatalogCache { return c }
        let disk = (try? Data(contentsOf: Self.tmCatalogFile))
            .flatMap { try? JSONDecoder().decode(TMCatalogSnapshot.self, from: $0) }
        if let disk, Date().timeIntervalSince(disk.fetchedAt) < 30 * 86400, !disk.entries.isEmpty {
            tmCatalogCache = disk.entries
            for m in disk.entries { moveCache[m.id] = m }
            return disk.entries
        }
        do {
            let entries = try await fetchTMCatalog()
            tmCatalogCache = entries
            for m in entries { moveCache[m.id] = m }   // instant hit on moveDetail(id:) without refetching
            if let data = try? JSONEncoder().encode(TMCatalogSnapshot(fetchedAt: Date(), entries: entries)) {
                try? data.write(to: Self.tmCatalogFile, options: .atomic)
            }
            return entries
        } catch {
            if let disk, !disk.entries.isEmpty {
                tmCatalogCache = disk.entries
                for m in disk.entries { moveCache[m.id] = m }
                return disk.entries
            }
            throw error
        }
    }

    private struct GraphQLTMResponse: Decodable {
        struct DataBox: Decodable { let machine: [Row] }
        struct Row: Decodable { let move: MoveRow }
        struct MoveRow: Decodable {
            let id: Int
            let name: String
            let power: Int?
            let accuracy: Int?
            let pp: Int
            let type: NamedGQL
            let movedamageclass: NamedGQL
            let movenames: [MoveNameGQL]
        }
        struct NamedGQL: Decodable { let name: String }
        struct MoveNameGQL: Decodable { let name: String; let language: NamedGQL }
        let data: DataBox
    }

    private func fetchTMCatalog() async throws -> [Move] {
        guard let url = URL(string: "https://graphql.pokeapi.co/v1beta2") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let langList = langCodes.map { "\"\($0)\"" }.joined(separator: ", ")
        let query = """
        { machine(where: {versiongroup: {name: {_eq: "\(MoveDataVersion.versionGroup)"}}}, order_by: {machine_number: asc}) \
        { move { id name power accuracy pp type { name } movedamageclass { name } \
        movenames(where: {language: {name: {_in: [\(langList)]}}}) { name language { name } } } } }
        """
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(GraphQLTMResponse.self, from: data)
        guard !decoded.data.machine.isEmpty else { throw URLError(.cannotParseResponse) }
        return decoded.data.machine.map { row in
            var byLang: [String: String] = [:]
            for n in row.move.movenames { byLang[n.language.name] = n.name }
            return Move(id: row.move.id, name: row.move.name, type: PokemonType(rawValue: row.move.type.name) ?? .normal,
                       power: row.move.power, accuracy: row.move.accuracy, pp: row.move.pp,
                       damageClass: MoveDamageClass(rawValue: row.move.movedamageclass.name) ?? .status,
                       names: byLang)
        }
    }

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        if let cached = lineCache[baseSpeciesID] { return cached }
        let baseSpecies = try await species(baseSpeciesID)
        // PokéAPI 응답의 URL — 비정상/빈 값이면 force-unwrap 대신 throw(앱은 알 상태 유지).
        guard let chainURL = Self.validatedChainURL(baseSpecies.evolution_chain.url) else {
            throw URLError(.badURL)
        }
        let chainDTO: ChainDTO = try await get(chainURL)
        let tree = node(from: chainDTO.chain)
        let rarity = Rarity.from(captureRate: baseSpecies.capture_rate,
                                 isLegendary: baseSpecies.is_legendary,
                                 isMythical: baseSpecies.is_mythical)
        // 라인의 모든 종 이름(지원 언어만)
        var names: [Int: [String: String]] = [:]
        for id in allIDs(tree) {
            let sp = try await species(id)
            var byLang: [String: String] = [:]
            for n in sp.names where langCodes.contains(n.language.name) { byLang[n.language.name] = n.name }
            names[id] = byLang
        }
        let line = EvoLine(baseID: baseSpeciesID, tree: tree, rarity: rarity, names: names)
        lineCache[baseSpeciesID] = line
        return line
    }

    // MARK: base 인덱스 (부화 후보)

    private var baseIndexCache: [BaseSpecies]?
    private var restBuildInFlight = false
    private var restBuildTried = false   // 세션당 1회 (GraphQL 다운 시 REST 인덱스 구축 트리거)
    private static let baseIndexFile: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("base-index.json")
    }()
    private struct BaseIndexSnapshot: Codable { let fetchedAt: Date; let entries: [BaseSpecies] }
    private struct GraphQLBaseResponse: Decodable {
        struct DataBox: Decodable { let pokemonspecies: [Row] }
        struct Row: Decodable { let id: Int; let capture_rate: Int }
        let data: DataBox
    }

    /// 1~5세대 base(진화라인 시작점) 전체 — PokéAPI GraphQL 1쿼리.
    /// 우선순위: 메모리 캐시 → 디스크 캐시(30일 TTL) → GraphQL fetch(성공 시 디스크 갱신)
    /// → TTL 지난 디스크라도 있으면 사용(오프라인 폴백). 전부 실패 시 throw(알 유지, 다음 틱 재시도).
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        if let c = baseIndexCache { return c }
        let disk = (try? Data(contentsOf: Self.baseIndexFile))
            .flatMap { try? JSONDecoder().decode(BaseIndexSnapshot.self, from: $0) }
        if let disk, Date().timeIntervalSince(disk.fetchedAt) < 30 * 86400, !disk.entries.isEmpty {
            baseIndexCache = disk.entries
            return disk.entries
        }
        do {
            let entries = try await fetchBaseIndex()
            baseIndexCache = entries
            if let data = try? JSONEncoder().encode(BaseIndexSnapshot(fetchedAt: Date(), entries: entries)) {
                try? data.write(to: Self.baseIndexFile, options: .atomic)
            }
            return entries
        } catch {
            if let disk, !disk.entries.isEmpty {   // 오프라인 — 오래된 인덱스라도 사용
                baseIndexCache = disk.entries
                return disk.entries
            }
            // GraphQL 다운 + 캐시 없음 → REST 로 인덱스를 백그라운드 구축(세션 1회).
            // 이번 부화는 per-hatch REST 폴백(chooseBaseViaREST)이 즉시 처리하고,
            // 구축이 끝나면 디스크 캐시로 남아 이후 선택이 가중·수집반영·오프라인가능으로 복귀한다.
            if !restBuildTried {
                restBuildTried = true
                Task { await self.buildBaseIndexViaREST() }
            }
            AppLog.write("base index (GraphQL) failed, no cache — REST build triggered; per-hatch fallback handles now: \(error)")
            throw error
        }
    }

    /// GraphQL base 인덱스 엔드포인트 장애 시 REST(pokemon-species/{id})로 base 인덱스를 직접 구축·영속.
    /// 한 번 성공하면 base-index.json(30일)으로 남아 이후 선택은 네트워크 없이 가중·수집반영으로 동작 →
    /// 부화가 특정 엔드포인트 생존에 영구히 묶이지 않게 하는 자가치유 캐시. PokéAPI 배려로 소규모 동시성.
    func buildBaseIndexViaREST() async {
        guard baseIndexCache == nil, !restBuildInFlight else { return }
        restBuildInFlight = true
        defer { restBuildInFlight = false }
        AppLog.write("base index: building via REST (GraphQL unavailable)…")
        var bases: [BaseSpecies] = []
        let batchSize = 6
        var start = 1
        let maxID = PokemonAssets.animatedSpeciesIDs.upperBound
        while start <= maxID {
            let end = min(start + batchSize - 1, maxID)
            let found = await withTaskGroup(of: BaseSpecies?.self) { group -> [BaseSpecies] in
                for id in start...end { group.addTask { try? await self.baseSpecies(id: id) } }
                var acc: [BaseSpecies] = []
                for await r in group { if let r { acc.append(r) } }
                return acc
            }
            bases.append(contentsOf: found)
            start += batchSize
        }
        // 대부분 실패(네트워크 불안정)면 빈약한 인덱스를 영속하지 않고 다음 세션 재시도.
        guard bases.count >= 150 else {
            AppLog.write("base index: REST build incomplete (\(bases.count)) — not cached, will retry next session")
            return
        }
        bases.sort { $0.id < $1.id }
        baseIndexCache = bases
        if let data = try? JSONEncoder().encode(BaseIndexSnapshot(fetchedAt: Date(), entries: bases)) {
            try? data.write(to: Self.baseIndexFile, options: .atomic)
        }
        AppLog.write("base index: REST build done — \(bases.count) bases persisted (offline-capable now)")
    }

    private func fetchBaseIndex() async throws -> [BaseSpecies] {
        // 공식 GraphQL — evolves_from IS NULL(=base) + id ≤ 649(Gen-V 애니메이션 스프라이트 상한)
        guard let url = URL(string: "https://graphql.pokeapi.co/v1beta2") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 메타몽(#132)은 위장 리빌 전용 → 일반 부화 풀에서 제외(_neq).
        let maxID = PokemonAssets.animatedSpeciesIDs.upperBound
        let query = "{ pokemonspecies(where: {evolves_from_species_id: {_is_null: true}, id: {_lte: \(maxID), _neq: \(PokemonOdds.dittoSpeciesID)}}, order_by: {id: asc}) { id capture_rate } }"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(GraphQLBaseResponse.self, from: data)
        let entries = decoded.data.pokemonspecies.map { BaseSpecies(id: $0.id, captureRate: $0.capture_rate) }
        guard !entries.isEmpty else { throw URLError(.cannotParseResponse) }
        return entries
    }

    private func species(_ id: Int) async throws -> SpeciesDTO {
        if let c = speciesCache[id] { return c }
        let dto: SpeciesDTO = try await get(base.appendingPathComponent("pokemon-species/\(id)"))
        speciesCache[id] = dto
        return dto
    }

    /// PokéAPI accepts a species slug where an id is expected — same convention `moveDetail(name:)`
    /// already relies on for moves, and the same reverse-slugging caveat (apostrophes dropped,
    /// e.g. "Farfetch'd" -> "farfetchd" wouldn't match PokéAPI's actual "farfetchd" slug — mostly
    /// fine in practice, a failed lookup just leaves that one caller without a sprite/id).
    func speciesID(name: String) async throws -> Int {
        let slug = Self.slug(fromDisplayName: name)
        if let cached = speciesIDByNameCache[slug] { return cached }
        let dto: SpeciesIDDTO = try await get(base.appendingPathComponent("pokemon-species/\(slug)"))
        speciesIDByNameCache[slug] = dto.id
        return dto.id
    }

    /// pokemon-species 는 line(baseSpeciesID:) 가 라인 조회 때 이미 캐시해뒀을 수 있다 —
    /// species(_:) 를 그대로 재사용하므로 그 경우 추가 네트워크 없이 즉시 반환된다.
    func flavorText(speciesID id: Int) async throws -> [String: String] {
        let sp = try await species(id)
        var byLang: [String: String] = [:]
        // 언어당 마지막 항목(대체로 더 최근 게임판) 사용 — 게임판별 표기 차이는 여기선 무시한다.
        for e in sp.flavor_text_entries where langCodes.contains(e.language.name) {
            byLang[e.language.name] = Self.cleanedFlavorText(e.flavor_text)
        }
        return byLang
    }

    /// PokéAPI 도감 설명은 옛 게임 텍스트박스 줄바꿈(\n)·페이지 넘김(\u{0C})·연철 하이픈(\u{AD})이
    /// 그대로 남아있다 — 한 줄 문장으로 정리한다.
    static func cleanedFlavorText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\u{AD}", with: "")
            .replacingOccurrences(of: "\u{0C}", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// REST 폴백 — 단일 종 상세(pokemon-species/{id})로 base 여부·capture_rate 판정.
    /// GraphQL base 인덱스가 죽어도 REST(pokeapi.co/api/v2)는 별개 엔드포인트라 동작한다.
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        guard id != PokemonOdds.dittoSpeciesID else { return nil }   // 메타몽은 위장 리빌 전용 — 일반 부화 제외
        let dto = try await species(id)
        guard dto.evolves_from_species == nil else { return nil }   // 진화 중간체는 부화 후보 아님
        return BaseSpecies(id: id, captureRate: dto.capture_rate)
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func node(from link: ChainLink) -> EvoNode {
        EvoNode(speciesID: Self.id(from: link.species.url ?? ""),
                children: link.evolves_to.map(node(from:)))
    }
    private func allIDs(_ n: EvoNode) -> [Int] { [n.speciesID] + n.children.flatMap(allIDs) }

    static func id(from speciesURL: String) -> Int {
        // ".../pokemon-species/{id}/"
        let parts = speciesURL.split(separator: "/").filter { !$0.isEmpty }
        return Int(parts.last ?? "0") ?? 0
    }

    /// PokéAPI evolution_chain URL 검증(SSRF 가드) — 서버 제어 문자열이므로 https + pokeapi.co 로 고정해
    /// 응답 변조 시 임의 호스트 fetch 를 막는다. 부적합하면 nil(호출부가 throw → 앱은 알 상태 유지).
    static func validatedChainURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme == "https", url.host == "pokeapi.co" else { return nil }
        return url
    }
}

// MARK: - DTO (PokéAPI 응답 부분 디코드)

/// Minimal decode for `speciesID(name:)` — only the id is needed, unlike `SpeciesDTO`'s full shape.
struct SpeciesIDDTO: Decodable, Sendable { let id: Int }
struct SpeciesDTO: Decodable, Sendable {
    let capture_rate: Int
    let is_legendary: Bool
    let is_mythical: Bool
    let names: [NameDTO]
    let evolution_chain: URLRef
    let evolves_from_species: NamedRef?   // nil = 진화라인 시작점(base)
    let flavor_text_entries: [FlavorTextEntryDTO]
    let genera: [GenusEntryDTO]
}
struct FlavorTextEntryDTO: Decodable, Sendable { let flavor_text: String; let language: NamedRef }
struct GenusEntryDTO: Decodable, Sendable { let genus: String; let language: NamedRef }
struct PokemonDTO: Decodable, Sendable {
    let height: Int   // decimeter
    let weight: Int   // hectogram
    let stats: [StatEntryDTO]
    let types: [TypeEntryDTO]
    let abilities: [AbilityEntryDTO]
    let moves: [MoveEntryDTO]
}
struct StatEntryDTO: Decodable, Sendable { let base_stat: Int; let stat: NamedRef }
struct TypeEntryDTO: Decodable, Sendable { let slot: Int; let type: NamedRef }
struct AbilityEntryDTO: Decodable, Sendable { let slot: Int; let is_hidden: Bool; let ability: NamedRef }
struct AbilityDTO: Decodable, Sendable { let names: [NameDTO] }
struct MoveEntryDTO: Decodable, Sendable { let move: NamedRef; let version_group_details: [VersionGroupDetailDTO] }
struct VersionGroupDetailDTO: Decodable, Sendable {
    let level_learned_at: Int
    let move_learn_method: NamedRef
    let version_group: NamedRef
}
struct MoveDTO: Decodable, Sendable {
    /// Not read by moveDetail(id:) — the id is already known there (it's in the request path). Read
    /// by moveDetail(name:), the only caller that doesn't already have it.
    let id: Int
    let name: String
    let power: Int?
    let accuracy: Int?
    let pp: Int
    let type: NamedRef
    let damage_class: NamedRef
    let names: [NameDTO]
}
struct NameDTO: Decodable, Sendable { let name: String; let language: NamedRef }
struct NamedRef: Decodable, Sendable { let name: String; let url: String? }
struct URLRef: Decodable, Sendable { let url: String }
struct ChainDTO: Decodable, Sendable { let chain: ChainLink }
struct ChainLink: Decodable, Sendable {
    let species: NamedRef
    let evolves_to: [ChainLink]
}
