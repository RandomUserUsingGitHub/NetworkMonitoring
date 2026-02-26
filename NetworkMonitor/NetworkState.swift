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
    @Published var lastUpdateTime: Date?         = nil
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
    private var lastDaemonCheck: Date = .distantPast
    private var lastLogModDate: Date = .distantPast

    // Tracking logic to fire notifications on state transition differences
    private var previousStatus: ConnectionStatus? = nil
    private var previousIP: String = ""
    
    private var notificationsSetup = false

    override init() {
        super.init()
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        if !notificationsSetup {
            setupNotifications()
            notificationsSetup = true
        }
        guard timer == nil else { return }
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

    private var lastStatusModDate: Date = .distantPast

    private func readStatus() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: statusFile.path),
              let modDate = attrs[.modificationDate] as? Date else { return }
        if modDate == lastStatusModDate { return }
        lastStatusModDate = modDate
        
        guard let raw = try? String(contentsOf: statusFile, encoding: .utf8) else { status = .starting; return }
        let newStatus = ConnectionStatus(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .starting
        
        if previousStatus != nil && previousStatus != newStatus {
            handleStatusChange(from: previousStatus!, to: newStatus)
        }
        previousStatus = newStatus
        status = newStatus
    }

    private var lastHistFileModDate: Date = .distantPast

    private func readPingHistory() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: histFile.path),
              let modDate = attrs[.modificationDate] as? Date else { return }
              
        let sDate = (try? FileManager.default.attributesOfItem(atPath: statusFile.path)[.modificationDate] as? Date) ?? .distantPast
        lastUpdateTime = max(modDate, sDate)
        
        if modDate == lastHistFileModDate && !pingHistory.isEmpty { return }
        lastHistFileModDate = modDate
        
        guard let raw = try? String(contentsOf: histFile, encoding: .utf8) else { pingHistory = []; latestPing = nil; return }
        let lines = raw.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let tail  = Array(lines.suffix(settings.graphWidth))
        pingHistory = tail.map {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t == "T" ? nil : Double(t)
        }
        latestPing = pingHistory.last.flatMap { $0 }
    }

    private var lastIPStateModDate: Date = .distantPast
    
    private func readIPState() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: ipFile.path),
              let modDate = attrs[.modificationDate] as? Date else { return }
        if modDate == lastIPStateModDate { return }
        lastIPStateModDate = modDate
        
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
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFile.path),
              let modDate = attrs[.modificationDate] as? Date else { return }
        if modDate == lastLogModDate && !logEntries.isEmpty { return }
        lastLogModDate = modDate

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
            // IP censorship has been moved to the View layer (EventRow) so it can dynamically update without locking to file read times.
            let kind: LogEntry.Kind
            if      line.contains("OUTAGE")      || line.contains("failed")    { kind = .outage   }
            else if line.contains("restored")    || line.contains("Restored")  { kind = .restored }
            else if line.contains("IP changed")  || line.contains("Initial IP"){ kind = .ipChange }
            else                                                                { kind = .info     }
            return LogEntry(text: text, kind: kind)
        }
    }

    private func checkDaemon() {
        let now = Date()
        if now.timeIntervalSince(lastDaemonCheck) < 5.0 { return }
        lastDaemonCheck = now
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var isRunning = false
            if let pidStr = try? String(contentsOf: URL(fileURLWithPath: "/tmp/.netmon_pid"), encoding: .utf8),
               let pid = pid_t(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                if kill(pid, 0) == 0 {
                    isRunning = true
                }
            }
            
            DispatchQueue.main.async {
                self.daemonRunning = isRunning
            }
        }
    }

    // MARK: - IP enrichment (URLSession, not Data(contentsOf:))

    func fetchIPDetails() {
        guard !fetchInFlight else { return }
        fetchInFlight = true
        lastIPFetch   = Date()
        
        // Retain existing IP metadata to prevent blanking out when ip-api rate-limits or fails
        let currentDetails = self.ipDetails

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var details = currentDetails

            // IPv4 + geo via ip-api.com (HTTP is fine; sandbox is off)
            let fields = "status,query,isp,org,country,regionName,city,lat,lon,timezone,proxy,hosting"
            if let url  = URL(string: "http://ip-api.com/json/?fields=\(fields)"),
               let data = try? Data(contentsOf: url),   // ok because sandbox=false, ATS not enforced for non-sandboxed
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String, status == "success" {
                details.ip        = json["query"]      as? String ?? details.ip
                details.isp       = json["isp"]        as? String ?? details.isp
                details.org       = json["org"]        as? String ?? details.org
                details.country   = json["country"]    as? String ?? details.country
                details.region    = json["regionName"] as? String ?? details.region
                details.city      = json["city"]       as? String ?? details.city
                details.timezone  = json["timezone"]   as? String ?? details.timezone
                details.lat       = json["lat"]        as? Double ?? details.lat
                details.lon       = json["lon"]        as? Double ?? details.lon
                let proxy         = json["proxy"]      as? Bool ?? false
                let hosting       = json["hosting"]    as? Bool ?? false
                details.vpnLikely = proxy || hosting
            }

            // IPv6 via api6.ipify.org
            if let url6 = URL(string: "https://api6.ipify.org"),
               let ip6  = try? String(contentsOf: url6, encoding: .utf8) {
                let trimmed = ip6.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.contains(":") { details.ipv6 = trimmed }
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
        
        // Optimistically update UI
        self.daemonRunning = (action == "load")
        if action == "load" { self.status = .starting }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if action == "unload" {
                try? FileManager.default.removeItem(atPath: "/tmp/.netmon_pid")
            }
            let t = Process()
            t.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            t.arguments = [action, self.daemonPlist.path]
            t.standardOutput = Pipe(); t.standardError = Pipe()
            try? t.run(); t.waitUntilExit()
            
            if action == "unload" { self.settings.writeDaemonConfig() }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.refresh()
            }
        }
    }

    func restartDaemon() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            try? FileManager.default.removeItem(atPath: "/tmp/.netmon_pid")
            let stop = Process()
            stop.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            stop.arguments = ["unload", self.daemonPlist.path]
            stop.standardOutput = Pipe(); stop.standardError = Pipe()
            try? stop.run(); stop.waitUntilExit()
            self.settings.writeDaemonConfig()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let start = Process()
                start.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                start.arguments = ["load", self.daemonPlist.path]
                start.standardOutput = Pipe(); start.standardError = Pipe()
                try? start.run(); start.waitUntilExit()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh() }
            }
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
                NotificationCenter.default.post(name: Notification.Name("ReopenMainWindow"), object: nil)
            }
        }
        completionHandler()
    }
}

// MARK: - Models

struct SettingsConfig: Codable {
    struct PingConfig: Codable {
        var host: String = "8.8.8.8"
        var interval_seconds: Double = 2.0
        var fail_threshold: Int = 3
        var timeout_seconds: Double = 2.0
        var packet_size: Int = 56
        var history_size: Int = 60
    }
    struct IPCheckConfig: Codable {
        var interval_seconds: Double = 10.0
    }
    struct NotificationsConfig: Codable {
        var enabled: Bool = true
        var sound: String = "Basso"
        var censor_on_change: Bool = false
    }
    struct LogConfig: Codable {
        var path: String? = nil
        var tail_lines: Int = 7
    }
    
    var ping: PingConfig = PingConfig()
    var ip_check: IPCheckConfig = IPCheckConfig()
    var notifications: NotificationsConfig = NotificationsConfig()
    var log: LogConfig = LogConfig()
}

// MARK: - Daemon

final class Daemon {
    let histFile = URL(fileURLWithPath: "/tmp/.netmon_ping_history")
    let ipStateFile = URL(fileURLWithPath: "/tmp/.netmon_ip_state")
    let statusFile = URL(fileURLWithPath: "/tmp/.netmon_status")
    let pidFile = URL(fileURLWithPath: "/tmp/.netmon_pid")
    
    // Notification center access for background alerts
    let center = UNUserNotificationCenter.current()
    
    var logPath: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".network_monitor.log")
    }
    var cfgPath: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/network-monitor/settings.json")
    }
    
    var config = SettingsConfig()
    var cfgMtime: Date = .distantPast
    
    var failCount = 0
    var outageActive = false
    var lastIP = ""
    var lastIPCheck = Date.distantPast
    
    lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5.0
        return URLSession(configuration: config)
    }()

    func run() {
        createAppDirectories()
        setupInitialFiles()
        
        log("=== Network Monitor Daemon (Swift) Started ===")
        try? String(describing: getpid()).write(to: pidFile, atomically: true, encoding: .utf8)
        
        // Ensure notifications are registered
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let mute1h = UNNotificationAction(identifier: "MUTE_1H", title: "Mute 1 Hour", options: [])
        let mute24 = UNNotificationAction(identifier: "MUTE_24H", title: "Mute 24 Hours", options: [])
        let category = UNNotificationCategory(identifier: "OUTAGE", actions: [mute1h, mute24], intentIdentifiers: [], options: [.customDismissAction])
        center.setNotificationCategories([category])
        
        while true {
            let start = Date()
            
            checkConfigUpdate()
            performPing()
            performIPCheckIfNeeded()
            
            // Sleep for the remainder of the interval
            let elapsed = Date().timeIntervalSince(start)
            let sleepTime = max(0.1, config.ping.interval_seconds - elapsed)
            Thread.sleep(forTimeInterval: sleepTime)
        }
    }
    
    // MARK: File I/O
    
    func createAppDirectories() {
        let logDir = logPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    }
    
    func setupInitialFiles() {
        if !FileManager.default.fileExists(atPath: histFile.path) {
            try? "".write(to: histFile, atomically: true, encoding: .utf8)
        }
        try? "fetching||".write(to: ipStateFile, atomically: true, encoding: .utf8)
        try? "STARTING".write(to: statusFile, atomically: true, encoding: .utf8)
    }
    
    func log(_ msg: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(msg)\n"
        
        if let handle = try? FileHandle(forWritingTo: logPath) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(to: logPath, atomically: true, encoding: .utf8)
        }
    }
    
    // MARK: Config
    
    func checkConfigUpdate() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cfgPath.path),
              let mtime = attrs[.modificationDate] as? Date,
              mtime != cfgMtime else { return }
        
        cfgMtime = mtime
        if let data = try? Data(contentsOf: cfgPath),
           let newConfig = try? JSONDecoder().decode(SettingsConfig.self, from: data) {
            self.config = newConfig
            log("Config reloaded (threshold:\(config.ping.fail_threshold) timeout:\(config.ping.timeout_seconds)s pktsize:\(config.ping.packet_size)b host:\(config.ping.host))")
        }
    }
    
    // MARK: Ping Logic
    
    func performPing() {
        let timeoutMs = max(1, Int(config.ping.timeout_seconds * 1000.0))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-W", "\(timeoutMs)", "-s", "\(config.ping.packet_size)", config.ping.host]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if process.terminationStatus == 0, let out = String(data: data, encoding: .utf8) {
                // Success
                var msValue = "1.0"
                for line in out.components(separatedBy: .newlines) {
                    if line.contains("round-trip") || line.contains("rtt") {
                        let parts = line.components(separatedBy: "/")
                        if parts.count > 4, let val = Double(parts[4]) {
                            msValue = String(format: "%.1f", val)
                        }
                    }
                }
                
                appendPing(msValue)
                try? "ONLINE".write(to: statusFile, atomically: true, encoding: .utf8)
                
                if outageActive {
                    log("Connection restored after \(failCount) failures.")
                    sendNotification(title: "🟢 Internet Restored", body: "Connection to \(config.ping.host) is back.", categoryId: nil)
                    outageActive = false
                }
                failCount = 0
            } else {
                handlePingFailure()
            }
        } catch {
            handlePingFailure()
        }
    }
    
    func handlePingFailure() {
        appendPing("T")
        failCount += 1
        log("Ping failed (\(failCount)/\(config.ping.fail_threshold))")
        
        if failCount >= config.ping.fail_threshold && !outageActive {
            log("OUTAGE detected after \(failCount) consecutive failures.")
            sendNotification(title: "🔴 Internet Outage", body: "Connection to \(config.ping.host) failed.", categoryId: "OUTAGE")
            outageActive = true
            try? "OFFLINE".write(to: statusFile, atomically: true, encoding: .utf8)
        }
    }
    
    func appendPing(_ val: String) {
        if let handle = try? FileHandle(forWritingTo: histFile) {
            handle.seekToEndOfFile()
            handle.write((val + "\n").data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? (val + "\n").write(to: histFile, atomically: true, encoding: .utf8)
        }
        
        // Truncate history file
        if let raw = try? String(contentsOf: histFile, encoding: .utf8) {
            var lines = raw.components(separatedBy: .newlines)
            if lines.last == "" { lines.removeLast() }
            if lines.count > config.ping.history_size {
                let tail = lines.suffix(config.ping.history_size)
                try? (tail.joined(separator: "\n") + "\n").write(to: histFile, atomically: true, encoding: .utf8)
            }
        }
    }
    
    // MARK: IP Check
    
    struct IPAPIResponse: Codable {
        let status: String
        let country: String?
        let city: String?
    }
    struct IPInfoResponse: Codable {
        let country: String?
        let city: String?
    }
    
    func performIPCheckIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastIPCheck) >= config.ip_check.interval_seconds else { return }
        lastIPCheck = now
        
        // Perform sync network requests to avoid messy dispatch groups
        let semaphore = DispatchSemaphore(value: 0)
        var currentIP = ""
        
        let urls = ["https://api.ipify.org", "https://ifconfig.me/ip", "https://checkip.amazonaws.com"]
        
        func tryFetchIP(index: Int) {
            guard index < urls.count else {
                semaphore.signal()
                return
            }
            let task = session.dataTask(with: URL(string: urls[index])!) { data, response, error in
                if let data = data, let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !ip.isEmpty {
                    currentIP = ip
                    semaphore.signal()
                } else {
                    tryFetchIP(index: index + 1)
                }
            }
            task.resume()
        }
        
        tryFetchIP(index: 0)
        _ = semaphore.wait(timeout: .now() + 6.0)
        
        if !currentIP.isEmpty && currentIP != lastIP {
            var country = "Unknown"
            var city = "Unknown"
            
            let geoSemaphore = DispatchSemaphore(value: 0)
            let geoTask = session.dataTask(with: URL(string: "http://ip-api.com/json/\(currentIP)?fields=status,country,city")!) { data, _, _ in
                if let data = data, let obj = try? JSONDecoder().decode(IPAPIResponse.self, from: data), obj.status == "success" {
                    country = obj.country ?? "Unknown"
                    city = obj.city ?? "Unknown"
                }
                geoSemaphore.signal()
            }
            geoTask.resume()
            _ = geoSemaphore.wait(timeout: .now() + 6.0)
            
            if country == "Unknown" { // Fallback
                let gbSemaphore = DispatchSemaphore(value: 0)
                let fallbackTask = session.dataTask(with: URL(string: "https://ipinfo.io/\(currentIP)/json")!) { data, _, _ in
                    if let data = data, let obj = try? JSONDecoder().decode(IPInfoResponse.self, from: data) {
                        country = obj.country ?? "Unknown"
                        city = obj.city ?? "Unknown"
                    }
                    gbSemaphore.signal()
                }
                fallbackTask.resume()
                _ = gbSemaphore.wait(timeout: .now() + 6.0)
            }
            
            let displayIP = config.notifications.censor_on_change ? censor(ip: currentIP) : currentIP
            
            if !lastIP.isEmpty {
                let displayOld = config.notifications.censor_on_change ? censor(ip: lastIP) : lastIP
                log("IP changed: \(displayOld) -> \(displayIP) (\(city), \(country))")
                sendNotification(title: "🌐 Public IP Changed", body: "New IP: \(displayIP)\n\(city), \(country)", categoryId: nil)
            } else {
                log("Initial IP: \(displayIP) (\(city), \(country))")
            }
            
            lastIP = currentIP
            try? "\(currentIP)|\(country)|\(city)".write(to: ipStateFile, atomically: true, encoding: .utf8)
        }
    }
    
    func sendNotification(title: String, body: String, categoryId: String?) {
        guard config.notifications.enabled else { return }
        
        // Check for active UI snooze via UserDefaults cross-talk
        if let ud = UserDefaults(suiteName: "com.armin.network-monitor"),
           let muteUntil = ud.object(forKey: "netmon.muteOutagesUntil") as? Date,
           muteUntil > Date(), categoryId == "OUTAGE" {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound(named: UNNotificationSoundName(config.notifications.sound))
        if let cat = categoryId { content.categoryIdentifier = cat }
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error = error {
                print("[NetworkMonitor Daemon] Notification failed: \(error.localizedDescription)")
            }
        }
    }
    
    func censor(ip: String) -> String {
        let parts = ip.components(separatedBy: ".")
        if parts.count == 4 {
            return parts[0] + ".*.*.*"
        }
        return ip
    }
}
