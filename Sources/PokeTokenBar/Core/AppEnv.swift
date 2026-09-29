import Foundation

/// 실행 환경 판별 — 한 곳에서만 정의해 중복 게이트의 drift(일부만 조건이 어긋나는 것)를 막는다.
enum AppEnv {
    /// 정식 `.app` 번들로 실행 중인가. 알림 전송·키체인 읽기·스프라이트 프리패치·프로덕션 로그 기록 등
    /// "실앱 전용" 부수효과의 단일 게이트 — `swift test`/로우 바이너리(dev 실행)에선 false.
    /// bundleIdentifier(Info.plist)와 경로 접미사를 함께 확인(둘 다 실앱에서만 참).
    static var isBundledApp: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// 저장소가 자기 파일을 읽고 써도 되는가.
    ///
    /// 경로를 **주입했으면** 언제나 허용한다 — 테스트가 임시 파일로 영속화를 검증하는 방식이다. 주입하지
    /// 않아 **기본(사용자) 경로**로 떨어진 저장소는 실앱에서만 영속화한다. 그래야 `swift test` 가 사용자의
    /// 실제 파일을 건드리지 않는다.
    ///
    /// 왜 저장소 쪽에 두는가: 테스트가 경로를 주입해서는 못 막는다. 주입은 그 테스트만 덮고 **프로세스**는
    /// 못 덮으므로, 기본 경로로 가는 분기는 테스트에서 보이지 않는다. 실측(2026-09-29, 앱 종료 상태):
    /// 전체 테스트 한 번에 사용자 실제 `usage-cache.json` 이 726,929 → 763,881 바이트로 바뀌었다 —
    /// 이 세션 내내 테스트를 돌릴 때마다 사용자 데이터를 고쳐 쓰고 있었다(상류 d6d24a04 와 같은 결함).
    /// 규칙은 여기 한 곳에만 둔다 — 저장소마다 복사하면 다음 복사본에서 빠뜨린다.
    /// 한도 프로바이더가 **실제** 자격증명을 읽고 원격 엔드포인트를 불러도 되는가.
    ///
    /// `UsageStore` 는 한도 프로바이더를 기본값으로 **진짜** 것(`OAuthLimitsProvider()` 등)을 쓰고, 스텁을
    /// 주입하지 않은 테스트가 열 개쯤 있다(실측). 그 테스트가 refresh 를 돌리면, 마침 Keychain 승인이 살아
    /// 있는 순간에는 무UI 읽기가 성공해 **사용자의 실제 토큰으로 api.anthropic.com 을 부른다** — 사용자의
    /// 한도 요청량을 소모하고(실앱이 그 뒤 429 백오프를 맞는다), Antigravity 면 refresh 토큰까지 쓴다.
    ///
    /// 실앱에서만 허용하고, 개발자가 **일부러** 실측하려면 `PTB_PARITY=1` 로 켠다(로컬 패리티 테스트와 같은
    /// 스위치). 스텁을 주입한 테스트는 이 게이트를 지나지 않으므로 영향이 없다.
    static var allowsLiveLimitsFetch: Bool {
        allowLiveLimitsFetchForTesting || isBundledApp || ProcessInfo.processInfo.environment["PTB_PARITY"] == "1"
    }

    /// 키체인 규율 테스트 전용 opt-in. 반드시 `KeychainReader.stubStatusForTesting` 과 **같이** 켠다 —
    /// 게이트만 열면 프로바이더가 실제 키체인을 읽는다. 게이트를 닫아 둔 채면 프로바이더 로직이 아예 안
    /// 돌아서, "자동 경로는 키체인을 안 읽는다"가 프로바이더의 규율이 아니라 게이트 때문에 참이 된다.
    nonisolated(unsafe) static var allowLiveLimitsFetchForTesting = false

    static func persistsToUserLocation(injectedFileURL: URL?,
                                       isBundledApp: Bool = AppEnv.isBundledApp) -> Bool {
        injectedFileURL != nil || isBundledApp
    }
}
