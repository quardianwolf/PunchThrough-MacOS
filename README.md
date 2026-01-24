# SplitWire for macOS

A native macOS menu bar application for managing DPI (Deep Packet Inspection) bypass tools. This is the macOS port of the Windows SplitWire-Turkey application.

## NOTE

You might receive an update error the first time Discord opens; please wait. It will log you in on the second update attempt (after 10 seconds).

## Features

- **Menu Bar App**: Unobtrusive status bar icon with quick access to controls
- **SpoofDPI Integration**: Primary bypass method using the lightweight SpoofDPI proxy
- **Zapret Integration**: Alternative bypass method for complex filtering scenarios
- **System Proxy Configuration**: Automatic system proxy setup
- **DNS Configuration**: Support for Google, Cloudflare, Quad9, or custom DNS
- **DNS over HTTPS (DoH)**: Enhanced privacy with encrypted DNS queries
- **Launch at Login**: Start automatically when you log in
- **Localization**: English and Turkish language support

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+ (for building)
- SpoofDPI (required): `brew install spoofdpi`
- Zapret (optional): Manual installation from GitHub

## Installation

### Prerequisites

1. Install Homebrew (if not already installed):
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

2. Install SpoofDPI:
   ```bash
   brew install spoofdpi
   ```

### Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/splitwire-for-mac.git
   cd splitwire-for-mac
   ```

2. Open the Xcode project:
   ```bash
   open SplitWire/SplitWire.xcodeproj
   ```

3. Build and run the project in Xcode (⌘R)

### Distribution Build

1. In Xcode, select **Product > Archive**
2. Export the archive as a macOS App
3. Optionally, notarize the app for distribution

## Usage

1. **Launch**: The app appears as an icon in your menu bar
2. **Connect**: Click the menu bar icon and select "Connect"
3. **Settings**: Access settings via the menu or ⌘, shortcut
4. **Change Method**: Select between SpoofDPI and Zapret in the menu

### Settings

- **General**
  - Launch at Login: Start SplitWire automatically on login
  - View connection status

- **Bypass**
  - Select bypass method (SpoofDPI / Zapret)
  - Configure DNS server
  - Enable/disable DoH
  - Set proxy port
  - View installation status

- **Logs**
  - View connection logs
  - Clear log history

## Architecture

```
┌─────────────────────────────────────────┐
│        SplitWire.app (Main App)         │
├─────────────────────────────────────────┤
│  MenuBarExtra UI                        │
│  ├── Status Display                     │
│  ├── Toggle Controls                    │
│  └── Settings Access                    │
├─────────────────────────────────────────┤
│  Services                               │
│  ├── BypassService (Orchestration)      │
│  ├── SpoofDPIService                    │
│  ├── ZapretService                      │
│  └── ProcessManager                     │
└─────────────────────────────────────────┘
            ↕ XPC (Optional)
┌─────────────────────────────────────────┐
│     SplitWireHelper (Privileged)        │
├─────────────────────────────────────────┤
│  - Privileged process management        │
│  - System proxy configuration           │
│  - Network settings modification        │
└─────────────────────────────────────────┘
```

## Project Structure

```
SplitWire/
├── SplitWire.xcodeproj
├── SplitWire/
│   ├── SplitWireApp.swift          # App entry point
│   ├── Info.plist
│   ├── SplitWire.entitlements
│   ├── Models/
│   │   ├── AppState.swift          # Global state
│   │   ├── BypassMethod.swift      # Method definitions
│   │   └── ConnectionStatus.swift  # Status enum
│   ├── Views/
│   │   ├── MenuBarView.swift       # Menu bar UI
│   │   ├── SettingsView.swift      # Settings window
│   │   └── StatusIndicator.swift   # Status dot
│   ├── Services/
│   │   ├── BypassService.swift     # Main service
│   │   ├── ProcessManager.swift    # Process lifecycle
│   │   ├── SpoofDPIService.swift   # SpoofDPI wrapper
│   │   ├── ZapretService.swift     # Zapret wrapper
│   │   └── HelperConnection.swift  # XPC client
│   └── Resources/
│       ├── en.lproj/
│       └── tr.lproj/
└── SplitWireHelper/
    ├── main.swift                  # Helper entry
    ├── HelperProtocol.swift        # XPC protocol
    ├── HelperTool.swift            # Implementation
    ├── Info.plist
    └── launchd.plist
```

## Supported Bypass Methods

### SpoofDPI (Recommended)
- Lightweight DPI bypass proxy
- Supports DNS over HTTPS
- Automatic system proxy configuration
- Install: `brew install spoofdpi`

### Zapret
- Advanced DPI bypass tool
- Multiple bypass strategies
- ISP-specific presets
- Manual installation required

## Troubleshooting

### SpoofDPI not found
Ensure SpoofDPI is installed and in your PATH:
```bash
brew install spoofdpi
which spoofdpi
```

### Connection issues
1. Check the Logs tab in Settings for error messages
2. Verify your DNS settings
3. Try switching between SpoofDPI and Zapret

### Helper tool installation
If the privileged helper fails to install:
1. Check System Preferences > Privacy & Security
2. Allow the app if prompted
3. Restart the app

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - See LICENSE file for details

## Acknowledgments

- [SpoofDPI](https://github.com/xvzc/SpoofDPI) - DPI bypass tool
- [Zapret](https://github.com/bol-van/zapret) - Advanced DPI bypass
- [SplitWire-Turkey](https://github.com/example/splitwire-turkey) - Original Windows version
