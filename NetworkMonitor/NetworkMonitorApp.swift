import SwiftUI
import AppKit
import UserNotifications

@main
struct NetworkMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var trayModel = TrayModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .frame(width: 560, height: 620)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands { CommandGroup(replacing: .newItem) {} }
        
        MenuBarExtra {
            Button("Open Network Monitor") {
                AppDelegate.showMainWindow()
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            TrayLabelView(model: trayModel)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Keep a reference to the window so we can always surface it
    private static var mainWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Settings.shared.writeDaemonConfig()
        
        // Capture the main window reference once it's created
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            AppDelegate.mainWindow = NSApp.windows.first(where: {
                $0.canBecomeKey && !$0.className.contains("StatusBar")
            })
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppDelegate.showMainWindow() }
        return true
    }

    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // Aggressively search for any SwiftUI content window
        let systemPrefixes = ["NSStatusBar", "_NSPopover", "NSMenuWindow", 
                              "_NSBackstage", "_NSAlert", "NSPanel"]
        
        let contentWindows = NSApp.windows.filter { w in
            let cls = String(describing: type(of: w))
            return !systemPrefixes.contains(where: { cls.contains($0) })
        }
        
        // Try cached reference first
        if let w = mainWindow, contentWindows.contains(where: { $0 === w }) {
            w.makeKeyAndOrderFront(nil)
            w.orderFrontRegardless()
            return
        }
        
        // Find any existing content window (visible or not)
        if let w = contentWindows.first(where: { $0.canBecomeKey }) ?? contentWindows.first {
            w.makeKeyAndOrderFront(nil)
            w.orderFrontRegardless()
            mainWindow = w
            return
        }

        // Absolutely no window found — ask SwiftUI to open one
        // Use the undocumented but reliable selector that SwiftUI registers for WindowGroup
        NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
        
        // Capture the new window after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            mainWindow = NSApp.windows.first(where: { w in
                let cls = String(describing: type(of: w))
                return !systemPrefixes.contains(where: { cls.contains($0) }) && w.canBecomeKey
            })
            mainWindow?.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Tray Label View

struct TrayLabelView: View {
    @ObservedObject var model: TrayModel
    
    var body: some View {
        let isOnline = model.status == .online
        let isLoading = model.status == .starting
        let p = model.ping
        
        // Quality-based dot
        let dot: String = {
            if isLoading { return "⚪" }
            guard isOnline, let ping = p else { return "🔴" }
            if ping < 80 { return "🟢" }
            if ping < 200 { return "🟡" }
            return "🔴"
        }()
        
        let pingStr: String = {
            if !isOnline { return "Offline" }
            guard let ping = p else { return "—" }
            return "\(Int(ping)) ms"
        }()
        
        let statusStr: String = {
            if isLoading { return "Starting…" }
            guard isOnline else { return "Disconnected" }
            guard let ping = p else { return "Connected" }
            if ping < 80 { return "Good" }
            if ping < 200 { return "Fair" }
            return "Poor"
        }()
        
        switch model.trayFormat {
        case "icon":
            Text(dot)
        case "ping":
            // Ping only — no icon dot
            Text(pingStr)
        case "status":
            // Status text only — no icon dot
            Text(statusStr)
        default: // "both" = icon + ping
            Text("\(dot) \(pingStr)")
        }
    }
}

// MARK: - TrayModel (lightweight — reads files without full model overhead)

final class TrayModel: ObservableObject {
    @Published var ping: Double? = nil
    @Published var status: ConnectionStatus = .starting
    @Published var trayFormat: String = "both"
    
    private var timer: Timer?
    private let histFile   = URL(fileURLWithPath:"/tmp/.netmon_ping_history")
    private let statusFile = URL(fileURLWithPath:"/tmp/.netmon_status")
    
    init() {
        startRefreshing()
    }
    
    func startRefreshing() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        let f = UserDefaults.standard.string(forKey: "netmon.trayFormat") ?? "both"
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let statusRaw = (try? String(contentsOf:self.statusFile, encoding:.utf8))?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
            let daemonStatus = ConnectionStatus(rawValue:statusRaw) ?? .starting

            var newPing: Double? = nil
            var lastPingFailed = false
            if let raw = try? String(contentsOf:self.histFile, encoding:.utf8) {
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
                if self.trayFormat != f { self.trayFormat = f }
            }
        }
    }
}
