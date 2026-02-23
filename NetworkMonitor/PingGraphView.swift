import SwiftUI

struct PingGraphView: View {
    let data:      [Double?]
    let theme:     AppTheme
    let maxPoints: Int

    private var numeric: [Double] { data.compactMap { $0 } }
    private var scaleCeil: Double {
        let peak = numeric.max() ?? 0
        for c in [50.0, 100, 150, 200, 300, 500, 1000, 2000] where c >= peak { return c }
        return max(peak * 1.2, 100)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                theme.bg2
                gridLayer(size: geo.size)
                fillLayer(size: geo.size)
                lineLayer(size: geo.size)
                timeoutLayer(size: geo.size)
                dotLayer(size: geo.size)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(height: 90)
    }

    // Layout
    private let padL: CGFloat = 6, padR: CGFloat = 52
    private let padT: CGFloat = 8, padB: CGFloat = 6

    private func slotW(_ w: CGFloat)  -> CGFloat { (w - padL - padR) / CGFloat(maxPoints) }
    private func graphH(_ h: CGFloat) -> CGFloat { h - padT - padB }

    private func xFor(index i: Int, width w: CGFloat) -> CGFloat {
        padL + (CGFloat(i) + CGFloat(maxPoints - data.count)) * slotW(w) + slotW(w) / 2
    }
    private func yFor(value v: Double, height h: CGFloat) -> CGFloat {
        padT + CGFloat(1.0 - min(v / scaleCeil, 1.0)) * graphH(h)
    }
    private func colorFor(_ v: Double) -> Color {
        v < 50 ? theme.graphOk : v < 150 ? theme.graphMid : theme.graphBad
    }

    @ViewBuilder
    private func gridLayer(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach([0.25, 0.5, 0.75, 1.0] as [Double], id: \.self) { frac in
                let yy = padT + CGFloat(1.0 - frac) * graphH(size.height)
                Path { p in
                    p.move(to: CGPoint(x: padL, y: yy))
                    p.addLine(to: CGPoint(x: size.width - padR, y: yy))
                }
                .stroke(theme.dim.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                Text("\(Int(scaleCeil * frac))ms")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(theme.dim)
                    .position(x: size.width - padR + 26, y: yy)
            }
        }
    }

    @ViewBuilder
    private func fillLayer(size: CGSize) -> some View {
        let pts = validPoints(size: size)
        if pts.count > 1 {
            Path { p in
                p.move(to: CGPoint(x: pts.first!.0, y: pts.first!.1))
                for pt in pts.dropFirst() { p.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
                p.addLine(to: CGPoint(x: pts.last!.0,  y: padT + graphH(size.height)))
                p.addLine(to: CGPoint(x: pts.first!.0, y: padT + graphH(size.height)))
                p.closeSubpath()
            }
            .fill(LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: theme.accent.opacity(0.35), location: 0),
                    .init(color: theme.accent.opacity(0.02), location: 1)
                ]),
                startPoint: .top, endPoint: .bottom
            ))
        }
    }

    @ViewBuilder
    private func lineLayer(size: CGSize) -> some View {
        ZStack {
            ForEach(0..<max(0, data.count - 1), id: \.self) { i in
                if let v0 = data[i], let v1 = data[i + 1] {
                    Path { p in
                        p.move(to:    CGPoint(x: xFor(index: i,   width: size.width), y: yFor(value: v0, height: size.height)))
                        p.addLine(to: CGPoint(x: xFor(index: i+1, width: size.width), y: yFor(value: v1, height: size.height)))
                    }
                    .stroke(colorFor((v0 + v1) / 2),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    @ViewBuilder
    private func timeoutLayer(size: CGSize) -> some View {
        ZStack {
            ForEach(0..<data.count, id: \.self) { i in
                if data[i] == nil {
                    Text("✕")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.offline)
                        .position(x: xFor(index: i, width: size.width),
                                  y: padT + graphH(size.height) - 6)
                }
            }
        }
    }

    @ViewBuilder
    private func dotLayer(size: CGSize) -> some View {
        if let lastIdx = (0..<data.count).reversed().first(where: { data[$0] != nil }),
           let val = data[lastIdx] {
            let cx = xFor(index: lastIdx, width: size.width)
            let cy = yFor(value: val, height: size.height)
            Circle().stroke(theme.bg, lineWidth: 2).frame(width: 10, height: 10).position(x: cx, y: cy)
            Circle().fill(theme.accent).frame(width: 7, height: 7).position(x: cx, y: cy)
        }
    }

    private func validPoints(size: CGSize) -> [(CGFloat, CGFloat)] {
        (0..<data.count).compactMap { i in
            guard let v = data[i] else { return nil }
            return (xFor(index: i, width: size.width), yFor(value: v, height: size.height))
        }
    }
}
