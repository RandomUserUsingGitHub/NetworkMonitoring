import SwiftUI
import Combine

// MARK: - Settings (persisted in UserDefaults, editable in-app)

final class Settings: ObservableObject {

    static let shared = Settings()

    // ── Ping ────────────────────────────────────────────────────
    @Published var pingHost:        String  { didSet { save() } }
    @Published var pingInterval:    Double  { didSet { save() } }
    @Published var failThreshold:   Int     { didSet { save() } }
    @Published var pingTimeout:     Double  { didSet { save() } }
    @Published var packetSize:      Int     { didSet { save() } }
    @Published var historySize:     Int     { didSet { save() } }

    // ── IP ──────────────────────────────────────────────────────
    @Published var ipInterval:      Double  { didSet { save() } }
    @Published var censorIPOnChange: Bool   { didSet { save() } }

    // ── Notifications ───────────────────────────────────────────
    @Published var notificationsEnabled: Bool   { didSet { save() } }
    @Published var notificationSound:    String { didSet { save() } }

    // ── UI ──────────────────────────────────────────────────────
    @Published var theme:           String  { didSet { save() } }
    @Published var graphWidth:      Int     { didSet { save() } }
    @Published var logTailLines:    Int     { didSet { save() } }
    @Published var subtitleText:    String  { didSet { save() } }

    // ── System ──────────────────────────────────────────────────
    @Published var launchAtLogin:   Bool    { didSet { save(); applyLaunchAtLogin() } }

    // ── Transient (not saved) ───────────────────────────────────
    @Published var ipHidden: Bool = false

    private let ud = UserDefaults.standard
    private let prefix = "netmon."

    private init() {
        // Load with defaults
        pingHost            = ud.string(forKey:  "netmon.pingHost")         ?? "8.8.8.8"
        pingInterval        = ud.double(forKey:  "netmon.pingInterval").nonZero ?? 2.0
        failThreshold       = ud.integer(forKey: "netmon.failThreshold").nonZero ?? 3
        pingTimeout         = ud.double(forKey:  "netmon.pingTimeout").nonZero  ?? 2.0
        packetSize          = ud.integer(forKey: "netmon.packetSize").nonZero   ?? 56
        historySize         = ud.integer(forKey: "netmon.historySize").nonZero  ?? 60

        ipInterval          = ud.double(forKey:  "netmon.ipInterval").nonZero   ?? 10.0
        censorIPOnChange    = ud.object(forKey:  "netmon.censorIPOnChange") as? Bool ?? false

        notificationsEnabled = ud.object(forKey: "netmon.notificationsEnabled") as? Bool ?? true
        notificationSound   = ud.string(forKey:  "netmon.notificationSound")    ?? "Basso"

        theme               = ud.string(forKey:  "netmon.theme")            ?? "green"
        graphWidth          = ud.integer(forKey: "netmon.graphWidth").nonZero ?? 60
        logTailLines        = ud.integer(forKey: "netmon.logTailLines").nonZero ?? 7
        subtitleText        = ud.string(forKey:  "netmon.subtitleText")     ?? "by Armin Hashemi"

        launchAtLogin       = ud.object(forKey:  "netmon.launchAtLogin") as? Bool ?? true
    }

    func save() {
        ud.set(pingHost,             forKey: "netmon.pingHost")
        ud.set(pingInterval,         forKey: "netmon.pingInterval")
        ud.set(failThreshold,        forKey: "netmon.failThreshold")
        ud.set(pingTimeout,          forKey: "netmon.pingTimeout")
        ud.set(packetSize,           forKey: "netmon.packetSize")
        ud.set(historySize,          forKey: "netmon.historySize")
        ud.set(ipInterval,           forKey: "netmon.ipInterval")
        ud.set(censorIPOnChange,     forKey: "netmon.censorIPOnChange")
        ud.set(notificationsEnabled, forKey: "netmon.notificationsEnabled")
        ud.set(notificationSound,    forKey: "netmon.notificationSound")
        ud.set(theme,                forKey: "netmon.theme")
        ud.set(graphWidth,           forKey: "netmon.graphWidth")
        ud.set(logTailLines,         forKey: "netmon.logTailLines")
        ud.set(subtitleText,         forKey: "netmon.subtitleText")
        ud.set(launchAtLogin,        forKey: "netmon.launchAtLogin")

        // Also write settings.json for the bash daemon
        writeDaemonConfig()
    }

    // Write ~/.config/network-monitor/settings.json for the daemon
    func writeDaemonConfig() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir  = home.appendingPathComponent(".config/network-monitor")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url  = dir.appendingPathComponent("settings.json")
        let json: [String: Any] = [
            "ping": [
                "host":             pingHost,
                "interval_seconds": pingInterval,
                "fail_threshold":   failThreshold,
                "timeout_seconds":  pingTimeout,
                "packet_size":      packetSize,
                "history_size":     historySize
            ],
            "ip_check": ["interval_seconds": ipInterval],
            "notifications": [
                "enabled": notificationsEnabled,
                "sound":   notificationSound,
                "censor_on_change": censorIPOnChange
            ],
            "ui": [
                "theme":            theme,
                "ping_graph_width": graphWidth
            ],
            "log": ["tail_lines": logTailLines]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }

    // LaunchAgent plist path
    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.user.network-monitor.plist")
    }

    private func applyLaunchAtLogin() {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments     = [launchAtLogin ? "load" : "unload", plistURL.path]
        task.standardOutput = Pipe(); task.standardError = Pipe()
        try? task.run(); task.waitUntilExit()
    }
}

// Helpers
private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
