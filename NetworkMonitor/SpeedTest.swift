import Foundation
import SwiftUI

struct SpeedServer: Identifiable, Hashable {
    let id       = UUID()
    let name:    String
    let url:     String
    let location: String
}

extension SpeedServer {
    static let presets: [SpeedServer] = [
        SpeedServer(name:"Cloudflare",         url:"https://speed.cloudflare.com/__down?bytes=25000000", location:"Global CDN"),
        SpeedServer(name:"US — New York",      url:"https://nyc.download.datapacket.com/100mb.bin",     location:"New York, USA"),
        SpeedServer(name:"EU — Frankfurt",     url:"https://fra.download.datapacket.com/100mb.bin",     location:"Frankfurt, DE"),
        SpeedServer(name:"EU — London",        url:"https://lon.download.datapacket.com/100mb.bin",     location:"London, UK"),
        SpeedServer(name:"AS — Singapore",     url:"https://sin.download.datapacket.com/100mb.bin",     location:"Singapore"),
        SpeedServer(name:"AS — Tokyo",         url:"https://tyo.download.datapacket.com/100mb.bin",     location:"Tokyo, JP"),
        SpeedServer(name:"AU — Sydney",        url:"https://syd.download.datapacket.com/100mb.bin",     location:"Sydney, AU"),
    ]
}

struct SpeedSample: Identifiable {
    let id   = UUID()
    let time: Date
    let mbps: Double
    let phase: SamplePhase

    enum SamplePhase { case download, upload }
}

enum SpeedTestPhase {
    case idle, ping, download, upload, done, failed(String)

    var isRunning: Bool {
        switch self { case .idle, .done, .failed: return false; default: return true }
    }

    var label: String {
        switch self {
        case .idle:          return "Ready"
        case .ping:          return "Measuring ping…"
        case .download:      return "Downloading…"
        case .upload:        return "Measuring upload…"
        case .done:          return "Complete ✓"
        case .failed(let m): return "Failed: \(m)"
        }
    }
}

struct SpeedResult: Identifiable {
    let id           = UUID()
    let date:        Date
    let server:      String
    let pingMs:      Double
    let jitterMs:    Double
    let downloadMbps: Double
    let uploadMbps:  Double
}

@MainActor
final class SpeedTestModel: ObservableObject {
    @Published var phase:        SpeedTestPhase = .idle
    @Published var pingMs:       Double?         = nil
    @Published var jitterMs:     Double?         = nil
    @Published var downloadMbps: Double?         = nil
    @Published var uploadMbps:   Double?         = nil
    @Published var progress:     Double          = 0
    @Published var liveSpeed:    Double          = 0
    @Published var samples:      [SpeedSample]   = []
    @Published var selectedServer: SpeedServer   = SpeedServer.presets[0]
    @Published var history:      [SpeedResult]   = []

    private var runTask: Task<Void, Never>?
    private var dlSession: URLSession?
    private var skipRequested = false

    func run() {
        guard !phase.isRunning else { return }
        samples = []; pingMs = nil; jitterMs = nil; downloadMbps = nil; uploadMbps = nil
        progress = 0; liveSpeed = 0; skipRequested = false
        runTask = Task { await runTest() }
    }

    func cancel() {
        runTask?.cancel()
        dlSession?.invalidateAndCancel()
        dlSession = nil
        skipRequested = false
        phase = .idle; progress = 0; liveSpeed = 0
    }

    /// Skip the current download or upload phase
    func skip() {
        skipRequested = true
        dlSession?.invalidateAndCancel()
        dlSession = nil
    }

    func deleteHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
    }

    func deleteHistoryItem(_ item: SpeedResult) {
        history.removeAll { $0.id == item.id }
    }

    // MARK: - Test sequence

    private func runTest() async {
        // ── Ping phase (5 samples for jitter) ──
        phase = .ping
        let host = URL(string: selectedServer.url)?.host ?? "8.8.8.8"
        var pings: [Double] = []
        for _ in 0..<5 {
            if Task.isCancelled { phase = .idle; return }
            let p = await measureSinglePing(host: host)
            if p > 0 { pings.append(p) }
        }

        if pings.isEmpty {
            phase = .failed("Ping failed — check connection.")
            return
        }
        let avgPing = pings.reduce(0, +) / Double(pings.count)
        pingMs = avgPing

        // Jitter = mean absolute difference between consecutive pings
        if pings.count > 1 {
            let diffs = zip(pings, pings.dropFirst()).map { abs($0 - $1) }
            jitterMs = diffs.reduce(0, +) / Double(diffs.count)
        } else {
            jitterMs = 0
        }
        progress = 0.1

        if Task.isCancelled { phase = .idle; return }

        // ── Download phase (with retry) ──
        phase = .download
        skipRequested = false
        var dl = await measureDownload(urlStr: selectedServer.url)

        if skipRequested {
            // User skipped download - use whatever we got so far
            skipRequested = false
            if let partialDl = dl {
                downloadMbps = partialDl
            } else {
                downloadMbps = liveSpeed > 0 ? liveSpeed : nil
            }
        } else if dl == nil && !Task.isCancelled {
            // Retry once after a short wait
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { phase = .idle; return }
            dl = await measureDownload(urlStr: selectedServer.url)
            if let dlResult = dl {
                downloadMbps = dlResult
            } else {
                phase = .failed("Download failed — check connection or try another server.")
                return
            }
        } else if let dlResult = dl {
            downloadMbps = dlResult
        } else {
            if Task.isCancelled { phase = .idle; return }
            phase = .failed("Download failed — check connection or try another server.")
            return
        }
        progress = 0.8

        if Task.isCancelled { phase = .idle; return }

        // ── Upload phase ──
        phase = .upload
        skipRequested = false
        let ulResult = await measureUpload()

        if skipRequested {
            // User skipped upload - use whatever partial data
            skipRequested = false
            uploadMbps = ulResult > 0 ? ulResult : 0
        } else {
            uploadMbps = ulResult
        }
        progress = 1.0

        if Task.isCancelled { phase = .idle; return }

        // ── Record result ──
        let result = SpeedResult(
            date: Date(), server: selectedServer.name,
            pingMs: pingMs ?? 0, jitterMs: jitterMs ?? 0,
            downloadMbps: downloadMbps ?? 0, uploadMbps: uploadMbps ?? 0
        )
        history.insert(result, at: 0)
        if history.count > 20 { history = Array(history.prefix(20)) }
        objectWillChange.send()

        phase = .done
    }

    // MARK: - Measurements

    private func measureSinglePing(host: String) async -> Double {
        guard let url = URL(string: "https://\(host)/") else { return 0 }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.httpMethod = "HEAD"
        let start = Date()
        _ = try? await URLSession.shared.data(for: req)
        return Date().timeIntervalSince(start) * 1000
    }

    private func measureDownload(urlStr: String) async -> Double? {
        guard let url = URL(string: urlStr) else { return nil }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config)
        dlSession = session

        let startTime = Date()
        var totalBytes: Int64 = 0
        var lastUpdate = startTime

        do {
            let (asyncBytes, response) = try await session.bytes(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

            for try await _ in asyncBytes {
                if Task.isCancelled || skipRequested { break }
                totalBytes += 1
                let now     = Date()
                let elapsed = now.timeIntervalSince(startTime)
                if now.timeIntervalSince(lastUpdate) >= 0.25 {
                    let mbps = elapsed > 0 ? Double(totalBytes) * 8 / (elapsed * 1_000_000) : 0
                    self.liveSpeed = mbps
                    self.samples.append(SpeedSample(time: now, mbps: mbps, phase: .download))
                    self.progress  = min(0.1 + (elapsed / 20.0) * 0.65, 0.75)
                    lastUpdate = now
                    if totalBytes > 25_000_000 || elapsed > 20 { break }
                }
            }
        } catch {
            if Task.isCancelled { return nil }
            // If skip was requested, the session was invalidated, which throws — still return partial
            if skipRequested {
                let elapsed = Date().timeIntervalSince(startTime)
                guard elapsed > 0.1, totalBytes > 0 else { return nil }
                return Double(totalBytes) * 8 / (elapsed * 1_000_000)
            }
            return nil
        }

        let elapsed = Date().timeIntervalSince(startTime)
        guard elapsed > 0.1, totalBytes > 0 else { return nil }
        return Double(totalBytes) * 8 / (elapsed * 1_000_000)
    }

    private func measureUpload() async -> Double {
        guard let url = URL(string: "https://httpbin.org/post") else { return 0 }
        var req  = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        let payload = Data(repeating: 0x55, count: 2_000_000)
        req.httpBody = payload
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let start = Date()

        // Simulate upload progress with samples
        let progressTask = Task {
            var elapsed = 0.0
            while !Task.isCancelled && !skipRequested {
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                elapsed = Date().timeIntervalSince(start)
                let estimatedMbps = elapsed > 0 ? Double(payload.count) * 8 / (max(elapsed, 1) * 1_000_000) : 0
                await MainActor.run {
                    self.liveSpeed = estimatedMbps
                    self.samples.append(SpeedSample(time: Date(), mbps: estimatedMbps, phase: .upload))
                    self.progress = min(0.8 + (elapsed / 20.0) * 0.2, 0.99)
                }
                if elapsed > 20 { break }
            }
        }

        _ = try? await URLSession.shared.data(for: req)
        progressTask.cancel()

        if Task.isCancelled || skipRequested { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        let mbps = elapsed > 0 ? Double(payload.count) * 8 / (elapsed * 1_000_000) : 0

        // Add final upload sample
        self.liveSpeed = mbps
        self.samples.append(SpeedSample(time: Date(), mbps: mbps, phase: .upload))

        return mbps
    }
}
