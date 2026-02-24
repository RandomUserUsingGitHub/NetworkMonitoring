import SwiftUI
import AppKit

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
                NSApp.activate(ignoringOtherApps: true)
                if let w = NSApp.windows.first(where: { $0.canBecomeKey }) {
                    w.makeKeyAndOrderFront(nil)
                } else {
                    NSApp.sendAction(Selector(("newDocument:")), to: nil, from: nil)
                }
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Settings.shared.writeDaemonConfig()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

// MARK: - Tray Label View
struct TrayLabelView: View {
    @ObservedObject var model: TrayModel
    // Read trayFormat directly from UserDefaults to avoid observing Settings (which triggers save loops)
    private var trayFormat: String {
        UserDefaults.standard.string(forKey: "netmon.trayFormat") ?? "both"
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if ["both", "icon"].contains(trayFormat) {
                switch model.status {
                case .offline:  Text("🔴")
                case .starting: Text("⚪")
                case .online:
                    if let p = model.ping {
                        Text(p < 80 ? "🟢" : p < 200 ? "🟡" : "🔴")
                    } else {
                        Text("🟢")
                    }
                }
            }
            if ["both", "ping"].contains(trayFormat) {
                if model.status == .offline { Text("—") }
                else if model.status == .starting { Text("…") }
                else if let p = model.ping { Text("\(Int(p))ms") }
            }
        }
        .onAppear { model.startRefreshing() }
    }
}

// MARK: - TrayModel (lightweight — reads files without full model overhead)

final class TrayModel: ObservableObject {
    @Published var ping: Double? = nil
    @Published var status: ConnectionStatus = .starting
    
    private var timer: Timer?
    private let histFile   = URL(fileURLWithPath:"/tmp/.netmon_ping_history")
    private let statusFile = URL(fileURLWithPath:"/tmp/.netmon_status")
    
    func startRefreshing() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let statusRaw = (try? String(contentsOf:self.statusFile, encoding:.utf8))?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
            let newStatus = ConnectionStatus(rawValue:statusRaw) ?? .starting

            var newPing: Double? = nil
            if let raw = try? String(contentsOf:self.histFile, encoding:.utf8) {
                let lines = raw.components(separatedBy:.newlines).filter{!$0.isEmpty}
                if let last = lines.last, last != "T" { newPing = Double(last) }
            }
            
            DispatchQueue.main.async {
                self.ping = newPing
                self.status = newStatus
            }
        }
    }
}
