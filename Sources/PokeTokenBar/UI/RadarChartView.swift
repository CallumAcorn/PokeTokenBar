import SwiftUI

/// 6축 레이더(스파이더) 차트 — 0~1로 정규화된 값 여러 시리즈를 같은 축 위에 겹쳐 그린다.
/// IV/EV 처럼 스케일이 다른 값도 각자 자기 최댓값 기준 0~1 로 정규화해 넘기면 "모양"을 바로 비교할 수 있다.
/// 축 순서는 호출부가 정한다 — MonDetailView 는 본가 스탯 요약 화면과 같은 순서(HP→공격→방어→스피드→특방→특공)를 쓴다.
struct RadarChartView: View {
    struct Series {
        let values: [Double]   // 0...1, count == axisLabels.count
        let color: Color
    }

    let axisLabels: [String]
    let series: [Series]
    var size: CGFloat = 150

    private var axisCount: Int { axisLabels.count }
    private static let gridRings: [Double] = [0.25, 0.5, 0.75, 1.0]
    /// 0 값을 중심점(반지름 0, 완전히 안 보임)이 아니라 눈에 보이는 최소 반지름으로 띄운다 —
    /// 안 그러면 EV 를 하나도 안 준 개체는 다각형이 점 하나로 뭉개져 "차트가 비었나?"처럼 보인다.
    /// fraction=1(만점)에서는 그대로 1 이라 만점 스탯의 위치는 안 바뀐다.
    private static let minFraction = 0.1
    private func padded(_ fraction: Double) -> Double {
        Self.minFraction + (1 - Self.minFraction) * min(1, max(0, fraction))
    }

    var body: some View {
        let radius = size / 2 - 16   // 라벨이 원 밖으로 나갈 여백
        ZStack {
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                for ring in Self.gridRings {
                    context.stroke(polygon(center: center, radius: radius, fractions: Array(repeating: ring, count: axisCount)),
                                   with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
                }
                for axis in 0..<axisCount {
                    context.stroke(Path { p in
                        p.move(to: center)
                        p.addLine(to: point(center: center, radius: radius, axis: axis, fraction: 1))
                    }, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
                }
                for s in series where s.values.count == axisCount {
                    let path = polygon(center: center, radius: radius, fractions: s.values.map { min(1, max(0, $0)) })
                    context.fill(path, with: .color(s.color.opacity(0.18)))
                    context.stroke(path, with: .color(s.color), lineWidth: 1.5)
                }
            }
            .frame(width: size, height: size)
            ForEach(0..<axisCount, id: \.self) { axis in
                Text(axisLabels[axis]).font(.system(size: 9)).foregroundStyle(.secondary)
                    .position(labelPosition(radius: radius, axis: axis))
            }
        }
        .frame(width: size, height: size)
    }

    private func angle(for axis: Int) -> Double {
        -Double.pi / 2 + Double(axis) * (2 * .pi / Double(axisCount))   // 12시부터 시계방향
    }
    private func point(center: CGPoint, radius: CGFloat, axis: Int, fraction: Double) -> CGPoint {
        let a = angle(for: axis)
        let r = radius * padded(fraction)
        return CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
    }
    private func polygon(center: CGPoint, radius: CGFloat, fractions: [Double]) -> Path {
        Path { p in
            for axis in 0..<axisCount {
                let pt = point(center: center, radius: radius, axis: axis, fraction: fractions[axis])
                if axis == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
    }
    private func labelPosition(radius: CGFloat, axis: Int) -> CGPoint {
        let center = CGPoint(x: size / 2, y: size / 2)
        let a = angle(for: axis)
        let labelRadius = radius + 11
        return CGPoint(x: center.x + labelRadius * cos(a), y: center.y + labelRadius * sin(a))
    }
}
