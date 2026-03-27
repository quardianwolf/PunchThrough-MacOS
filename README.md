# SplitWire for macOS

A native macOS menu bar application that bypasses DPI (Deep Packet Inspection) restrictions. Works with ISPs that use DPI-based internet filtering.

Built with Swift/SwiftUI. Powered by [SpoofDPI](https://github.com/xvzc/SpoofDPI).

## Features

- One-click connect/disconnect from menu bar
- Automatic system proxy configuration
- Auto-detects and bypasses blocked sites
- DNS over HTTPS (DoH)
- Multiple DNS options (Google, Cloudflare, Quad9, custom)
- Multi-language: English, Türkçe, Français
- Launch at login

## Quick Start

```bash
brew install spoofdpi
```

Download `SplitWire.app` from [Releases](https://github.com/quardianwolf/SplitWire-MacOS/releases), move to `/Applications`, and launch.

> **"Not compatible" error?** Run `xattr -cr /Applications/SplitWire.app` in Terminal.

Requires macOS 14.0+ and SpoofDPI v1.2.1+.

See [full documentation](SplitWire/README.md) for build instructions, settings, and troubleshooting.

## License

MIT
