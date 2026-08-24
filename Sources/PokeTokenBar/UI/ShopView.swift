import SwiftUI

/// 상점 카테고리 — 탭하면 그 그룹의 아이템 목록으로 들어간다(PC/도감과 같은 push 패턴).
/// eggs 는 활성 포켓몬이 없으면(알 상태) 목록에서 아예 빠진다 — 즉시 액션(리롤 대상 없음)이라
/// purchasableItems 처럼 "재고만 쌓아둘 수 있는" 것과 다르다(기존 shopEntries 게이트와 동일 규칙).
private enum ShopGroup: Hashable, CaseIterable {
    case items, vitamins, eggs
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
        case .eggs:
            // 알과 같은 실제 스프라이트(speciesID: nil) — 도감·PC 다른 곳의 알 표시와 같은 에셋.
            SpriteView(speciesID: nil, size: 26).frame(width: 30, height: 30)
        }
    }

    private func title(for group: ShopGroup, _ l: L) -> String {
        switch group {
        case .vitamins: return l.shopGroupVitamins
        case .items: return l.shopGroupItems
        case .eggs: return l.shopGroupEggs
        }
    }
    private func subtitle(for group: ShopGroup, _ l: L) -> String {
        switch group {
        case .vitamins: return l.shopGroupVitaminsHint
        case .items: return l.shopGroupItemsHint
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
