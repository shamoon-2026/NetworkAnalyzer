# Network Analyzer

*[日本語版はこちら](README.ja.md)*

Network Analyzer is a native macOS app that discovers hosts on your local network and shows their hostname, MAC address / NIC vendor, an estimated OS type, and open well-known ports. It never requires administrator privileges or a raw socket — every stage is built on unprivileged system binaries (`arp`, `ndp`, `ping`, `ping6`) and `Network.framework`. Built with SwiftUI and Swift Concurrency.

## Features

- **Non-privileged host discovery**: no sudo, no raw sockets, ever
- **User-specified scan target**: set a Start IP, End IP, and Netmask (IPv4) or Prefix Length (IPv6) to actively sweep exactly the range you want, preset on launch from this Mac's own network configuration (with a one-click reset back to it). A full IPv6 /64 (2^64 addresses) is never something to sweep in one go — the app tells you to narrow the range rather than silently truncating it
- **Separate IPv4 / IPv6 tabs**: each tab has its own scan, results table, and CSV export — the two never share data
- **NIC vendor lookup**: resolves the MAC address's manufacturer from the IEEE OUI registry; a small starter dataset ships in the app, with an "Update Vendor Data" button in Settings to fetch the current official list
- **Hostname resolution**: races a Bonjour service scan, a genuine multicast DNS (mDNS) reverse query, and standard reverse DNS, and shows whichever answers first
- **OS type estimate**: guesses Windows / macOS-Linux / network device from the TTL and open-port pattern, always labeled "(estimated)" with a visible accuracy disclaimer — this is a heuristic, not a fingerprinting exploit
- **Well-known port scan**: checks common TCP/UDP ports with `Network.framework`; UDP only ever reports "responded" or "no response" (never a false "closed", since that would need a raw socket to read)
- **Sortable results table**: click any column header (IP, hostname, MAC, vendor, OS, ports, comment) to sort ascending/descending
- **Per-host comments**: type a free-text note directly into a host's row (e.g. "living room switch") — it's saved automatically and included in CSV export. Comments survive a rescan but are reset when you relaunch the app (by design — nothing is written to disk)
- **CSV export**: save either tab's current results — including your comments — to a CSV file
- **English/Japanese UI**: the app starts in English by default; switch to Japanese anytime from the language picker
- **Scans only when you ask**: nothing happens on launch — press "Scan" to start

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`) are enough to build — the full Xcode app isn't required

## Building

```bash
cd NetworkAnalyzer-macOS
./build-app.sh
```

This produces `dist/Network Analyzer.app` (ad-hoc signed).

For quick iteration during development, you can also just run:

```bash
swift run
```

## Running

```bash
open "dist/Network Analyzer.app"
```

For regular use, copy `dist/Network Analyzer.app` into `/Applications`.

## Usage

1. Pick the "IPv4" or "IPv6" tab
2. The Start IP / End IP / Netmask (or Prefix Length on the IPv6 tab) fields are preset to this Mac's own network on first launch — edit them to target a different range, or click the reset icon to restore the preset. A live "N addresses in range" line under the fields updates as you type, turning red once the range would exceed what a single scan can cover. On IPv6, the preset is the *entire* detected /64, which is always far too large to scan as-is — see "Choosing an appropriate IPv6 scan range" below
3. Click "Scan" to discover hosts on that network
4. Click any column header to sort by that column (click again to reverse)
5. Click into a host's Comment cell to type a note — it's saved as you type
6. Click "Export CSV" to save the current results, comments included
7. Open Settings (gear icon) to fetch the latest vendor data from the IEEE OUI registry

## Choosing an appropriate IPv6 scan range

A full /64 has 2^64 addresses — scanning "the whole subnet" is never something this app (or any tool) can actually do in one pass, unlike IPv4 where the default /24 preset (254 addresses) fits comfortably. Scanning that full preset as-is will always report the range as too large.

IPv6 addresses also aren't handed out sequentially the way IPv4's typically are (no DHCP-style `.1`, `.2`, `.3`, ...), so there's no single range that's "correct" the way there might be for IPv4. In practice, narrow the Start/End IP fields to at most 4,096 addresses that plausibly cover real hosts:

- **Vary only the last group** around an address you already know is live, e.g. `2001:db8:1234:5678::1` through `2001:db8:1234:5678::1000`
- **Target a manually-assigned block**, if your network assigns IPv6 addresses by hand rather than via SLAAC/privacy addresses
- Otherwise, prefer the IPv6 tab's passive discovery (reading the NDP neighbor cache) for a general survey of the network, and use an active range scan only once you have a specific, narrow target in mind

The app shows this guidance directly under the IPv6 tab's range fields, along with a live address count as you type.

## Tests

The core logic (ARP/NDP parsing, vendor CSV parsing, OS guessing, IP sort ordering, CSV escaping, etc.) lives in the `NetworkAnalyzerCore` library target and is covered by XCTest.

```bash
swift test
```

Note: `swift test` requires the **full Xcode app** (it needs `XCTest.framework`) — it won't run with Command Line Tools alone. Building and running the app itself doesn't need full Xcode.

## Project layout

```
NetworkAnalyzer-macOS/
├── Package.swift                  # Swift Package Manager manifest
├── Info.plist                     # App bundle metadata
├── NetworkAnalyzer.entitlements   # com.apple.security.network.client only
├── AppIcon.icns                   # App icon
├── build-app.sh                   # Release build + .app bundle assembly script
├── Sources/
│   ├── CDNSSD/                        # System-library wrapper over <dns_sd.h>
│   ├── NetworkAnalyzerCore/           # Discovery/scan logic (library, unit tested)
│   │   ├── HostDiscovery.swift            # arp -a / ndp -a, or an active range sweep
│   │   ├── ArpTableParser.swift           # Parses `arp -a` (IPv4)
│   │   ├── NdpTableParser.swift           # Parses `ndp -a` (IPv6)
│   │   ├── IPv4Range.swift                # IPv4 range/netmask arithmetic + validation
│   │   ├── IPv6Range.swift                # IPv6 range/prefix-length arithmetic + validation
│   │   ├── LocalNetworkInfoProvider.swift # Reads this Mac's own address/netmask or prefix
│   │   ├── PingProbe.swift                # Runs ping/ping6, extracts TTL/hop-limit
│   │   ├── VendorResolver.swift           # IEEE OUI CSV lookup + update
│   │   ├── HostnameResolver.swift         # Bonjour / mDNS / reverse-DNS race
│   │   ├── BonjourServiceMap.swift        # NWBrowser-based service name map
│   │   ├── MDNSReversePTR.swift           # Forced-multicast DNS PTR query
│   │   ├── OSFingerprint.swift            # TTL + port heuristic OS guess
│   │   ├── PortScanner.swift              # NWConnection-based TCP/UDP scan
│   │   ├── NetworkAnalyzerViewModel.swift # Per-tab scan orchestration
│   │   ├── HostCommentStore.swift         # Per-host comments, in memory only (per tab, per run)
│   │   ├── CSVExport.swift                # CSV serialization
│   │   └── Models.swift                   # Data models (HostViewModel, OSFamily, etc.)
│   └── NetworkAnalyzer/               # App target (UI)
│       ├── NetworkAnalyzerApp.swift       # App entry point
│       ├── ContentView.swift              # UI (IPv4/IPv6 tabs, results table)
│       ├── SettingsView.swift             # Vendor data update
│       └── Localization.swift             # English/Japanese UI strings
└── Tests/NetworkAnalyzerTests/        # XCTest unit tests
```

## Technical notes

- No stage requires sudo or a raw socket: host discovery shells out to the system `arp`/`ndp`/`ping`/`ping6` binaries (the same non-privileged precedent as MultiPingMonitor-macOS), and port scanning/hostname resolution use `Network.framework` and `dns_sd`
- `arp`/`ndp` are always invoked with `-n` (numeric, no hostname resolution): without it, `ndp -a` alone was measured taking 30+ seconds per scan on a real network, since it does its own reverse-DNS lookup per neighbor and blocks on each one lacking a PTR record
- A scan actively pings every address in the specified range (capped at 4096 addresses to bound how many `ping`/`ping6` processes can run at once) and then reads `arp -a`/`ndp -a` once to pick up MAC addresses — only addresses that actually responded are shown, so scanning a mostly-empty range doesn't produce hundreds of blank rows
- The IPv6 tab's preset range is the full detected /64 (~1.8×10^19 addresses) — scanning that as-is always hits the 4096-address cap and shows an error asking you to narrow it, since actively sweeping a whole /64 isn't practical (unlike IPv4's /24-sized default, which fits the cap immediately). See "Choosing an appropriate IPv6 scan range" above
- Comments are kept in memory only, separately per tab, keyed by IP address, and are merged back onto freshly discovered hosts after every scan — they're the one thing about a host that a rescan is expected to remember rather than rediscover. They are intentionally **not** written to disk, so quitting and reopening the app always starts with a clean slate
- The OS type column is always an estimate — it combines the ICMP TTL (rounded up to the nearest common initial value: 64/128/255) with the open-port pattern, and is never presented as a certainty
- Reverse DNS alone (`getnameinfo()`) does **not** reach mDNS for an ordinary LAN subnet on macOS — only `169.254.0.0/16` and IPv6 link-local are auto-routed through mDNSResponder — so hostname resolution also performs a genuine multicast PTR query
- App Sandbox is not enabled (matching this project's ad-hoc, direct-distribution build); only the network-client entitlement is applied at signing time

## License

[GNU General Public License v3.0](LICENSE)
