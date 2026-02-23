import Foundation

// MARK: - Types

enum ConnectionStatus: String {
    case online   = "ONLINE"
    case offline  = "OFFLINE"
    case starting = "STARTING"
}

struct LogEntry: Identifiable {
    let id   = UUID()
    let text: String
    let kind: Kind
    enum Kind { case outage, restored, ipChange, info }
}

// MARK: - Model

final class NetworkStateModel: ObservableObject {

    @Published var status:        ConnectionStatus = .starting
    @Published var pingHistory:   [Double?]        = []
    @Published var latestPing:    Double?           = nil
    @Published var publicIP:      String            = "fetching…"
    @Published var country:       String            = "—"
    @Published var city:          String            = "—"
    @Published var logEntries:    [LogEntry]        = []
    @Published var daemonRunning: Bool              = false

    var settings: Settings { Settings.shared }
    var theme: AppTheme    { AppTheme.named(settings.theme) }

    var avgPing: Double? {
        let v = pingHistory.compactMap { $0 }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
    var minPing:  Double? { pingHistory.compactMap { $0 }.min() }
    var timeouts: Int     { pingHistory.filter { $0 == nil }.count }

    // File paths
    private let histFile   = URL(fileURLWithPath: "/tmp/.netmon_ping_history")
    private let ipFile     = URL(fileURLWithPath: "/tmp/.netmon_ip_state")
    private let statusFile = URL(fileURLWithPath: "/tmp/.netmon_status")
    private let logFile    = FileManager.default.homeDirectoryForCurrentUser
                               .appendingPathComponent(".network_monitor.log")
    private let daemonPlist = FileManager.default.homeDirectoryForCurrentUser
                               .appendingPathComponent("Library/LaunchAgents/com.user.network-monitor.plist")

    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        readStatus()
        readPingHistory()
        readIPState()
        readLog()
        checkDaemon()
    }

    // MARK: - Readers

    private func readStatus() {
        guard let raw = try? String(contentsOf: statusFile, encoding: .utf8)
        else { status = .starting; return }
        status = ConnectionStatus(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .starting
    }

    private func readPingHistory() {
        guard let raw = try? String(contentsOf: histFile, encoding: .utf8)
        else { pingHistory = []; latestPing = nil; return }
        let lines = raw.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let tail  = Array(lines.suffix(settings.graphWidth))
        pingHistory = tail.map {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t == "T" ? nil : Double(t)
        }
        latestPing = pingHistory.last.flatMap { $0 }
    }

    private func readIPState() {
        guard let raw = try? String(contentsOf: ipFile, encoding: .utf8) else { return }
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "|")
        let ip    = parts.count > 0 ? parts[0] : ""
        publicIP  = (ip.isEmpty || ip == "fetching") ? "fetching…" : ip
        country   = parts.count > 1 ? parts[1] : "—"
        city      = parts.count > 2 ? parts[2] : "—"
        if country.isEmpty { country = "—" }
        if city == country  { city = "" }
    }

    private func readLog() {
        guard let raw = try? String(contentsOf: logFile, encoding: .utf8)
        else { logEntries = []; return }
        let lines = Array(raw.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .suffix(settings.logTailLines))
        logEntries = lines.map { line in
            var short = line
            if line.count > 21 && line.hasPrefix("[20") {
                let i12 = line.index(line.startIndex, offsetBy: 12)
                let i19 = line.index(line.startIndex, offsetBy: 19)
                let i21 = line.index(line.startIndex, offsetBy: 21)
                short = "[" + line[i12..<i19] + "]" + line[i21...]
            }
            let kind: LogEntry.Kind
            if      line.contains("OUTAGE")     || line.contains("failed")     { kind = .outage   }
            else if line.contains("restored")   || line.contains("Restored")   { kind = .restored }
            else if line.contains("IP changed") || line.contains("Initial IP") { kind = .ipChange }
            else                                                                { kind = .info     }
            return LogEntry(text: short, kind: kind)
        }
    }

    private func checkDaemon() {
        let task = Process()
        task.executableURL  = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments      = ["list"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError  = Pipe()
        do {
            try task.run(); task.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async { self.daemonRunning = out.contains("com.user.network-monitor") }
        } catch {
            DispatchQueue.main.async { self.daemonRunning = false }
        }
    }

    // MARK: - Daemon control

    func toggleDaemon() {
        let action = daemonRunning ? "unload" : "load"
        let task   = Process()
        task.executableURL  = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments      = [action, daemonPlist.path]
        task.standardOutput = Pipe(); task.standardError = Pipe()
        try? task.run(); task.waitUntilExit()

        // After changing settings, restart daemon so it picks up new config
        if !daemonRunning {
            settings.writeDaemonConfig()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.refresh() }
    }

    func restartDaemon() {
        guard daemonRunning else { return }
        // Unload
        let stop = Process()
        stop.executableURL  = URL(fileURLWithPath: "/bin/launchctl")
        stop.arguments      = ["unload", daemonPlist.path]
        stop.standardOutput = Pipe(); stop.standardError = Pipe()
        try? stop.run(); stop.waitUntilExit()

        settings.writeDaemonConfig()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let start = Process()
            start.executableURL  = URL(fileURLWithPath: "/bin/launchctl")
            start.arguments      = ["load", self.daemonPlist.path]
            start.standardOutput = Pipe(); start.standardError = Pipe()
            try? start.run(); start.waitUntilExit()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh() }
        }
    }
}
