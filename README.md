# PunchThrough for macOS

A native macOS menu bar application that bypasses DPI (Deep Packet Inspection) restrictions. Works with ISPs that use DPI-based internet filtering.

Built with Swift/SwiftUI. Ships with two bypass engines: [SpoofDPI](https://github.com/xvzc/SpoofDPI) (default, no admin needed) and [Zapret/tpws](https://github.com/bol-van/zapret) (one-time admin install, keeps app updaters working — Discord etc.).

## Features

- One-click connect/disconnect from menu bar
- Two bundled engines: **SpoofDPI** (userspace, zero setup) and **Zapret/tpws** (transparent TCP proxy, app-compatible)
- Automatic system proxy configuration (SpoofDPI engine)
- Auto-detects and bypasses blocked sites
- DNS over HTTPS (DoH)
- Multiple DNS options (Google, Cloudflare, Quad9, custom)
- Multi-language: English, Türkçe, Français
- Launch at login + auto-connect

## Quick Start

Download `PunchThrough.app` from [Releases](https://github.com/quardianwolf/PunchThrough-MacOS/releases), move to `/Applications`, and launch. Both engines are bundled — no separate install needed.

> **"Not compatible" error?** Run `xattr -cr /Applications/PunchThrough.app` in Terminal.

Requires macOS 14.0+ (Universal: Apple Silicon & Intel).

See [full documentation](PunchThrough/README.md) for build instructions, settings, and troubleshooting.

## License

MIT
