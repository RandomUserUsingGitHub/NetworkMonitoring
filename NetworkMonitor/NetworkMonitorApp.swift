import SwiftUI
import AppKit

@main
struct NetworkMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 560, height: 620)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

// MARK: - AppDelegate — menu bar / system tray

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var trayTimer: Timer?
    private var trayModel = TrayModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Settings.shared.writeDaemonConfig()
        setupMenuBar()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateTray(ping: nil, status: .starting)

        // Poll state files every second for tray updates
        trayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.trayModel.refresh()
        }

        // Menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title:"Open Network Monitor", action:#selector(openWindow), keyEquivalent:""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title:"Quit", action:#selector(NSApplication.terminate(_:)), keyEquivalent:"q"))
        statusItem?.menu = menu

        // Observe model changes
        trayModel.onUpdate = { [weak self] ping, status in
            self?.updateTray(ping: ping, status: status)
        }
    }

    private func updateTray(ping: Double?, status: ConnectionStatus) {
        guard let button = statusItem?.button else { return }
        DispatchQueue.main.async {
            switch status {
            case .offline:
                button.title = "🔴 —"
            case .starting:
                button.title = "⚪ …"
            case .online:
                if let p = ping {
                    let icon = p < 80 ? "🟢" : p < 200 ? "🟡" : "🔴"
                    button.title = "\(icon) \(Int(p))ms"
                } else {
                    button.title = "🟢"
                }
            }
        }
    }

    @objc private func openWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // Find an existing content window, or the first window that can become key
        if let window = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first(where: { $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // No window found — the user closed it. Open a new one.
            // For SwiftUI WindowGroup apps, we can re-open via the standard new-window action.
            if #available(macOS 13.0, *) {
                // sendAction for newDocument: triggers WindowGroup to create a new window
                NSApp.sendAction(Selector(("newDocument:")), to: nil, from: nil)
            }
        }
    }
}

// MARK: - TrayModel (lightweight — reads files without full model overhead)

final class TrayModel {
    var onUpdate: ((Double?, ConnectionStatus) -> Void)?
    private let histFile   = URL(fileURLWithPath:"/tmp/.netmon_ping_history")
    private let statusFile = URL(fileURLWithPath:"/tmp/.netmon_status")

    func refresh() {
        let statusRaw = (try? String(contentsOf:statusFile, encoding:.utf8))?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
        let status    = ConnectionStatus(rawValue:statusRaw) ?? .starting

        var ping: Double? = nil
        if let raw = try? String(contentsOf:histFile, encoding:.utf8) {
            let lines = raw.components(separatedBy:.newlines).filter{!$0.isEmpty}
            if let last = lines.last, last != "T" { ping = Double(last) }
        }
        onUpdate?(ping, status)
    }
}
