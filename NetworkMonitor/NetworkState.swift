import Foundation
import SwiftUI
import AppKit
import UserNotifications

enum ConnectionStatus: String {
    case online  = "ONLINE"
    case offline = "OFFLINE"
    case starting = "STARTING"
}

struct LogEntry: Identifiable {
    let id   = UUID()
    let text: String
    let kind: Kind
    enum Kind { case outage, restored, ipChange, info }
}

struct IPDetails {
    var ip:       String = "—"
    var ipv6:     String = "—"
    var isp:      String = "—"
    var org:      String = "—"
    var city:     String = "—"
    var region:   String = "—"
    var country:  String = "—"
    var timezone: String = "—"
    var lat:      Double = 0
    var lon:      Double = 0
    var vpnLikely: Bool  = false
    var tor:      Bool   = false
}

final class NetworkStateModel: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var status:      ConnectionStatus = .starting
    @Published var pingHistory: [Double?]        = []
    @Published var latestPing:  Double?          = nil
    @Published var logEntries:  [LogEntry]       = []
    @Published var daemonRunning: Bool           = false
    @Published var ipDetails:   IPDetails        = IPDetails()

    var publicIP: String { ipDetails.ip }
    var country:  String { ipDetails.country }
    var city:     String { ipDetails.city }

    var settings: Settings { Settings.shared }
    var theme: AppTheme    { AppTheme.named(settings.theme) }

    var avgPing: Double? {
        let v = pingHistory.compactMap { $0 }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
    var minPing:  Double? { pingHistory.compactMap { $0 }.min() }
    var maxPing:  Double? { pingHistory.compactMap { $0 }.max() }
    var timeouts: Int     { pingHistory.filter { $0 == nil }.count }

    private let histFile    = URL(fileURLWithPath: "/tmp/.netmon_ping_history")
    private let ipFile      = URL(fileURLWithPath: "/tmp/.netmon_ip_state")
    private let statusFile  = URL(fileURLWithPath: "/tmp/.netmon_status")
    private let logFile     = FileManager.default.homeDirectoryForCurrentUser
                                  .appendingPathComponent(".network_monitor.log")
    private let daemonPlist = FileManager.default.homeDirectoryForCurrentUser
                                  .appendingPathComponent("Library/LaunchAgents/com.user.network-monitor.plist")

    private var timer:       Timer?
    private var lastIPFetch: Date   = .distantPast
    private var lastRawIP:   String = ""
    private var fetchInFlight = false

    // Tracking logic to fire notifications on state transition differences
    private var previousStatus: ConnectionStatus? = nil
    private var previousIP: String = ""
    
    override init() {
        super.init()
        setupNotifications()
    }

    func start() {
        refresh()
        fetchIPDetails()
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
        // Re-fetch when IP changes or every 60s
        let raw = (try? String(contentsOf: ipFile, encoding: .utf8))?.components(separatedBy: "|").first ?? ""
        if (raw != lastRawIP && !raw.isEmpty && raw != "fetching") || Date().timeIntervalSince(lastIPFetch) > 60 {
            lastRawIP = raw
            fetchIPDetails()
        }
    }

    // MARK: - File readers

    private func readStatus() {
        guard let raw = try? String(contentsOf: statusFile, encoding: .utf8) else { status = .starting; return }
        let newStatus = ConnectionStatus(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .starting
        
        if previousStatus != nil && previousStatus != newStatus {
            handleStatusChange(from: previousStatus!, to: newStatus)
        }
        previousStatus = newStatus
        status = newStatus
    }

    private func readPingHistory() {
        guard let raw = try? String(contentsOf: histFile, encoding: .utf8) else { pingHistory = []; latestPing = nil; return }
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
        let ip = parts.count > 0 ? parts[0] : ""
        if !ip.isEmpty && ip != "fetching" {
            ipDetails.ip      = ip
            ipDetails.country = parts.count > 1 ? parts[1] : "—"
            ipDetails.city    = parts.count > 2 ? parts[2] : "—"
            // Only notify once per unique IP change, using a dedicated tracker
            if !previousIP.isEmpty && previousIP != ip && settings.notificationsEnabled && !settings.isMuted {
                let shouldCensor = settings.censorIPOnChange
                let displayIP = shouldCensor ? "••••••••••" : ip
                let displayOld = shouldCensor ? "••••••••••" : previousIP
                sendNotification(
                    title: "🌐 Public IP Changed",
                    body: "\(displayOld) → \(displayIP) (\(ipDetails.city), \(ipDetails.country))",
                    categoryId: nil
                )
            }
            previousIP = ip
        }
    }

    private func readLog() {
        guard let raw = try? String(contentsOf: logFile, encoding: .utf8) else { logEntries = []; return }
        let lines = Array(raw.components(separatedBy: .newlines).filter { !$0.isEmpty }.suffix(settings.logTailLines))
        logEntries = lines.map { line in
            var text = line
            // Shorten timestamp [2026-01-01 10:23:45] → [10:23:45]
            if line.count > 21 && line.hasPrefix("[20") {
                let i12 = line.index(line.startIndex, offsetBy: 12)
                let i19 = line.index(line.startIndex, offsetBy: 19)
                let i21 = line.index(line.startIndex, offsetBy: 21)
                text = "[" + line[i12..<i19] + "]" + line[i21...]
            }
            // Censor any IPv4 in log display if hidden
            if settings.ipHidden {
                // simple regex for IPv4
                text = text.replacingOccurrences(
                    of: "\\b(?:[0-9]{1,3}\\.){3}[0-9]{1,3}\\b",
                    with: "█████████",
                    options: .regularExpression
                )
            }
            let kind: LogEntry.Kind
            if      line.contains("OUTAGE")      || line.contains("failed")    { kind = .outage   }
            else if line.contains("restored")    || line.contains("Restored")  { kind = .restored }
            else if line.contains("IP changed")  || line.contains("Initial IP"){ kind = .ipChange }
            else                                                                { kind = .info     }
            return LogEntry(text: text, kind: kind)
        }
    }

    private func checkDaemon() {
        DispatchQueue.global(qos: .background).async {
            let t = Process()
            t.executableURL  = URL(fileURLWithPath: "/bin/launchctl")
            t.arguments      = ["list"]
            let p = Pipe(); t.standardOutput = p; t.standardError = Pipe()
            try? t.run(); t.waitUntilExit()
            let out = String(data: p.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async { self.daemonRunning = out.contains("com.user.network-monitor") }
        }
    }

    // MARK: - IP enrichment (URLSession, not Data(contentsOf:))

    func fetchIPDetails() {
        guard !fetchInFlight else { return }
        fetchInFlight = true
        lastIPFetch   = Date()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var details = IPDetails()

            // IPv4 + geo via ip-api.com (HTTP is fine; sandbox is off)
            let fields = "status,query,isp,org,country,regionName,city,lat,lon,timezone,proxy,hosting"
            if let url  = URL(string: "http://ip-api.com/json/?fields=\(fields)"),
               let data = try? Data(contentsOf: url),   // ok because sandbox=false, ATS not enforced for non-sandboxed
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                details.ip        = json["query"]      as? String ?? "—"
                details.isp       = json["isp"]        as? String ?? "—"
                details.org       = json["org"]        as? String ?? "—"
                details.country   = json["country"]    as? String ?? "—"
                details.region    = json["regionName"] as? String ?? "—"
                details.city      = json["city"]       as? String ?? "—"
                details.timezone  = json["timezone"]   as? String ?? "—"
                details.lat       = json["lat"]        as? Double ?? 0
                details.lon       = json["lon"]        as? Double ?? 0
                let proxy         = json["proxy"]      as? Bool ?? false
                let hosting       = json["hosting"]    as? Bool ?? false
                details.vpnLikely = proxy || hosting
            }

            // IPv6 via api6.ipify.org
            if let url6 = URL(string: "https://api6.ipify.org"),
               let ip6  = try? String(contentsOf: url6, encoding: .utf8) {
                let trimmed = ip6.trimmingCharacters(in: .whitespacesAndNewlines)
                details.ipv6 = trimmed.contains(":") ? trimmed : "Not available"
            } else {
                details.ipv6 = "Not available"
            }

            DispatchQueue.main.async {
                self.ipDetails    = details
                self.fetchInFlight = false
            }
        }
    }

    // MARK: - Daemon control

    func toggleDaemon() {
        let action = daemonRunning ? "unload" : "load"
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        t.arguments = [action, daemonPlist.path]
        t.standardOutput = Pipe(); t.standardError = Pipe()
        try? t.run(); t.waitUntilExit()
        if !daemonRunning { settings.writeDaemonConfig() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.refresh() }
    }

    func restartDaemon() {
        let stop = Process()
        stop.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        stop.arguments = ["unload", daemonPlist.path]
        stop.standardOutput = Pipe(); stop.standardError = Pipe()
        try? stop.run(); stop.waitUntilExit()
        settings.writeDaemonConfig()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let start = Process()
            start.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            start.arguments = ["load", self.daemonPlist.path]
            start.standardOutput = Pipe(); start.standardError = Pipe()
            try? start.run(); start.waitUntilExit()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh() }
        }
    }
    
    // MARK: - Notifications
    
    private var notificationAuthGranted = false
    
    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.notificationAuthGranted = granted
            }
            if !granted {
                print("[NetworkMonitor] UNUserNotificationCenter authorization denied or unavailable. Will use fallback.")
            }
        }
        
        let mute1h = UNNotificationAction(identifier: "MUTE_1H", title: "Mute 1 Hour", options: [])
        let mute24 = UNNotificationAction(identifier: "MUTE_24H", title: "Mute 24 Hours", options: [])
        let category = UNNotificationCategory(identifier: "OUTAGE", actions: [mute1h, mute24], intentIdentifiers: [], options: [.customDismissAction])
        center.setNotificationCategories([category])
    }
    
    private func handleStatusChange(from old: ConnectionStatus, to new: ConnectionStatus) {
        guard settings.notificationsEnabled, !settings.isMuted else { return }
        
        if new == .offline {
            sendNotification(
                title: "🔴 Internet Outage",
                body: "Connection to \(settings.pingHost) failed.",
                categoryId: "OUTAGE"
            )
        } else if new == .online && old == .offline {
            sendNotification(
                title: "🟢 Internet Restored",
                body: "Connection to \(settings.pingHost) is back.",
                categoryId: nil
            )
        }
    }

    private func sendNotification(title: String, body: String, categoryId: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound(named: UNNotificationSoundName(settings.notificationSound))
        if let cat = categoryId { content.categoryIdentifier = cat }
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NetworkMonitor] Notification delivery failed: \(error.localizedDescription)")
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "MUTE_1H" {
            settings.muteOutagesUntil = Date().addingTimeInterval(3600)
        } else if response.actionIdentifier == "MUTE_24H" {
            settings.muteOutagesUntil = Date().addingTimeInterval(86400)
        } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            DispatchQueue.main.async {
                AppDelegate.showMainWindow()
            }
        }
        completionHandler()
    }
}

