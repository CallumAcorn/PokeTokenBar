import AppKit

/// Front (every existing screen) or back (the local player's own active mon on the battle screen —
/// the real games' own convention: you see your own mon from behind, the opponent's face-on).
enum SpriteFacing: Equatable {
    case front, back
}

/// 포켓몬 스프라이트를 런타임에 받아 로컬(Application Support)에 캐시. 레포/번들에 미포함.
actor SpriteStore {
    static let shared = SpriteStore()
    private let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon"
    private let itemBase = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items"
    private let badgeBase = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/badges"
    private var mem: [String: Data] = [:]
    private var memOrder: [String] = []   // LRU 순서(최근 접근이 뒤). 상한 초과 시 앞(오래된 것)부터 evict
    // in-memory 스프라이트 캐시 상한 — 세션 중 종 변경 누적 무한증가 방지(#H1).
    // 도감 한 페이지가 24칸이라 상한 24 는 LRU 가 매 페이지 전환마다 완전 회전했다(돌아올 때 디스크
    // 동기 재읽기 24회). 정적 PNG 는 종당 0.5~1KB 라 64 로 올려도 메모리 비용이 무의미하다.
    private let memLimit = 64
    private let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar/sprites")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// 캐시 파일명 키 — 기존 "\(id)-a"/"\(id)-s" 유지, shiny 는 "sh" 접두(구캐시 그대로 유효).
    /// facing=.back 은 "bk" 접두 — 기존(.front) 캐시 파일명과 절대 겹치지 않아야 앞뒤가 안 섞인다.
    static func cacheKey(speciesID: Int, animated: Bool, shiny: Bool, facing: SpriteFacing = .front) -> String {
        "\(speciesID)-\(facing == .back ? "bk" : "")\(shiny ? "sh" : "")\(animated ? "a" : "s")"
    }

    /// Sprites are the one remote payload the app writes to disk, so the response is checked
    /// before it lands there: right host, plausible size, and a real image header. A 200 from a
    /// CDN is not on its own a reason to persist arbitrary bytes into Application Support.
    static let allowedSpriteHosts: Set<String> = ["raw.githubusercontent.com"]
    /// Largest sprite in the PokéAPI set is a few hundred KB; 5 MB is generous headroom and
    /// still bounds what a redirect or a compromised mirror could write.
    static let maxSpriteBytes = 5 * 1024 * 1024

    /// PNG / GIF / JPEG / WebP magic numbers. Checked rather than trusting Content-Type, and
    /// deliberately permissive across the four formats so a legitimate sprite is never rejected.
    nonisolated static func hasImageMagic(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        guard bytes.count >= 4 else { return false }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true }          // PNG
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return true }          // GIF87a/89a
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return true }                // JPEG
        if bytes.count >= 12, bytes.starts(with: [0x52, 0x49, 0x46, 0x46]),
           Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50] { return true }      // RIFF....WEBP
        return false
    }

    /// Fetch sprite bytes, returning nil unless every check passes.
    nonisolated static func fetchImageData(_ url: URL) async -> Data? {
        guard url.scheme == "https", let host = url.host, allowedSpriteHosts.contains(host) else {
            return nil
        }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              !data.isEmpty, data.count <= maxSpriteBytes,
              hasImageMagic(data)
        else { return nil }
        return data
    }

    func data(speciesID: Int, animated: Bool, shiny: Bool = false, facing: SpriteFacing = .front) async -> Data? {
        if animated, !PokemonAssets.hasAnimatedSprite(speciesID: speciesID) { return nil }
        let key = Self.cacheKey(speciesID: speciesID, animated: animated, shiny: shiny, facing: facing)
        if let d = mem[key] { touch(key); return d }
        let ext = animated ? "gif" : "png"
        let file = dir.appendingPathComponent("\(key).\(ext)")
        if let d = try? Data(contentsOf: file) { remember(key, d); return d }
        // "back/" is a path *prefix*, ahead of "shiny/" when both apply — matches the sprites repo's
        // own directory layout (sprites/pokemon/back/shiny/{id}.png, not shiny/back/{id}.png).
        let backSegment = facing == .back ? "back/" : ""
        let urlStr: String
        switch (animated, shiny) {
        case (true, false):  urlStr = "\(base)/versions/generation-v/black-white/animated/\(backSegment)\(speciesID).gif"
        case (true, true):   urlStr = "\(base)/versions/generation-v/black-white/animated/\(backSegment)shiny/\(speciesID).gif"
        case (false, false): urlStr = "\(base)/\(backSegment)\(speciesID).png"
        case (false, true):  urlStr = "\(base)/\(backSegment)shiny/\(speciesID).png"
        }
        guard let url = URL(string: urlStr), let d = await Self.fetchImageData(url) else { return nil }
        try? d.write(to: file, options: .atomic)   // torn write 방지 — 크래시/강제종료 시 손상 캐시가 남지 않게
        remember(key, d)
        return d
    }

    /// 아이템 스프라이트(정적 PNG, 이름 기반). 포켓몬과 같은 메모리/디스크 캐시 사용(키 "item-<name>",
    /// 포켓몬 파일 "<id>-..." 과 안 겹침). 미제공(404)/오프라인이면 nil → 뷰가 이모지로 폴백.
    func data(itemName: String) async -> Data? {
        let key = "item-\(itemName)"
        if let d = mem[key] { touch(key); return d }
        let file = dir.appendingPathComponent("\(key).png")
        if let d = try? Data(contentsOf: file) { remember(key, d); return d }
        guard let url = URL(string: "\(itemBase)/\(itemName).png"),
              let d = await Self.fetchImageData(url) else { return nil }
        try? d.write(to: file, options: .atomic)
        remember(key, d)
        return d
    }

    /// 체육관 배지 스프라이트(정적, badges/{n}.png — 번호는 GymBadge.artworkSpriteNumber). 아이템과
    /// 같은 메모리/디스크 캐시(키 "badge-<n>", 포켓몬/아이템 파일명과 안 겹침). 미제공(404)/오프라인이면
    /// nil → 뷰가 seal 글리프로 폴백.
    func data(badgeSpriteNumber: Int) async -> Data? {
        let key = "badge-\(badgeSpriteNumber)"
        if let d = mem[key] { touch(key); return d }
        let file = dir.appendingPathComponent("\(key).png")
        if let d = try? Data(contentsOf: file) { remember(key, d); return d }
        guard let url = URL(string: "\(badgeBase)/\(badgeSpriteNumber).png"),
              let d = await Self.fetchImageData(url) else { return nil }
        try? d.write(to: file, options: .atomic)
        remember(key, d)
        return d
    }

    /// 알 스프라이트(정적, pokemon/egg.png) — 애니메이션 알은 없음. 포켓몬/아이템과 같은 메모리·디스크 캐시(키 "egg").
    func eggData() async -> Data? {
        let key = "egg"
        if let d = mem[key] { touch(key); return d }
        let file = dir.appendingPathComponent("egg.png")
        if let d = try? Data(contentsOf: file) { remember(key, d); return d }
        guard let url = URL(string: "\(base)/egg.png"),
              let d = await Self.fetchImageData(url) else { return nil }
        try? d.write(to: file, options: .atomic)
        remember(key, d)
        return d
    }

    /// in-memory 캐시에 넣고 LRU 상한 유지(#H1) — 세션 중 종이 여러 번 바뀌어도 무한 성장 방지.
    private func remember(_ key: String, _ data: Data) {
        mem[key] = data
        touch(key)
        while memOrder.count > memLimit {
            let old = memOrder.removeFirst()
            mem.removeValue(forKey: old)
        }
    }
    /// 접근/삽입 키를 최근(뒤)으로 이동 — 활성 종이 evict 되지 않게 하는 LRU.
    private func touch(_ key: String) {
        if let i = memOrder.firstIndex(of: key) { memOrder.remove(at: i) }
        memOrder.append(key)
    }
}

@MainActor
enum SpriteLoader {
    static let cacheDir: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar/sprites")
    }()

    /// 디스크 캐시에 이미 있으면 동기 반환(네트워크 없음). 없으면 nil.
    /// shiny 캐시 미스는 일반 캐시로 폴백 — 오프라인에서 live mon 이 알 글리프로 보이는 것 방지.
    static func cachedImage(speciesID: Int, animated: Bool = false, shiny: Bool = false, facing: SpriteFacing = .front) -> NSImage? {
        let ext = animated ? "gif" : "png"
        let key = SpriteStore.cacheKey(speciesID: speciesID, animated: animated, shiny: shiny, facing: facing)
        let f = cacheDir.appendingPathComponent("\(key).\(ext)")
        if let d = try? Data(contentsOf: f), let img = NSImage(data: d) { return img }
        guard shiny else { return nil }
        return cachedImage(speciesID: speciesID, animated: animated, shiny: false, facing: facing)
    }

    /// 정적 스프라이트. animated=true 면 Gen-V 움직이는 스프라이트(없으면 정적으로 폴백).
    /// shiny=true 는 색이 다른 스프라이트 — 미제공 종이면 일반으로 폴백.
    static func image(speciesID: Int, animated: Bool = false, shiny: Bool = false, facing: SpriteFacing = .front) async -> NSImage? {
        if animated, let d = await SpriteStore.shared.data(speciesID: speciesID, animated: true, shiny: shiny, facing: facing),
           let img = NSImage(data: d) {
            return img
        }
        if let d = await SpriteStore.shared.data(speciesID: speciesID, animated: false, shiny: shiny, facing: facing),
           let img = NSImage(data: d) {
            return img
        }
        // shiny 미제공 → 일반 폴백
        guard shiny else { return nil }
        return await image(speciesID: speciesID, animated: animated, shiny: false, facing: facing)
    }

    /// 아이템 스프라이트 — 디스크 캐시 동기 조회(없으면 nil). 아이콘 즉시 표시용(재렌더 플래시 방지).
    static func cachedItemImage(name: String) -> NSImage? {
        let f = cacheDir.appendingPathComponent("item-\(name).png")
        if let d = try? Data(contentsOf: f), let img = NSImage(data: d) { return img }
        return nil
    }

    /// 아이템 스프라이트 — 런타임 로드(+캐시). 미제공/실패면 nil(뷰가 이모지로 폴백).
    static func itemImage(name: String) async -> NSImage? {
        guard let d = await SpriteStore.shared.data(itemName: name), let img = NSImage(data: d) else { return nil }
        return img
    }

    /// 체육관 배지 스프라이트 — 디스크 캐시 동기 조회(없으면 nil). 아이콘 즉시 표시용(재렌더 플래시 방지).
    static func cachedBadgeImage(spriteNumber: Int) -> NSImage? {
        let f = cacheDir.appendingPathComponent("badge-\(spriteNumber).png")
        if let d = try? Data(contentsOf: f), let img = NSImage(data: d) { return img }
        return nil
    }

    /// 체육관 배지 스프라이트 — 런타임 로드(+캐시). 미제공/실패면 nil(뷰가 seal 글리프로 폴백).
    static func badgeImage(spriteNumber: Int) async -> NSImage? {
        guard let d = await SpriteStore.shared.data(badgeSpriteNumber: spriteNumber), let img = NSImage(data: d) else { return nil }
        return img
    }

    /// 알 스프라이트는 96×96 캔버스에 실제 알이 28×30(≈29%)만 차지 — 그대로 쓰면 프레임에서 아주 작게
    /// 보인다(🥚 이모지는 여백이 없어 꽉 찼음). 콘텐츠 경계로 1회 크롭해 여백을 제거하고 캐시 →
    /// 상점·홈 등 모든 크기에서 이모지처럼 프레임을 꽉 채운다.
    private static var croppedEgg: NSImage?

    /// 크롭 완료분만 동기 반환(미준비면 nil — 동기 크롭 안 함, 히치 방지). 첫 표시 때만 🥚 폴백 후 eggImage 로 교체.
    static func cachedEggImage() -> NSImage? { croppedEgg }

    /// 알 스프라이트 — 런타임 로드 + 콘텐츠 크롭(최초 1회 메모이즈). 오프라인/실패면 nil(뷰가 🥚 폴백).
    static func eggImage() async -> NSImage? {
        if let c = croppedEgg { return c }
        guard let d = await SpriteStore.shared.eggData(), let img = NSImage(data: d) else { return nil }
        croppedEgg = cropToContent(img)
        return croppedEgg
    }

    /// 비투명(alpha>0) 콘텐츠 경계로 크롭 — 큰 투명 여백 제거. 96×96 1회만 수행(메모이즈).
    private static func cropToContent(_ image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return image }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }
        // 콘텐츠 bbox 를 정사각(긴 변 기준)으로 확장해 중앙 정렬 — 알 콘텐츠는 28×30(세로가 김)이라 그대로
        // 크롭하면 SpriteView 의 size×size 정사각 프레임에서 가로로 늘어나 뚱뚱해진다. 정사각 크롭이면 비율 보존.
        let bw = maxX - minX + 1, bh = maxY - minY + 1
        let side = min(max(bw, bh), min(w, h))
        let sx = max(0, min(minX - (side - bw) / 2, w - side))
        let sy = max(0, min(minY - (side - bh) / 2, h - side))
        guard let cg = rep.cgImage?.cropping(to: CGRect(x: sx, y: sy, width: side, height: side))
        else { return image }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

/// 스프라이트를 정사각 프레임에 넣을 때의 **비율 유지** 기하 — 팝오버(SpriteView)와 메뉴바가 공유한다.
///
/// Gen-V 움직이는 스프라이트(GIF)는 캔버스가 종마다 다르고 정사각이 아니다 — 잭키(#325) 36×66,
/// 피카츄(#25) 50×46, 팬텀(#143) 74×75. 반면 정적 스프라이트는 96×96, 아이템은 30×30 으로 전부
/// 정사각이라 "size×size 로 늘려 채우기"가 정적 경로에서는 아무 증상이 없다가 GIF 경로에서만
/// 왜곡으로 드러났다(잭키 = 가로 1.83배). 두 호출부가 같은 식을 쓰게 여기로 모은다.
enum SpriteFit {
    /// `box`×`box` 정사각 안에 원본 비율을 유지해 맞춘 크기(contentMode .fit — 긴 변이 box 에 닿는다).
    /// 원본 크기가 비었으면(디코드 실패 등) 정사각 폴백 — 0 나눗셈 방지.
    static func size(for pixelSize: CGSize, box: CGFloat) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return CGSize(width: box, height: box) }
        let scale = min(box / pixelSize.width, box / pixelSize.height)
        return CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }
}
