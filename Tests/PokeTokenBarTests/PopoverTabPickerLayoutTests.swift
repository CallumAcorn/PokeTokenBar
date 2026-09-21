import XCTest
import SwiftUI
@testable import PokeTokenBar

/// 팝오버 상단 탭 선택기의 폭 가드.
///
/// 세그먼티드 컨트롤은 모든 세그먼트를 가장 긴 라벨에 맞추므로, 한 언어에서 라벨 하나만 길어져도 네 칸이
/// 함께 넓어져 콘텐츠 폭을 넘는다. `.frame(width:)` 는 자르지 않고 가운데 정렬만 하므로, 넘친 만큼
/// 팝오버 **내용 전체**가 좌우로 잘려 나간다(탭 라벨도, 토큰 숫자도).
///
/// `ProviderTabLayoutTests` 가 프로바이더 캡슐 바에 대해 같은 가드를 이미 갖고 있었는데 메인 탭
/// 선택기만 빠져 있었다 — 그래서 한국어에서는 멀쩡해 보이는 채로 나머지 네 언어가 깨진 채 나갔다.
///
/// **실측(로컬 Xcode 27 / Swift 6.4, 2026-09-21)** — `.controlSize(.small)` 적용 후 자연 폭:
///
///     ko 196 · pt 252 · es 288 · en 292 · fr 292 · ja 332
///
/// 일본어가 예산(332)과 **정확히 같다**. PR 작성자가 잰 값은 324 였는데 그 사이 Xcode 27 로 올라가며
/// 폰트 메트릭이 8pt 늘었다. 즉 지금 일본어를 붙잡고 있는 건 여유가 아니라 `maxWidth` 클램프다 —
/// 그 클램프는 장식이 아니라 **하중을 받는 부재**이니 지우지 말 것.
@MainActor
final class PopoverTabPickerLayoutTests: XCTestCase {

    /// 제안 폭. 예산(332)을 제안하면 세그먼티드 컨트롤이 제안을 꽉 채워 항상 332 를 돌려주므로,
    /// 자연 폭을 재려면 넉넉히 제안해 컨트롤이 스스로 원하는 크기를 말하게 해야 한다.
    private static let probeWidth: CGFloat = 2000

    private func renderedWidth(_ lang: AppLanguage) -> CGFloat {
        var tab = PopoverTab.home
        let binding = Binding(get: { tab }, set: { tab = $0 })
        // `unclamped` 를 잰다 — 완성된 body 는 maxWidth 클램프 때문에 어떤 언어든 332 를 돌려주고,
        // 그러면 "예산 안에 들어온다"와 "넘쳤지만 잘렸다"를 구분하지 못한다.
        let view = PopoverTabPicker(l: L(lang), selection: binding).unclamped
        return NSHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: Self.probeWidth, height: 600)).width
    }

    /// 지원 언어 **전부**가 예산 안에 들어와야 한다. 한 언어라도 넘치면 그 언어 사용자에게는 팝오버가
    /// 통째로 잘려 보인다.
    ///
    /// `NSSegmentedControl` 은 AppKit 백업 컨트롤이라 고유 크기를 계산하려면 실제 데스크톱 세션이
    /// 필요하다. 헤드리스 CI(macos-15 러너)에서는 레이아웃이 돌지 않아 **제안 폭이 그대로 되돌아온다** —
    /// 그 상태의 숫자는 폭에 대해 아무것도 말해주지 않으므로, 실패로 위장하지 말고 건너뛴다.
    /// (이 결함은 정확히 그렇게 드러났다: 로컬 통과, CI 에서 전 언어 2000.0.)
    func testEveryLanguageFitsThePopoverContentWidth() throws {
        let probe = renderedWidth(.ko)
        try XCTSkipIf(probe >= Self.probeWidth,
                      "AppKit이 고유 크기를 계산하지 않는 환경(헤드리스) — 측정값이 제안 폭 그대로라 의미 없음")

        for lang in AppLanguage.allCases {
            let w = renderedWidth(lang)
            XCTAssertLessThanOrEqual(w, PopoverMetrics.contentWidth,
                                     "\(lang.rawValue): 탭 선택기 폭 \(w) 가 예산 \(PopoverMetrics.contentWidth) 를 넘는다")
        }
    }
}
