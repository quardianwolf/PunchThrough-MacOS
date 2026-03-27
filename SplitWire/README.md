# SplitWire for macOS

A native macOS menu bar application that bypasses DPI (Deep Packet Inspection) restrictions. Works with ISPs that use DPI-based internet filtering.

## Screenshots

| Disconnected | Connected | Settings |
|:---:|:---:|:---:|
| ![Disconnected](Screenshots/menubar-disconnected.webp) | ![Connected](Screenshots/menubar-connected.webp) | ![Settings](Screenshots/settings.webp) |

## Features

- **One-click connection** - Connect/Disconnect from the menu bar
- **Automatic proxy setup** - HTTP and HTTPS proxy configured automatically
- **Auto policy detection** - Automatically detects and bypasses blocked sites
- **DNS over HTTPS** - Secure encrypted DNS queries
- **Multiple DNS options** - Google, Cloudflare, Quad9, or custom DNS
- **Multi-language** - English, Turkish, French (selectable in Settings)
- **Lightweight and fast** - Native Swift/SwiftUI, runs in the menu bar

## Requirements

- macOS 14.0 (Sonoma) or later
- [SpoofDPI](https://github.com/xvzc/SpoofDPI) v1.2.1+ (required)

## Installation

### 1. Install SpoofDPI (required)

```bash
# Install Homebrew if you don't have it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install SpoofDPI
brew install spoofdpi
```

Verify:
```bash
which spoofdpi
# /opt/homebrew/bin/spoofdpi (Apple Silicon) or /usr/local/bin/spoofdpi (Intel)
```

### 2. Install SplitWire

#### Pre-built (recommended):
Download `SplitWire.app` from [Releases](https://github.com/quardianwolf/SplitWire-MacOS/releases) and move it to `/Applications`.

**Getting "Not compatible" or "damaged" error?**

This happens because macOS blocks apps that are not signed/notarized by Apple. It works on both Intel and Apple Silicon. To fix:

1. Download the latest release and move SplitWire.app to your Applications folder
2. Open Terminal (Applications > Utilities > Terminal)
3. Run: `xattr -cr /Applications/SplitWire.app`
4. Open SplitWire.app normally

If you still see a warning, right-click on SplitWire.app and select "Open".

#### Build from source:
```bash
xcode-select --install
git clone https://github.com/quardianwolf/SplitWire-MacOS.git
cd SplitWire-MacOS
xcodebuild -scheme SplitWire -configuration Release build
cp -r ~/Library/Developer/Xcode/DerivedData/SplitWire-*/Build/Products/Release/SplitWire.app /Applications/
open /Applications/SplitWire.app
```

## Usage

1. **Launch** - SplitWire appears in your menu bar
2. **Connect** - Click the menu bar icon and select "Connect"
3. **Settings** - Configure DNS, port, language, and more

### Settings

- **General** - Launch at login, language selection, connection status
- **Bypass** - DNS server, DoH, proxy port, installation status
- **Logs** - View and clear connection logs

## How It Works

SplitWire runs a local proxy on your Mac (127.0.0.1:8080) and routes your traffic through it. It works like a local VPN, but instead of encrypting and tunneling all traffic to a remote server, it manipulates how your packets are sent to trick your ISP's DPI (Deep Packet Inspection) system.

**What it does:**
1. **Packet Fragmentation** - Splits the HTTPS handshake into tiny chunks so the DPI can't read the destination
2. **Disorder** - Sends those chunks out of order, further confusing the DPI
3. **Auto Policy** - Automatically detects which sites are blocked and applies bypass only to those
4. **DNS over HTTPS** - Encrypts DNS queries so your ISP can't block sites at the DNS level

**How is this different from a VPN?**
- No remote server needed - everything runs locally on your Mac
- No speed loss - your traffic goes directly to the destination, not through a middleman
- Your ISP still sees your traffic, but can't analyze it well enough to block specific sites
- No subscription, no account, no data collection

## Troubleshooting

### SpoofDPI outdated or not installed
```bash
brew install spoofdpi    # install
brew upgrade spoofdpi    # update to latest
```

### Port in use
```bash
lsof -i :8080
```
You can change the port in Settings.

### Sites still not loading
1. Check Settings > Logs for error messages
2. Try a different DNS server (Cloudflare, Quad9)
3. Flush DNS cache:
```bash
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

## Contributing

Contributions and translations are welcome! Feel free to submit a Pull Request.

## License

MIT License

## Acknowledgments

- [SpoofDPI](https://github.com/xvzc/SpoofDPI) - DPI bypass engine
- [@Tetonne](https://github.com/Tetonne) - French translation

---

**Note:** This application is designed for legal purposes. Please use it in compliance with local laws.
