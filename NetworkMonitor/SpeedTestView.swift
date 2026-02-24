import SwiftUI

struct SpeedTestView: View {
    @ObservedObject var vm: SpeedTestModel
    @ObservedObject  private var settings = Settings.shared
    var t: AppTheme { AppTheme.named(settings.theme) }

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headerRow
                    serverPicker
                    gaugeRow
                    if !vm.samples.isEmpty || vm.phase.isRunning { progressSection }
                    if case .done = vm.phase { resultCards }
                    if !vm.history.isEmpty   { historySection }
                }
                .padding(18)
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("SPEED TEST")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(t.accent2)
                Text(vm.phase.label)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(t.dim)
            }
            Spacer()

            // Skip button — visible during download or upload
            if case .download = vm.phase {
                skipButton(label: "Skip ↓")
            } else if case .upload = vm.phase {
                skipButton(label: "Skip ↑")
            }

            Button(action: { vm.phase.isRunning ? vm.cancel() : vm.run() }) {
                HStack(spacing: 6) {
                    Image(systemName: vm.phase.isRunning ? "stop.fill" : "play.fill")
                    Text(vm.phase.isRunning ? "Stop" : "Run Test")
                }
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(t.bg)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(vm.phase.isRunning ? t.offline : t.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    private func skipButton(label: String) -> some View {
        Button(action: { vm.skip() }) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(t.warn)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(t.warn.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(t.warn.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Server picker

    private var serverPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SERVER")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(t.dim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SpeedServer.presets) { server in
                        ServerChip(
                            server: server,
                            selected: vm.selectedServer.id == server.id,
                            theme: t
                        ) {
                            if !vm.phase.isRunning { vm.selectedServer = server }
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
                .padding(.trailing, 20)
            }
        }
    }

    // MARK: - Gauges

    private var gaugeRow: some View {
        HStack(spacing: 10) {
            SpeedGauge(
                label: "PING",
                value: vm.pingMs.map { "\(Int($0)) ms" } ?? "—",
                icon: "antenna.radiowaves.left.and.right",
                color: t.warn, theme: t
            )
            SpeedGauge(
                label: "DOWNLOAD",
                value: vm.downloadMbps.map { fmtMbps($0) } ?? (vm.liveSpeed > 0 ? fmtMbps(vm.liveSpeed) : "—"),
                icon: "arrow.down.circle",
                color: t.graphOk, theme: t
            )
            SpeedGauge(
                label: "UPLOAD",
                value: vm.uploadMbps.map { fmtMbps($0) } ?? "—",
                icon: "arrow.up.circle",
                color: t.accent, theme: t
            )
        }
    }

    // MARK: - Progress + live chart

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LIVE SPEED")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(t.dim)
                Spacer()
                if vm.liveSpeed > 0 {
                    Text(fmtMbps(vm.liveSpeed))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(t.accent)
                }
            }
            // Progress bar removed per request

            // Side-by-side charts: Download | Upload
            let dlSamples = vm.samples.filter { $0.phase == .download }
            let ulSamples = vm.samples.filter { $0.phase == .upload }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("↓ DOWNLOAD")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(t.graphOk)
                    if dlSamples.count > 1 {
                        SingleSparkline(samples: dlSamples, color: t.graphOk, theme: t)
                            .frame(height: 70)
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(t.bg2).frame(height: 70)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("↑ UPLOAD")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(t.accent)
                    if ulSamples.count > 1 {
                        SingleSparkline(samples: ulSamples, color: t.accent, theme: t)
                            .frame(height: 70)
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(t.bg2).frame(height: 70)
                    }
                }
            }
        }
    }

    // MARK: - Results

    private var resultCards: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RESULTS — \(vm.testedServer?.name ?? vm.selectedServer.name)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(t.dim)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    ResultCard(label: "Download", value: fmtMbps(vm.downloadMbps ?? 0),
                               sub: ratingLabel(vm.downloadMbps ?? 0), color: t.graphOk, theme: t)
                    ResultCard(label: "Upload",   value: fmtMbps(vm.uploadMbps   ?? 0),
                               sub: ratingLabel(vm.uploadMbps   ?? 0), color: t.accent,  theme: t)
                }
                GridRow {
                    ResultCard(label: "Ping",   value: "\(Int(vm.pingMs ?? 0)) ms",
                               sub: pingRating(vm.pingMs ?? 0), color: t.warn, theme: t)
                    ResultCard(label: "Jitter", value: "\(Int(vm.jitterMs ?? 0)) ms",
                               sub: "ping variance",            color: t.graphMid, theme: t)
                }
            }
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HISTORY")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(t.dim)
                Spacer()
                if !vm.history.isEmpty {
                    Button(action: { vm.history.removeAll() }) {
                        Text("Clear")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(t.dim)
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(spacing: 0) {
                ForEach(vm.history) { r in
                    HistoryRow(result: r, theme: t, onDelete: { vm.deleteHistoryItem(r) })
                    if r.id != vm.history.last?.id {
                        Divider().overlay(t.border.opacity(0.1))
                    }
                }
            }
            .background(t.bg2)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(t.border.opacity(0.2), lineWidth: 1))
        }
    }

    // MARK: - Helpers

    private func fmtMbps(_ v: Double) -> String {
        v >= 1000
            ? String(format: "%.2f Gbps", v / 1000)
            : String(format: "%.1f Mbps", v)
    }

    private func ratingLabel(_ v: Double) -> String {
        if v < 5   { return "Very slow" }
        if v < 25  { return "Slow" }
        if v < 100 { return "Good" }
        if v < 500 { return "Fast" }
        return "Excellent"
    }

    private func pingRating(_ v: Double) -> String {
        if v < 20  { return "Excellent" }
        if v < 50  { return "Good" }
        if v < 100 { return "Fair" }
        if v < 200 { return "Slow" }
        return "High latency"
    }
}

// MARK: - Sub-views

struct ServerChip: View {
    let server: SpeedServer
    let selected: Bool
    let theme: AppTheme
    let action: () -> Void
    var body: some View {
        VStack(spacing: 2) {
            Text(server.name)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .fixedSize(horizontal: true, vertical: false)
            Text(server.location)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(selected ? theme.bg.opacity(0.7) : theme.dim)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(selected ? theme.bg : theme.text)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(selected ? theme.accent : theme.bg2)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .stroke(theme.border.opacity(selected ? 0 : 0.3), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }
}

struct SpeedGauge: View {
    let label: String; let value: String; let icon: String; let color: Color; let theme: AppTheme
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(color)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(theme.dim)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(theme.bg2)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border.opacity(0.3), lineWidth: 1))
    }
}

struct ResultCard: View {
    let label: String; let value: String; let sub: String; let color: Color; let theme: AppTheme
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(theme.dim)
            Text(value).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(color)
            Text(sub).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(theme.bg2)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border.opacity(0.3), lineWidth: 1))
    }
}

struct SingleSparkline: View {
    let samples: [SpeedSample]
    let color: Color
    let theme: AppTheme

    var body: some View {
        GeometryReader { geo in
            let peak = max(samples.map { $0.mbps }.max() ?? 1, 1) // Ensure peak is at least 1
            let n    = samples.count
            ZStack(alignment: .topLeading) {
                theme.bg2
                
                // Grid lines & labels
                if peak > 1 {
                    VStack(spacing: 0) {
                        gridLine(label: String(format: "%.0f", peak), color: color.opacity(0.4), geo: geo)
                        Spacer()
                        gridLine(label: String(format: "%.0f", peak / 2), color: color.opacity(0.2), geo: geo)
                        Spacer()
                    }
                }
                
                if n > 1 {
                    let pts: [CGPoint] = samples.enumerated().map { (i, s) in
                        CGPoint(
                            x: geo.size.width  * CGFloat(i) / CGFloat(n - 1),
                            y: geo.size.height * CGFloat(1 - (s.mbps / peak))
                        )
                    }
                    // Fill
                    Path { p in
                        p.move(to: pts.first!)
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts.last!.x,  y: geo.size.height))
                        p.addLine(to: CGPoint(x: pts.first!.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [color.opacity(0.4), color.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    // Line
                    Path { p in
                        p.move(to: pts.first!)
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private func gridLine(label: String, color: Color, geo: GeometryProxy) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(theme.dim)
                .frame(width: 24, alignment: .trailing)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: geo.size.width - 26, y: 0))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(height: 1)
        }
        .padding(.top, 2)
    }
}

struct HistoryRow: View {
    let result: SpeedResult
    let theme: AppTheme
    var onDelete: () -> Void
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm  d MMM"; return f
    }()
    @State private var hovering = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.server)
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(theme.text)
                Text(Self.fmt.string(from: result.date))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.dim)
            }
            Spacer()
            HStack(spacing: 12) {
                Text(String(format: "↓ %.0fM", result.downloadMbps))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.graphOk)
                Text(String(format: "↑ %.0fM", result.uploadMbps))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.accent)
                Text(String(format: "~%.0fms", result.pingMs))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.warn)
            }
            // Delete button on hover
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.dim.opacity(hovering ? 1 : 0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .onHover { hovering = $0 }
    }
}

