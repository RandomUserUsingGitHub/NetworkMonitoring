import SwiftUI

// MARK: - Root (tab bar)

struct ContentView: View {
    @StateObject private var model = NetworkStateModel()
    @ObservedObject private var settings = Settings.shared
    @State private var tab: Tab = .dashboard
    @State private var showSettings = false

    enum Tab { case dashboard, ipDetails, speedTest }

    var t: AppTheme { model.theme }

    var body: some View {
        ZStack(alignment: .bottom) {
            t.bg.ignoresSafeArea()

            // Page content
            Group {
                switch tab {
                case .dashboard: DashboardView(model: model, showSettings: $showSettings)
                case .ipDetails: IPDetailsView(model: model)
                case .speedTest: SpeedTestView()
                }
            }
            .padding(.bottom, 48)

            // Tab bar
            TabBar(tab: $tab, model: model)
        }
        .onAppear  { model.start() }
        .onDisappear { model.stop() }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model)
        }
        .frame(width: 560, height: 620)
    }
}

// MARK: - Tab bar

struct TabBar: View {
    @Binding var tab: ContentView.Tab
    @ObservedObject var model: NetworkStateModel
    var t: AppTheme { model.theme }

    var body: some View {
        HStack(spacing: 0) {
            TabItem(icon:"wifi", label:"Dashboard",  active: tab == .dashboard, theme:t) { tab = .dashboard }
            TabItem(icon:"globe", label:"IP Details", active: tab == .ipDetails, theme:t) { tab = .ipDetails }
            TabItem(icon:"speedometer", label:"Speed Test", active: tab == .speedTest, theme:t) { tab = .speedTest }
        }
        .frame(height: 48)
        .background(t.bg2)
        .overlay(Rectangle().fill(t.border.opacity(0.2)).frame(height:1), alignment:.top)
    }
}

struct TabItem: View {
    let icon: String; let label: String; let active: Bool; let theme: AppTheme; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size:14, weight: active ? .semibold : .regular))
                Text(label).font(.system(size:9, design:.monospaced))
            }
            .foregroundStyle(active ? theme.accent : theme.dim)
            .frame(maxWidth:.infinity).frame(height:48)
            .contentShape(Rectangle())
            .background(active ? theme.accent.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @ObservedObject var model: NetworkStateModel
    @ObservedObject private var settings = Settings.shared
    @Binding var showSettings: Bool

    var t: AppTheme { model.theme }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HeaderBar(model: model, showSettings: $showSettings).padding(.bottom, 12)
                Divider().overlay(t.border.opacity(0.25))
                StatsGrid(model: model).padding(.vertical, 12)
                Divider().overlay(t.border.opacity(0.25))
                GraphSection(model: model).padding(.vertical, 12)
                Divider().overlay(t.border.opacity(0.25))
                EventsSection(model: model).padding(.top, 12).padding(.bottom, 8)
            }
            .padding(18)
        }
        .background(t.bg)
    }
}

// MARK: - Header

struct HeaderBar: View {
    @ObservedObject var model: NetworkStateModel
    @Binding var showSettings: Bool
    @ObservedObject private var settings = Settings.shared
    var t: AppTheme { model.theme }

    var body: some View {
        HStack(alignment:.center, spacing:10) {
            HStack(spacing:10) {
                ZStack {
                    Circle().fill(t.accent.opacity(0.15)).frame(width:36,height:36)
                    Text("🌐").font(.system(size:20))
                }
                VStack(alignment:.leading, spacing:1) {
                    Text("Network Monitor")
                        .font(.system(size:16, weight:.bold, design:.monospaced)).foregroundStyle(t.accent2)
                    if !settings.subtitleText.isEmpty {
                        Text(settings.subtitleText)
                            .font(.system(size:10, design:.monospaced)).foregroundStyle(t.dim)
                    }
                }
            }
            Spacer()
            // ── Fixed clock: uses a timer published to .main ──
            ClockView(theme: t)
            Button(action:{ showSettings=true }) {
                Image(systemName:"gearshape").font(.system(size:14)).foregroundStyle(t.dim).padding(6)
            }.buttonStyle(.plain)
            DaemonButton(model: model)
        }
    }
}

/// Standalone clock that actually ticks every second
struct ClockView: View {
    let theme: AppTheme
    @State private var now: Date = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss  EEE d MMM"; return f
    }()
    var body: some View {
        Text(fmt.string(from: now))
            .font(.system(size:11, design:.monospaced))
            .foregroundStyle(theme.dim)
            .onReceive(ticker) { now = $0 }
    }
}

struct DaemonButton: View {
    @ObservedObject var model: NetworkStateModel
    @State private var hovering = false
    var t: AppTheme { model.theme }
    var body: some View {
        let running = model.daemonRunning
        let color   = running ? t.online : t.offline
        Button(action:{ model.toggleDaemon() }) {
            Text(running ? "● running" : "⏹ stopped")
                .font(.system(size:12, design:.monospaced)).foregroundStyle(color)
                .padding(.horizontal,12).padding(.vertical,5)
                .background(color.opacity(hovering ? 0.22 : 0.12))
                .clipShape(RoundedRectangle(cornerRadius:7))
                .overlay(RoundedRectangle(cornerRadius:7).stroke(color.opacity(0.4), lineWidth:1))
        }
        .buttonStyle(.plain).onHover{ hovering=$0 }
    }
}

// MARK: - Stats grid

struct StatsGrid: View {
    @ObservedObject var model: NetworkStateModel
    @ObservedObject private var settings = Settings.shared
    var t: AppTheme { model.theme }

    var body: some View {
        Grid(horizontalSpacing:10, verticalSpacing:10) {
            GridRow {
                StatCard(label:"STATUS",   value:statusLabel, color:statusColor, theme:t)
                StatCard(label:"PING  →  \(settings.pingHost)", value:pingLabel, color:pingColor, theme:t)
            }
            GridRow {
                IPCard(model:model)
                StatCard(label:"LOCATION", value:locationLabel, color:t.accent, theme:t)
            }
        }
    }

    private var statusLabel: String {
        switch model.status { case .online: return "● ONLINE"; case .offline: return "✖ OFFLINE"; case .starting: return "◌ Starting…" }
    }
    private var statusColor: Color {
        switch model.status { case .online: return t.online; case .offline: return t.offline; case .starting: return t.warn }
    }
    private var pingLabel: String {
        guard let p = model.latestPing else { return model.status == .offline ? "timeout" : "—" }
        return String(format:"%.1f ms", p)
    }
    private var pingColor: Color {
        guard let p = model.latestPing else { return t.offline }
        if p < settings.thresholdGood { return t.graphOk }
        if p < settings.thresholdWarn { return t.graphMid }
        return t.graphBad
    }
    private var locationLabel: String {
        let c=model.city, k=model.country
        if c.isEmpty||c=="—" { return k }
        return "\(c), \(k)"
    }
}

/// IP card with eye toggle — also censors the log
struct IPCard: View {
    @ObservedObject var model: NetworkStateModel
    @ObservedObject private var settings = Settings.shared
    var t: AppTheme { model.theme }

    var displayIP: String {
        settings.ipHidden ? "••••••••••" : model.publicIP
    }

    var body: some View {
        VStack(alignment:.leading, spacing:4) {
            HStack(spacing:4) {
                Text("PUBLIC IP")
                    .font(.system(size:10, weight:.medium, design:.monospaced)).foregroundStyle(t.dim)
                Spacer()
                Button(action:{ settings.ipHidden.toggle() }) {
                    Image(systemName: settings.ipHidden ? "eye.slash" : "eye")
                        .font(.system(size:11)).foregroundStyle(t.dim)
                }.buttonStyle(.plain)
            }
            Text(displayIP)
                .font(.system(size:16, weight:.semibold, design:.monospaced))
                .foregroundStyle(settings.ipHidden ? t.dim : t.warn)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth:.infinity, alignment:.leading)
        .padding(.horizontal,14).padding(.vertical,10)
        .background(t.bg2)
        .clipShape(RoundedRectangle(cornerRadius:10))
        .overlay(RoundedRectangle(cornerRadius:10).stroke(t.border.opacity(0.3), lineWidth:1))
    }
}

// MARK: - Graph

struct GraphSection: View {
    @ObservedObject var model: NetworkStateModel
    @ObservedObject private var settings = Settings.shared
    var t: AppTheme { model.theme }

    var body: some View {
        VStack(alignment:.leading, spacing:8) {
            HStack {
                Text("PING GRAPH")
                    .font(.system(size:11, weight:.medium, design:.monospaced)).foregroundStyle(t.dim)
                Spacer()
                HStack(spacing:10) {
                    LegendDot(color:t.graphOk,  label:"<\(Int(settings.thresholdGood))ms", theme:t)
                    LegendDot(color:t.graphMid, label:"<\(Int(settings.thresholdWarn))ms", theme:t)
                    LegendDot(color:t.graphBad, label:"≥\(Int(settings.thresholdWarn))ms", theme:t)
                }
            }

            // Key fix: use .id() so SwiftUI recreates the view when graphWidth changes
            PingGraphView(
                data: model.pingHistory,
                theme: t,
                maxPoints: settings.graphWidth,
                thresholdGood: settings.thresholdGood,
                thresholdWarn: settings.thresholdWarn
            )
            .id("graph-\(settings.graphWidth)")   // ← forces redraw on width change

            HStack(spacing:18) {
                if let mn=model.minPing { GraphStat(icon:"↓",label:"min",value:String(format:"%.0fms",mn),theme:t) }
                if let av=model.avgPing { GraphStat(icon:"ø",label:"avg",value:String(format:"%.0fms",av),theme:t) }
                if let mx=model.maxPing { GraphStat(icon:"↑",label:"max",value:String(format:"%.0fms",mx),theme:t) }
                GraphStat(icon:"✕",label:"timeouts",value:"\(model.timeouts)",theme:t)
                Spacer()
            }.font(.system(size:11, design:.monospaced))
        }
    }
}

struct LegendDot: View {
    let color:Color; let label:String; let theme:AppTheme
    var body: some View {
        HStack(spacing:3) {
            Circle().fill(color).frame(width:6,height:6)
            Text(label).font(.system(size:10,design:.monospaced)).foregroundStyle(color)
        }
    }
}
struct GraphStat: View {
    let icon:String; let label:String; let value:String; let theme:AppTheme
    var body: some View {
        HStack(spacing:3) {
            Text(icon).foregroundStyle(theme.accent)
            Text(label).foregroundStyle(theme.dim)
            Text(value).foregroundStyle(theme.text)
        }
    }
}

// MARK: - Events

struct EventsSection: View {
    @ObservedObject var model: NetworkStateModel
    @ObservedObject private var settings = Settings.shared
    var t: AppTheme { model.theme }

    var body: some View {
        VStack(alignment:.leading, spacing:8) {
            Text("EVENTS")
                .font(.system(size:11, weight:.medium, design:.monospaced)).foregroundStyle(t.dim)
            if model.logEntries.isEmpty {
                Text("(no events yet)")
                    .font(.system(size:11, design:.monospaced)).foregroundStyle(t.dim).padding(.vertical,4)
            } else {
                VStack(alignment:.leading, spacing:0) {
                    ForEach(model.logEntries) { entry in
                        EventRow(entry:entry, theme:t)
                        if entry.id != model.logEntries.last?.id {
                            Divider().overlay(t.border.opacity(0.1))
                        }
                    }
                }
                .background(t.bg2)
                .clipShape(RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).stroke(t.border.opacity(0.2),lineWidth:1))
            }
        }
    }
}

struct EventRow: View {
    let entry: LogEntry; let theme: AppTheme
    private var color: Color {
        switch entry.kind { case .outage: return theme.offline; case .restored: return theme.online; case .ipChange: return theme.warn; case .info: return theme.dim }
    }
    var body: some View {
        Text(entry.text)
            .font(.system(size:11, design:.monospaced)).foregroundStyle(color)
            .padding(.horizontal,12).padding(.vertical,6)
            .frame(maxWidth:.infinity, alignment:.leading)
    }
}
