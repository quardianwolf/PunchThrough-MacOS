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
- **Optional SSH tunnel** — send selected sites, or all browser traffic, through your own server to [open sites that block your country](#tunnel-open-sites-that-block-your-country)
- Multi-language: English, Türkçe, Français
- Launch at login + auto-connect

## Quick Start

Download `PunchThrough.app` from [Releases](https://github.com/quardianwolf/PunchThrough-MacOS/releases), move to `/Applications`, and launch. Both engines are bundled — no separate install needed.

> **"Not compatible" error?** Run `xattr -cr /Applications/PunchThrough.app` in Terminal.

Requires macOS 14.0+ (Universal: Apple Silicon & Intel).

See [full documentation](PunchThrough/README.md) for build instructions, settings, and troubleshooting.

## Tunnel: open sites that block your country

DPI bypass defeats blocks made by your ISP. It cannot help when the **website itself** refuses visitors from your country — for that your traffic has to come out somewhere else. The Tunnel does exactly that, using a server you control:

- **Selected sites only** — just the sites you list go through your server; everything else keeps using your normal connection (with DPI bypass).
- **All browser traffic** — every browser goes through your server.

It uses the SSH client that ships with macOS (`ssh -D`) plus a proxy auto-config script, so **nothing has to be installed on the server** and no admin password is needed. Any Linux machine you can SSH into works.

### 1. Get a server (skip if you already have one)

Any VPS in a country where the site is reachable will do. A free option is the Oracle Cloud "Always Free" tier:

1. Create an account at a cloud provider and pick a **region outside your country**.
2. Create a Linux instance (Ubuntu is fine).
3. When asked about SSH keys, choose **generate a key pair** and **download the private key**. Keep that file — it is your login.
4. Note the instance's **public IP address**.
5. Make sure **TCP port 22** is open in the provider's firewall / security list (it is by default on most providers).

Login user names: `ubuntu` on Ubuntu images, `opc` on Oracle Linux, `root` on many other VPS providers.

### 2. Set it up in PunchThrough

Open **Settings > Tunnel** and follow the four steps on that page:

| Step | What you do | What PunchThrough checks |
|------|-------------|--------------------------|
| 1. SSH client | Nothing — macOS includes it | That `/usr/bin/ssh` is present |
| 2. Your server | Enter address, port (22), user and choose the private key file | That the key is a usable OpenSSH private key (not `.ppk`, not `.pub`) |
| 3. Test the connection | Click **Test connection** | Server reachable → login works → which IP and country your traffic exits from |
| 4. What goes through | Choose a mode, add your sites, click **Save & apply** | — |

Every check tells you what to fix when it fails, and the test stops at the first problem. The tunnel then starts and stops together with Connect/Disconnect and reconnects by itself if the connection drops.

**Adding sites:** type a domain (for example `example.com`) and press **+**. Subdomains are included automatically. If a page opens without images or styling, the site serves those from a second domain — add that one too (Safari/Chrome developer tools, Network tab, shows which).

### Good to know

- **Browsers only.** The tunnel is applied through the macOS proxy settings (Automatic Proxy Configuration). Safari, Chrome, Edge and Firefox (default "use system proxy settings") follow it; apps that ignore the system proxy do not. It is not a full VPN.
- **Key login only.** Password logins and keys protected by a passphrase are not supported.
- Your key file is never modified, and no `chmod` is needed. PunchThrough works on a private copy inside `~/Library/Application Support/PunchThrough/tunnel`, because ssh rejects keys that other accounts can read.
- Your previous proxy settings are restored on disconnect and quit — and on the next launch if the app crashed.
- The exit location check asks `cloudflare.com/cdn-cgi/trace` — through the tunnel — which IP it sees.
- Some sites treat data-centre IP addresses with suspicion and may show extra CAPTCHAs.

## License

MIT
