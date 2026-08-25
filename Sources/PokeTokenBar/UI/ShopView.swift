import SwiftUI

/// 상점 카테고리 — 탭하면 그 그룹의 아이템 목록으로 들어간다(PC/도감과 같은 push 패턴).
/// eggs 는 활성 포켓몬이 없으면(알 상태) 목록에서 아예 빠진다 — 즉시 액션(리롤 대상 없음)이라
/// purchasableItems 처럼 "재고만 쌓아둘 수 있는" 것과 다르다(기존 shopEntries 게이트와 동일 규칙).
private enum ShopGroup: Hashable, CaseIterable {
    case items, vitamins, tms, eggs
}

/// 상점 — 사용한 토큰(재화 = usedSinceInstall − spentTokens)으로 아이템 구매.
/// 인라인 확인(버튼 morph) — .sheet/.alert 금지(BagView 주석과 동일: transient 팝오버가 닫힐 때
/// 고아 시트가 이후 클릭을 먹통내는 결함 회피).
struct ShopView: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    @State private var selectedGroup: ShopGroup?

    /// eggs 그룹은 활성 포켓몬이 있을 때만 보인다 — 나머지 둘은 항상.
    private var availableGroups: [ShopGroup] {
        ShopGroup.allCases.filter { $0 != .eggs || store.hasActive }
    }

    var body: some View {
        let l = store.l
        // 고정 높이 — 컬렉션/가방과 동일(팝오버 재오픈 시 fitting size 축소 방지).
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let group = selectedGroup {
                    groupHeader(group, l)
                } else {
                    walletHeader(l)
                }
                if let group = selectedGroup {
                    groupContent(group, l)
                } else {
                    groupTiles(l)
                }
            }
        }
        .frame(height: 520)
        // The TM grid's page buttons and the TM detail's buy/cancel buttons reach the trailing edge,
        // and under "always show scroll bars" the thick legacy scroller sits right on top of them —
        // same reason as EvoLineView, `.never` instead of `.hidden`.
        .scrollIndicators(.never)
        // 선택한 그룹이 사라지면(예: 알 상태로 돌아가 eggs 그룹이 빠짐) 목록으로 돌아간다 — 빈 화면 방지.
        .onChange(of: availableGroups) { _, groups in
            if let g = selectedGroup, !groups.contains(g) { selectedGroup = nil }
        }
    }

    private func groupHeader(_ group: ShopGroup, _ l: L) -> some View {
        HStack {
            Button { selectedGroup = nil } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .accessibilityLabel(l.back)
            Text(title(for: group, l)).font(.callout.weight(.semibold))
            Spacer()
        }
    }

    private func groupTiles(_ l: L) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(availableGroups, id: \.self) { group in
                Button {
                    selectedGroup = group
                } label: {
                    groupTile(group, l)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func groupTile(_ group: ShopGroup, _ l: L) -> some View {
        HStack(spacing: 10) {
            groupIcon(group)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: group, l)).font(.callout.weight(.semibold))
                Text(subtitle(for: group, l)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func groupIcon(_ group: ShopGroup) -> some View {
        switch group {
        case .vitamins:
            Image(systemName: "pills.fill").font(.system(size: 20)).foregroundStyle(.orange)
                .frame(width: 30, height: 30)
        case .items:
            Image(systemName: "shippingbox.fill").font(.system(size: 20)).foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
        case .tms:
            Image(systemName: "list.bullet.rectangle.fill").font(.system(size: 20)).foregroundStyle(.blue)
                .frame(width: 30, height: 30)
        case .eggs:
            // 알과 같은 실제 스프라이트(speciesID: nil) — 도감·PC 다른 곳의 알 표시와 같은 에셋.
            SpriteView(speciesID: nil, size: 26).frame(width: 30, height: 30)
        }
    }

    private func title(for group: ShopGroup, _ l: L) -> String {
        switch group {
        case .vitamins: return l.shopGroupVitamins
        case .items: return l.shopGroupItems
        case .tms: return l.shopGroupTMs
        case .eggs: return l.shopGroupEggs
        }
    }
    private func subtitle(for group: ShopGroup, _ l: L) -> String {
        switch group {
        case .vitamins: return l.shopGroupVitaminsHint
        case .items: return l.shopGroupItemsHint
        case .tms: return l.shopGroupTMsHint
        case .eggs: return l.shopGroupEggsHint
        }
    }

    @ViewBuilder
    private func groupContent(_ group: ShopGroup, _ l: L) -> some View {
        switch group {
        case .vitamins:
            walletHeader(l)
            // purchasableItems 가 이미 가격순+구매완료 보유형 하단 정렬을 해두므로, 그룹은 거기서
            // 부분집합만 골라 쓴다 — 정렬 기준을 두 곳에 따로 두지 않는다.
            ForEach(store.purchasableItems.filter { $0.vitaminStat != nil }, id: \.self) { kind in
                ShopItemCard(store: store, kind: kind)
            }
        case .items:
            walletHeader(l)
            ForEach(store.purchasableItems.filter { $0.vitaminStat == nil }, id: \.self) { kind in
                ShopItemCard(store: store, kind: kind)
            }
        case .tms:
            walletHeader(l)
            TMGridView(store: store)
        case .eggs:
            walletHeader(l)
            regionFilter(l)
            ForEach(FreshEgg.shopTiers, id: \.self) { tier in
                EggCard(store: store, nav: nav, tier: tier)
            }
        }
    }

    private func walletHeader(_ l: L) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l.spendableTokens)
                .font(.caption).foregroundStyle(.secondary)
            Text(TokenFormatter.compact(store.availableTokens))
                .font(.system(size: 24, weight: .bold)).monospacedDigit()
            Text(l.shopHint)
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func regionFilter(_ l: L) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(l.eggRegionLabel).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: Binding(
                    get: { store.eggRegion },
                    set: { store.setEggRegion($0) })) {
                    Text(l.eggRegionAll).tag(Region?.none)
                    ForEach(Region.allCases, id: \.self) { Text(l.regionLabel($0)).tag(Region?.some($0)) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            Text(l.eggRegionHint)
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// 상점 아이템 1장 — 아이콘·이름·설명(사탕 XP / 민트 "성격 랜덤 변경")·보유수 + 가격/구매(인라인 확인).
/// kind 별 store.canBuy(kind)/buy(kind) 로 일반화 — 판매 목록은 store.purchasableItems.
private struct ShopItemCard: View {
    let store: CompanionStore
    let kind: ItemKind
    @State private var confirming = false

    private var price: Int { kind.shopPrice ?? 0 }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ItemIconView(kind: kind, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l.itemName(kind)).font(.callout.weight(.semibold))
                        let owned = store.itemCount(kind)
                        if owned > 0 && !kind.isPassive {
                            Text(l.ownedCount(owned)).font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Text(l.itemDescription(kind))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            buyControls(l)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func buyControls(_ l: L) -> some View {
        if kind.isPassive && store.itemCount(kind) > 0 {
            // 보유형(이로치 부적 등) — 1회 구매라 소유 후엔 "적용 중" 표시(재구매 버튼 없음).
            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.green)
                Text(l.ownedAlready).font(.caption2.weight(.semibold)).foregroundStyle(.green)
                Spacer()
            }
        } else if confirming {
            HStack(spacing: 8) {
                Text(l.buyConfirm(l.itemName(kind)))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button(l.buy) { buyNow() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(l.cancel) { confirming = false }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        } else {
            HStack {
                Text("\(l.shopPriceLabel) \(TokenFormatter.compact(price))")
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                Spacer()
                if store.canBuy(kind) {
                    Button(l.buy) { confirming = true }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Text(l.notEnoughTokens)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func buyNow() {
        confirming = false
        _ = store.buy(kind)
    }
}

/// 알 카드 — 구매 = 훈련 중인 개체를 PC 로 돌려보내고(폐기 아님) 새 알로. `tier` 는 보증 등급
/// 하한(nil = 보증 없는 기본 알). 인라인 확인 1단계 — 더 이상 개체를 잃지 않으므로(PC 에 남는다)
/// 이로치 추가 경고는 없다. 성공하면 Home 으로 전환해 새 알을 보여준다.
private struct EggCard: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let tier: Rarity?
    @State private var stage: Stage = .idle
    private enum Stage { case idle, confirm }

    private var price: Int { FreshEgg.price(guaranteeing: tier) }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                SpriteView(speciesID: nil, size: 26)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l.eggName(tier)).font(.callout.weight(.semibold))
                        if let tier {
                            Text(l.rarityLabel(tier).uppercased()).font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(rarityColor(tier)).foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    Text(l.eggDescription(tier))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            controls(l)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func controls(_ l: L) -> some View {
        switch stage {
        case .idle:
            HStack {
                Text("\(l.shopPriceLabel) \(TokenFormatter.compact(price))")
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                Spacer()
                if store.canBuyEgg(tier) {
                    Button(l.buy) { stage = .confirm }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Text(l.notEnoughTokens).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        case .confirm:
            HStack(spacing: 8) {
                Text(l.eggConfirm(store.displayName, l.eggName(tier)))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button(l.buy) { commit() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(l.cancel) { stage = .idle }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        }
    }

    private func commit() {
        stage = .idle
        if store.buyEgg(tier) { nav.tab = .home }
    }
}

/// TM icon — prefers the shared per-type sprite (PokéAPI's item sheet has `tm-{type}.png`, not one
/// per move — only 18 of them, far lighter than species/move sprites). Falls back to an SF Symbol
/// before load / on failure.
private struct TMIconView: View {
    let type: PokemonType
    var size: CGFloat = 30
    @State private var img: NSImage?

    private var spriteName: String { "tm-\(type.rawValue)" }

    init(type: PokemonType, size: CGFloat = 30) {
        self.type = type
        self.size = size
        _img = State(initialValue: SpriteLoader.cachedItemImage(name: "tm-\(type.rawValue)"))
    }

    var body: some View {
        Group {
            if let img {
                Image(nsImage: img).resizable().interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: size * 0.55))
                    .foregroundStyle(typeColor(type))
                    .frame(width: size, height: size)
            }
        }
        .task(id: spriteName) {
            guard img == nil else { return }
            img = await SpriteLoader.itemImage(name: spriteName)
        }
    }
}

/// TM catalog — the same fixed 4×6 page grid as DexGridView, plus a type filter (same spot as the
/// rarity chips, but 18 types don't fit one row, so it scrolls horizontally). Tapping a cell pushes
/// to the detail screen (TMDetailView).
private struct TMGridView: View {
    let store: CompanionStore
    @State private var catalog: [Move] = []
    @State private var selectedType: PokemonType?
    @State private var page = 0
    @State private var selectedMoveID: Int?

    private static let columns = 4
    private static let rows = 6
    private static let pageSize = columns * rows
    private static let spacing: CGFloat = 4

    var body: some View {
        if let id = selectedMoveID, let move = catalog.first(where: { $0.id == id }) {
            TMDetailView(store: store, move: move) { selectedMoveID = nil }
        } else {
            let visible = selectedType.map { t in catalog.filter { $0.type == t } } ?? catalog
            let pageCount = max(1, (visible.count + Self.pageSize - 1) / Self.pageSize)
            let current = min(page, pageCount - 1)
            let slice = Array(visible.dropFirst(current * Self.pageSize).prefix(Self.pageSize))
            VStack(alignment: .leading, spacing: 8) {
                Text(store.l.tmCatalogTitle).font(.callout.weight(.semibold))
                typeFilter
                grid(slice)
                footer(current: current, pageCount: pageCount)
            }
            .task { if catalog.isEmpty { catalog = await store.tmCatalog() } }
        }
    }

    private var typeFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(PokemonType.allCases, id: \.self) { t in
                    let count = catalog.lazy.filter { $0.type == t }.count
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedType = (selectedType == t) ? nil : t
                            page = 0
                        }
                    } label: {
                        Text(store.l.typeName(t).uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(selectedType == t ? typeColor(t) : typeColor(t).opacity(0.25))
                            .foregroundStyle(selectedType == t ? .white : Color.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(count == 0)
                }
            }
        }
    }

    private func grid(_ slice: [Move]) -> some View {
        VStack(spacing: Self.spacing) {
            ForEach(0..<Self.rows, id: \.self) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(0..<Self.columns, id: \.self) { col in
                        let i = row * Self.columns + col
                        if i < slice.count {
                            let move = slice[i]
                            TMCell(store: store, move: move) { selectedMoveID = move.id }
                                .frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func footer(current: Int, pageCount: Int) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 4)
            if pageCount > 1 {
                Button { page = max(0, current - 1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).disabled(current == 0)
                    .accessibilityLabel(store.l.dexPagePrev)
                Text("\(current + 1) / \(pageCount)")
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.secondary)
                Button { page = min(pageCount - 1, current + 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain).disabled(current == pageCount - 1)
                    .accessibilityLabel(store.l.dexPageNext)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .frame(height: 18)
    }
}

/// One cell in the TM grid — same size/shape as DexSpeciesCell. Shows an owned-count badge top-right when count > 0.
private struct TMCell: View {
    let store: CompanionStore
    let move: Move
    let onTap: () -> Void

    private static let thumb: CGFloat = 44

    var body: some View {
        let owned = store.tmCount(move.id)
        Button(action: onTap) {
            VStack(spacing: 1) {
                TMIconView(type: move.type, size: Self.thumb)
                Text(move.localizedName(store.language))
                    .font(.system(size: 9))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                if owned > 0 {
                    Text("×\(owned)")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .padding(3)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

/// TM detail — type/power/accuracy/PP/damage class + owned count + inline-confirm buy (same pattern as ShopItemCard).
private struct TMDetailView: View {
    let store: CompanionStore
    let move: Move
    var onClose: () -> Void
    @State private var confirming = false
    /// nil = not computed yet (loading), otherwise the set of PC mon ids that can learn this TM.
    @State private var compatibleMonIDs: Set<MonState.ID>?

    private var owned: Int { store.tmCount(move.id) }
    private var compatibleMons: [MonState] {
        guard let compatibleMonIDs else { return [] }
        return store.party.filter { compatibleMonIDs.contains($0.id) }
    }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: onClose) { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).accessibilityLabel(l.back)
                Text(l.tmCatalogTitle).font(.callout.weight(.semibold))
                Spacer()
            }
            HStack(spacing: 12) {
                TMIconView(type: move.type, size: 56)
                    .frame(width: 56, height: 56)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(move.localizedName(store.language)).font(.callout.weight(.semibold))
                    Text(l.typeName(move.type).uppercased()).font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(typeColor(move.type)).foregroundStyle(.white).clipShape(Capsule())
                    if owned > 0 {
                        Text(l.tmOwnedCount(owned)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            statsRow(l)
            compatibleSection(l)
            walletHeader(l)
            buyControls(l)
        }
        // Caches learnsets by species across the party, so even multiple mons of the same species only cost one lookup.
        .task(id: move.id) {
            var compatible: Set<MonState.ID> = []
            var learnsetCache: [Int: [LearnableMove]] = [:]
            for mon in store.party {
                let learnset: [LearnableMove]
                if let cached = learnsetCache[mon.currentID] {
                    learnset = cached
                } else {
                    learnset = await store.learnableMoves(speciesID: mon.currentID)
                    learnsetCache[mon.currentID] = learnset
                }
                if learnset.contains(where: { $0.moveID == move.id && $0.method == .machine }) {
                    compatible.insert(mon.id)
                }
            }
            compatibleMonIDs = compatible
        }
    }

    /// PC mons that can learn this TM — sprite+name badges laid out horizontally (same scroll pattern as the filter chips).
    @ViewBuilder
    private func compatibleSection(_ l: L) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l.tmCompatibleTitle).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            if compatibleMonIDs == nil {
                Text("···").font(.caption2).foregroundStyle(.tertiary)
            } else if compatibleMons.isEmpty {
                Text(l.tmNoCompatiblePC).font(.caption2).foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(compatibleMons) { mon in
                            CompatiblePCMonBadge(store: store, mon: mon)
                        }
                    }
                }
            }
        }
    }

    private func statsRow(_ l: L) -> some View {
        HStack(spacing: 16) {
            statCell(l.movePowerLabel, move.power.map(String.init) ?? l.moveNoPower)
            statCell(l.moveAccuracyLabel, move.accuracy.map { "\($0)%" } ?? l.moveNoPower)
            statCell(l.movePPLabel, "\(move.pp)")
            statCell("", l.moveDamageClassName(move.damageClass))
            Spacer()
        }
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if !label.isEmpty { Text(label).font(.caption2).foregroundStyle(.secondary) }
            Text(value).font(.caption.weight(.semibold)).monospacedDigit()
        }
    }

    private func walletHeader(_ l: L) -> some View {
        HStack {
            Text(l.spendableTokens).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(TokenFormatter.compact(store.availableTokens)).font(.caption.weight(.bold)).monospacedDigit()
        }
    }

    @ViewBuilder
    private func buyControls(_ l: L) -> some View {
        if confirming {
            HStack(spacing: 8) {
                Text(l.buyConfirm(move.localizedName(store.language)))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button(l.buy) { confirming = false; store.buyTM(move.id) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(l.cancel) { confirming = false }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        } else {
            HStack {
                Text("\(l.shopPriceLabel) \(TokenFormatter.compact(TM.price))")
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                Spacer()
                if store.canBuyTM(move.id) {
                    Button(l.buy) { confirming = true }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Text(l.notEnoughTokens).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

/// Compatible-PC-mon badge — sprite + species name (line lookup, same pattern as MonDetailView.displayName).
private struct CompatiblePCMonBadge: View {
    let store: CompanionStore
    let mon: MonState
    @State private var name: String?

    var body: some View {
        VStack(spacing: 1) {
            SpriteView(speciesID: mon.currentID, size: 32, shiny: mon.isShiny)
                .frame(width: 32, height: 32)
            Text(name ?? "#\(mon.currentID)")
                .font(.system(size: 8))
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 40)
        }
        .task(id: "\(mon.baseID)-\(store.language.rawValue)") {
            let line = await store.line(baseID: mon.baseID)
            name = line?.localizedName(mon.currentID, store.language)
        }
    }
}
