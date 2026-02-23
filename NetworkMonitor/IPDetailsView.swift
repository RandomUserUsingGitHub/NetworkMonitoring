import SwiftUI
import Darwin  // for getifaddrs, AF_INET, inet_ntop

struct IPDetailsView: View {
    @ObservedObject var model: NetworkStateModel
    @ObservedObject private var settings = Settings.shared
    @State private var webRTCResult  = "Not tested yet"
    @State private var webRTCTesting = false

    var t: AppTheme  { model.theme }
    var d: IPDetails { model.ipDetails }

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    pageHeader
                    addressSection
                    locationSection
                    networkSection
                    privacySection
                    webRTCSection
                }
                .padding(18)
            }
        }
    }

    // MARK: - Header

    private var pageHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("IP & LOCATION")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(t.accent2)
                Text("ip-api.com + ipify.org")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(t.dim)
            }
            Spacer()
            Button(action: { model.fetchIPDetails() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(t.accent)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(t.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(t.accent.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sections

    private var addressSection: some View {
        DetailSection(title: "ADDRESSES", theme: t) {
            DetailRow(label: "IPv4",
                      value: settings.ipHidden ? "█████████" : d.ip,
                      color: t.warn, theme: t, mono: true)
            DetailRow(label: "IPv6",
                      value: settings.ipHidden ? "█████████" : d.ipv6,
                      color: t.accent, theme: t, mono: true)
        }
    }

    private var locationSection: some View {
        DetailSection(title: "LOCATION", theme: t) {
            DetailRow(label: "City",      value: d.city,     color: t.text, theme: t)
            DetailRow(label: "Region",    value: d.region,   color: t.text, theme: t)
            DetailRow(label: "Country",   value: d.country,  color: t.text, theme: t)
            DetailRow(label: "Timezone",  value: d.timezone, color: t.dim,  theme: t, mono: true)
            DetailRow(label: "Latitude",  value: d.lat != 0 ? String(format: "%.4f", d.lat) : "—",
                      color: t.dim, theme: t, mono: true)
            DetailRow(label: "Longitude", value: d.lon != 0 ? String(format: "%.4f", d.lon) : "—",
                      color: t.dim, theme: t, mono: true)
        }
    }

    private var networkSection: some View {
        DetailSection(title: "NETWORK", theme: t) {
            DetailRow(label: "ISP",           value: d.isp, color: t.text, theme: t)
            DetailRow(label: "Organisation",  value: d.org, color: t.text, theme: t)
        }
    }

    private var privacySection: some View {
        DetailSection(title: "PRIVACY FLAGS", theme: t) {
            flagRow(label: "VPN / Proxy / Hosting", flagged: d.vpnLikely)
            flagRow(label: "Tor exit node",          flagged: d.tor)
        }
    }

    private func flagRow(label: String, flagged: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(t.text)
                Spacer()
                Text(flagged ? "⚠ Detected" : "✓ Not detected")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(flagged ? t.warn : t.graphOk)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            Divider().overlay(t.border.opacity(0.1)).padding(.horizontal, 14)
        }
    }

    private var webRTCSection: some View {
        DetailSection(title: "WEBRTC LEAK TEST", theme: t) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Local network interfaces")
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(t.text)
                        Text(webRTCResult)
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(t.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(action: runWebRTCTest) {
                        Text(webRTCTesting ? "Testing…" : "Test")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(t.accent)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(t.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .disabled(webRTCTesting)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)

                Divider().overlay(t.border.opacity(0.1)).padding(.horizontal, 14)

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(t.dim).font(.system(size: 11))
                    Text("Shows local IPs discoverable via browser WebRTC APIs. Checks network interfaces directly.")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(t.dim)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
    }

    // MARK: - WebRTC

    private func runWebRTCTest() {
        webRTCTesting = true
        webRTCResult  = "Scanning…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.collectLocalIPs()
            DispatchQueue.main.async {
                self.webRTCResult  = result
                self.webRTCTesting = false
            }
        }
    }

    private static func collectLocalIPs() -> String {
        var ips: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return "Error reading interfaces" }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let sa = cur.pointee.ifa_addr else { continue }
            let family = sa.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }

            var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            if family == UInt8(AF_INET) {
                var s = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                inet_ntop(AF_INET, &s.sin_addr, &buf, socklen_t(INET6_ADDRSTRLEN))
            } else {
                var s = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                inet_ntop(AF_INET6, &s.sin6_addr, &buf, socklen_t(INET6_ADDRSTRLEN))
            }

            let name = String(cString: cur.pointee.ifa_name)
            let ip   = String(cString: buf)
            guard ip != "0.0.0.0", !ip.hasPrefix("fe80"), ip != "::" else { continue }
            ips.append("\(name): \(ip)")
        }
        return ips.isEmpty ? "No leakable IPs found" : ips.joined(separator: "\n")
    }
}

// MARK: - Shared components

struct DetailSection<Content: View>: View {
    let title: String; let theme: AppTheme
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.dim).padding(.bottom, 6)
            VStack(spacing: 0) { content() }
                .background(theme.bg2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(theme.border.opacity(0.25), lineWidth: 1))
        }
    }
}

struct DetailRow: View {
    let label: String; let value: String; let color: Color; let theme: AppTheme
    var mono: Bool = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(theme.text)
                Spacer()
                Text(value.isEmpty || value == "—" ? "—" : value)
                    .font(.system(size: 12, design: mono ? .monospaced : .default))
                    .foregroundStyle(value.isEmpty || value == "—" ? theme.dim : color)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            Divider().overlay(theme.border.opacity(0.1)).padding(.horizontal, 14)
        }
    }
}
