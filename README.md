# 🌐 Network Monitor

> **Made by Armin Hashemi** — lightweight macOS network monitoring app built with SwiftUI.

[![macOS](https://img.shields.io/badge/macOS-13%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## Features

- **Live ping graph** — real-time latency visualisation with colour-coded status
- **Public IP & location tracking** — detects IP changes with city/country lookup
- **Outage detection** — notifications when connectivity drops or restores
- **Eye icon** — hide/reveal your public IP at any time
- **IP censoring** — optionally censor IP in notifications when a change is detected
- **In-app settings** — configure everything without touching config files
- **Themes** — green, amber, blue, red
- **Customisable subtitle** — change "by Armin Hashemi" to anything you like (I'll allow it :D)
- **Login item control** — toggle start-at-login from inside the app
- **Configurable ping** — host, interval, timeout, packet size, fail threshold

---

## Screenshots

_Coming soon_

---

## Installation

### Homebrew (recommended)

```bash
brew tap RandomUserUsingGitHub/homebrew-tap
brew install --cask network-monitor
```

### Manual — Download from Releases

1. Go to [Releases](../../releases) and download the latest `NetworkMonitor-release.zip`
2. Unzip it
3. Drag `NetworkMonitor.app` → `/Applications`
4. Open Terminal and run:

```bash
bash install.sh
```

> If macOS says "unidentified developer": right-click the app → **Open** → **Open Anyway** (one time only)

### For developers — Build from source

**Requirements:** macOS 13+, Xcode 15+

```bash
git clone https://github.com/RandomUserUsingGitHub/NetworkMonitoring.git
cd NetworkMonitoring
open NetworkMonitor.xcodeproj
# Press ⌘R to build and run
```

Or build from the command line:

```bash
bash build_and_distribute.sh
```

---

## How it works

The app has two parts:

| Component | Description |
|-----------|-------------|
| `NetworkMonitor.app` | SwiftUI GUI — reads state files, shows live data |
| `NetworkMonitor --daemon` | Native Swift daemon — runs in background, handles ping, IP tracking, and notifications natively |

The daemon writes state to `/tmp/.netmon_*` files every few seconds. The app reads them on a 1-second timer without spawning sub-processes. Settings are stored in `UserDefaults` and synced to `~/.config/network-monitor/settings.json` for the daemon.

---

## Settings

All settings are configurable in-app via the ⚙️ gear icon:

| Setting | Default | Description |
|---------|---------|-------------|
| Ping host | 8.8.8.8 | Target to ping |
| Ping interval | 2s | How often to ping |
| Ping timeout | 2s | Per-packet timeout |
| Packet size | 56 bytes | ICMP packet size |
| Fail threshold | 3 | Failures before outage alert |
| IP check interval | 10s | How often to check public IP |
| Censor IP in notifications | off | Show only first octet in alerts |
| Theme | green | green / amber / blue / red |
| Launch at login | on | Start daemon automatically |
| Subtitle text | "by Armin Hashemi" | Custom tagline |

---

## Uninstall

```bash
bash install.sh --uninstall
```

---

## Publishing a release (maintainer notes)

1. Build: `bash build_and_distribute.sh`
2. This creates `NetworkMonitor-release.zip`
3. On GitHub: **Releases → Draft a new release**
4. Tag: `v1.0.0`, upload `NetworkMonitor-release.zip`
5. Source code is automatically included by GitHub

---

## License

MIT — see [LICENSE](LICENSE)
