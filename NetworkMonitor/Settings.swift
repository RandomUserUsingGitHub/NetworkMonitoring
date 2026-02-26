import SwiftUI
import ServiceManagement

final class Settings: ObservableObject {
    static let shared = Settings()
    private let ud = UserDefaults.standard

    // Ping
    @Published var pingHost:        String { didSet { save() } }
    @Published var pingInterval:    Double { didSet { save() } }
    @Published var failThreshold:   Int    { didSet { save() } }
    @Published var pingTimeout:     Double { didSet { save() } }
    @Published var packetSize:      Int    { didSet { save() } }
    @Published var historySize:     Int    { didSet { save() } }

    // Graph color thresholds (ms)
    @Published var thresholdGood:   Double { didSet { save() } } // below = green
    @Published var thresholdWarn:   Double { didSet { save() } } // below = yellow, above = red

    // IP
    @Published var ipInterval:       Double { didSet { save() } }
    @Published var censorIPOnChange:  Bool   { didSet { save() } }

    // Tray
    @Published var showTrayIcon: Bool   { didSet { save() } }
    @Published var trayFormat:   String { didSet { save() } } // "icon", "ping", "both"
    @Published var trayUpdateInterval: Double { didSet { save() } }


    // Notifications
    @Published var notificationsEnabled: Bool   { didSet { save() } }
    @Published var notificationSound:    String { didSet { save() } }
    @Published var muteOutagesUntil:     Date   { didSet { save() } }
    
    var isMuted: Bool { muteOutagesUntil > Date() }

    // UI
    @Published var theme:        String { didSet { save() } }
    @Published var graphWidth:   Int    { didSet { save() } }
    @Published var logTailLines: Int    { didSet { save() } }
    @Published var subtitleText: String { didSet { save() } }

    // System
    @Published var launchAtLogin: Bool { didSet { save(); applyLaunchAtLogin() } }

    // Transient
    @Published var ipHidden: Bool = false

    private init() {
        let defaults = UserDefaults.standard
        func d(_ k: String, _ def: Double) -> Double { let v = defaults.double(forKey:k); return v==0 ? def : v }
        func i(_ k: String, _ def: Int)    -> Int    { let v = defaults.integer(forKey:k); return v==0 ? def : v }
        func s(_ k: String, _ def: String) -> String { defaults.string(forKey:k) ?? def }
        func b(_ k: String, _ def: Bool)   -> Bool   { defaults.object(forKey:k) as? Bool ?? def }

        pingHost            = s("netmon.pingHost",   "8.8.8.8")
        pingInterval        = d("netmon.pingInterval", 2.0)
        failThreshold       = i("netmon.failThreshold", 3)
        pingTimeout         = d("netmon.pingTimeout", 2.0)
        packetSize          = i("netmon.packetSize", 56)
        historySize         = i("netmon.historySize", 60)
        thresholdGood       = d("netmon.thresholdGood", 80.0)
        thresholdWarn       = d("netmon.thresholdWarn", 200.0)
        ipInterval          = d("netmon.ipInterval", 10.0)
        censorIPOnChange    = b("netmon.censorIPOnChange", false)
        showTrayIcon        = b("netmon.showTrayIcon", true)
        trayFormat          = s("netmon.trayFormat", "both")
        trayUpdateInterval  = d("netmon.trayUpdateInterval", 2.0)
        notificationsEnabled = b("netmon.notificationsEnabled", true)
        notificationSound   = s("netmon.notificationSound", "Basso")
        muteOutagesUntil    = defaults.object(forKey: "netmon.muteOutagesUntil") as? Date ?? Date.distantPast
        theme               = s("netmon.theme", "green")
        graphWidth          = i("netmon.graphWidth", 60)
        logTailLines        = i("netmon.logTailLines", 7)
        subtitleText        = s("netmon.subtitleText", "by Armin Hashemi")
        launchAtLogin       = b("netmon.launchAtLogin", true)
    }

    func save() {
        ud.set(pingHost,             forKey:"netmon.pingHost")
        ud.set(pingInterval,         forKey:"netmon.pingInterval")
        ud.set(failThreshold,        forKey:"netmon.failThreshold")
        ud.set(pingTimeout,          forKey:"netmon.pingTimeout")
        ud.set(packetSize,           forKey:"netmon.packetSize")
        ud.set(historySize,          forKey:"netmon.historySize")
        ud.set(thresholdGood,        forKey:"netmon.thresholdGood")
        ud.set(thresholdWarn,        forKey:"netmon.thresholdWarn")
        ud.set(ipInterval,           forKey:"netmon.ipInterval")
        ud.set(censorIPOnChange,     forKey:"netmon.censorIPOnChange")
        ud.set(showTrayIcon,         forKey:"netmon.showTrayIcon")
        ud.set(trayFormat,           forKey:"netmon.trayFormat")
        ud.set(trayUpdateInterval,   forKey:"netmon.trayUpdateInterval")
        ud.set(notificationsEnabled, forKey:"netmon.notificationsEnabled")
        ud.set(notificationSound,    forKey:"netmon.notificationSound")
        ud.set(muteOutagesUntil,     forKey:"netmon.muteOutagesUntil")
        ud.set(theme,                forKey:"netmon.theme")
        ud.set(graphWidth,           forKey:"netmon.graphWidth")
        ud.set(logTailLines,         forKey:"netmon.logTailLines")
        ud.set(subtitleText,         forKey:"netmon.subtitleText")
        ud.set(launchAtLogin,        forKey:"netmon.launchAtLogin")
        writeDaemonConfig()
    }

    func writeDaemonConfig() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/network-monitor")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json: [String: Any] = [
            "ping": ["host":pingHost,"interval_seconds":pingInterval,
                     "fail_threshold":failThreshold,"timeout_seconds":pingTimeout,
                     "packet_size":packetSize,"history_size":historySize],
            "ip_check": ["interval_seconds":ipInterval],
            "notifications": ["enabled":notificationsEnabled,"sound":notificationSound,
                              "censor_on_change":censorIPOnChange],
            "ui": ["theme":theme,"ping_graph_width":graphWidth],
            "log": ["tail_lines":logTailLines]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json, options:[.prettyPrinted,.sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("settings.json"))
        }
    }

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.user.network-monitor.plist")
    }

    private func applyLaunchAtLogin() {
        // 1. Enable/Disable daemon background ping script
        if FileManager.default.fileExists(atPath: plistURL.path) {
            let t = Process()
            t.executableURL = URL(fileURLWithPath:"/bin/launchctl")
            t.arguments = [launchAtLogin ? "load" : "unload", plistURL.path]
            t.standardOutput = Pipe(); t.standardError = Pipe()
            try? t.run(); t.waitUntilExit()
        }
        
        // 2. Enable/Disable the main UI app launch
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status == .notRegistered {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("Failed to toggle UI App login startup: \(error.localizedDescription)")
        }
    }
}
