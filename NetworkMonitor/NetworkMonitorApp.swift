import SwiftUI
import AppKit
import UserNotifications

@main
struct NetworkMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var trayModel = TrayModel()

    var body: some Scene {
        Window("Network Monitor", id: "main") {
            ContentView()
                .frame(width: 560, height: 620)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands { CommandGroup(replacing: .newItem) {} }
        
        MenuBarExtra {
            OpenWindowMenuItem()
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            TrayLabelView(model: trayModel)
        }
    }
}

struct OpenWindowMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Open Network Monitor") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Settings.shared.writeDaemonConfig()
        Settings.shared.applyLaunchAtLogin()
        
        // Start the monitoring daemon as a background thread
        Daemon.shared.start()
        
        // Clean up old launchd daemon plist (no longer needed)
        let oldPlist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.user.network-monitor.plist")
        if FileManager.default.fileExists(atPath: oldPlist.path) {
            let t = Process()
            t.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            t.arguments = ["unload", oldPlist.path]
            t.standardOutput = Pipe(); t.standardError = Pipe()
            try? t.run(); t.waitUntilExit()
            try? FileManager.default.removeItem(at: oldPlist)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: Notification.Name("ReopenMainWindow"), object: nil)
        }
        return true
    }
}

// MARK: - Tray Label View

struct TrayLabelView: View {
    @ObservedObject var model: TrayModel
    @Environment(\.openWindow) private var openWindow
    @State private var hasAutoOpened = false
    
    var body: some View {
        let isOnline = model.status == .online
        let isLoading = model.status == .starting
        let p = model.ping
        
        let tGood = UserDefaults.standard.double(forKey: "netmon.thresholdGood")
        let tWarn = UserDefaults.standard.double(forKey: "netmon.thresholdWarn")
        let goodThreshold = tGood > 0 ? tGood : 80.0
        let warnThreshold = tWarn > 0 ? tWarn : 200.0
        
        // Quality-based dot
        let dot: String = {
            if !model.isDaemonRunning { return "⚪" } // Handled conditionally in Group
            if isLoading { return "⚪" }
            guard isOnline, let ping = p else { return "🔴" }
            if ping < goodThreshold { return "🟢" }
            if ping < warnThreshold { return "🟡" }
            return "🔴"
        }()
        
        let pingStr: String = {
            if !model.isDaemonRunning { return "Off" }
            if !isOnline { return "Offline" }
            guard let ping = p else { return "—" }
            return "\(Int(ping)) ms"
        }()
        
        let statusStr: String = {
            if !model.isDaemonRunning { return "Off" }
            if isLoading { return "Starting…" }
            guard isOnline else { return "Disconnected" }
            guard let ping = p else { return "Connected" }
            if ping < goodThreshold { return "Good" }
            if ping < warnThreshold { return "Fair" }
            return "Poor"
        }()
        
        // To guarantee perfect vertical alignment between an emoji and text in a MenuBarExtra
        // while maintaining the native text color (white in dark mode, black in light mode),
        // we use a Label. We render ONLY the emoji into an NSImage so it keeps its color,
        // and allow macOS to natively render the text element.
        Group {
            if !model.isDaemonRunning {
                switch model.trayFormat {
                case "icon":
                    if let img = renderEmojiImage(dot: "⚪") { Image(nsImage: img) } else { Text("⚪") }
                case "ping", "status", "both":
                    Text("Off")
                default:
                    Text("Off")
                }
            } else {
                switch model.trayFormat {
                case "icon":
                    if let img = renderEmojiImage(dot: dot) { Image(nsImage: img) } else { Text(dot) }
                case "ping":
                    Text(pingStr)
                case "status":
                    Text(statusStr)
                default: // "both" = icon + ping
                    HStack(alignment: .center, spacing: 4) {
                        if let img = renderEmojiImage(dot: dot) { Image(nsImage: img) } else { Text(dot) }
                        Text(pingStr)
                    }
                }
            }
        }
        .onAppear {
            if !hasAutoOpened {
                hasAutoOpened = true
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ReopenMainWindow"))) { _ in
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @MainActor
    private func renderEmojiImage(dot: String) -> NSImage? {
        let viewToRender = Text(dot).font(.system(size: 13))
        let renderer = ImageRenderer(content: viewToRender)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        renderer.isOpaque = false
        
        guard let cgImage = renderer.cgImage else { return nil }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / Int(renderer.scale), height: cgImage.height / Int(renderer.scale)))
        nsImage.isTemplate = false // Emojis shouldn't be templates, so they keep their intrinsic colors.
        return nsImage
    }
}

// MARK: - TrayModel (lightweight — reads files without full model overhead)

final class TrayModel: ObservableObject {
    @Published var ping: Double? = nil
    @Published var status: ConnectionStatus = .starting
    @Published var trayFormat: String = "both"
    @Published var isDaemonRunning: Bool = true
    @Published var lastUpdateTime: Date? = nil
    
    private var timer: Timer?
    private let histFile   = URL(fileURLWithPath:"/tmp/.netmon_ping_history")
    private let statusFile = URL(fileURLWithPath:"/tmp/.netmon_status")
    private var lastHistFileModDate: Date = .distantPast
    private var lastStatusFileModDate: Date = .distantPast
    private var lastDaemonCheck: Date = .distantPast
    
    init() {
        startRefreshing()
    }
    
    private var lastRefreshTime: Date = .distantPast

    func startRefreshing() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
    }

    private func checkIfDue() {
        let interval = UserDefaults.standard.double(forKey: "netmon.trayUpdateInterval")
        let actualInterval = interval > 0 ? interval : 2.0
        let format = UserDefaults.standard.string(forKey: "netmon.trayFormat") ?? "both"
        
        let now = Date()
        if format != trayFormat {
            lastRefreshTime = now
            refresh()
        } else if now.timeIntervalSince(lastRefreshTime) >= actualInterval {
            lastRefreshTime = now
            refresh()
        }
    }

    private func refresh() {
        let f = UserDefaults.standard.string(forKey: "netmon.trayFormat") ?? "both"
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            // Check modification dates to reduce CPU
            let histMtime = (try? FileManager.default.attributesOfItem(atPath: self.histFile.path)[.modificationDate] as? Date) ?? .distantPast
            let statusMtime = (try? FileManager.default.attributesOfItem(atPath: self.statusFile.path)[.modificationDate] as? Date) ?? .distantPast
            
            // Check daemon status directly
            let now = Date()
            var daemonIsRunning = self.isDaemonRunning
            if now.timeIntervalSince(self.lastDaemonCheck) > 4.0 {
                self.lastDaemonCheck = now
                daemonIsRunning = Daemon.shared.isRunning
            }
            
            if histMtime == self.lastHistFileModDate && statusMtime == self.lastStatusFileModDate && self.trayFormat == f && daemonIsRunning == self.isDaemonRunning {
                return // Nothing changed
            }
            self.lastHistFileModDate = histMtime
            self.lastStatusFileModDate = statusMtime
            
            let updateTime = max(histMtime, statusMtime)
            let newUpdateTime = updateTime == .distantPast ? nil : updateTime
            
            let statusRaw = (try? String(contentsOf:self.statusFile, encoding:.utf8))?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
            let daemonStatus = ConnectionStatus(rawValue:statusRaw) ?? .starting

            var newPing: Double? = nil
            var lastPingFailed = false
            if let raw = try? String(contentsOf:self.histFile, encoding:.utf8) {
                // Optimize reading only the last line (using components is fine since file is small, but let's avoid it if unmodified)
                let lines = raw.components(separatedBy:.newlines).filter{!$0.isEmpty}
                if let last = lines.last {
                    if last == "T" {
                        lastPingFailed = true
                    } else {
                        newPing = Double(last)
                    }
                }
            }
            
            // Real-time status: show ping failure immediately instead of waiting for daemon's fail threshold
            let effectiveStatus: ConnectionStatus
            if daemonStatus == .starting {
                effectiveStatus = .starting
            } else if lastPingFailed {
                effectiveStatus = .offline
            } else {
                effectiveStatus = .online
            }
            
            DispatchQueue.main.async {
                self.ping = newPing
                self.status = effectiveStatus
                self.isDaemonRunning = daemonIsRunning
                self.lastUpdateTime = newUpdateTime
                if self.trayFormat != f { self.trayFormat = f }
            }
        }
    }
}
