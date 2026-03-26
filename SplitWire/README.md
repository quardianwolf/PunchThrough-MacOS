# SplitWire for macOS

DPI (Deep Packet Inspection) bypass aracı. Türk ISP'lerinin uyguladığı internet engellerini aşmak için tasarlanmış native macOS uygulaması.

## Ekran Görüntüleri / Screenshots

| Disconnected | Connected | Settings |
|:---:|:---:|:---:|
| ![Disconnected](Screenshots/menubar-disconnected.webp) | ![Connected](Screenshots/menubar-connected.webp) | ![Settings](Screenshots/settings.webp) |

## Özellikler

- **Tek tıkla bağlantı** - Menu bar'dan hızlıca Connect/Disconnect
- **Otomatik proxy ayarı** - HTTP ve HTTPS proxy otomatik yapılandırılır
- **Türk ISP optimizasyonu** - Türk internet sağlayıcıları için özel ayarlar
- **DNS over HTTPS** - Güvenli DNS sorguları
- **Hafif ve hızlı** - Native Swift/SwiftUI ile yazıldı

## Gereksinimler

- macOS 14.0 (Sonoma) veya üstü
- [Homebrew](https://brew.sh) paket yöneticisi
- Xcode Command Line Tools (kaynak koddan derlemek için)

## Kurulum

> **ÖNEMLİ:** SpoofDPI yüklü olmalıdır, yoksa uygulama çalışmaz!

### 1. Homebrew yükle (yoksa)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2. SpoofDPI'ı yükle (ZORUNLU)

```bash
brew install spoofdpi
```

Yüklü olduğunu kontrol et:
```bash
which spoofdpi
# Çıktı: /opt/homebrew/bin/spoofdpi veya /usr/local/bin/spoofdpi
```

### 3. SplitWire'ı yükle

#### Kaynak koddan derleme (Xcode gerekli):

```bash
# Xcode Command Line Tools yükle (yoksa)
xcode-select --install

# Repoyu klonla
git clone https://github.com/quardianwolf/SplitWire-Turkey-MacOS.git
cd SplitWire-Turkey-MacOS

# Derle
xcodebuild -scheme SplitWire -configuration Release build

# Applications'a kopyala
cp -r ~/Library/Developer/Xcode/DerivedData/SplitWire-*/Build/Products/Release/SplitWire.app /Applications/

# Uygulamayı başlat
open /Applications/SplitWire.app
```

#### Hazır uygulama:
[Releases](https://github.com/quardianwolf/SplitWire-Turkey-MacOS/releases) sayfasından `SplitWire.app` dosyasını indirip `/Applications` klasörüne taşıyın.

> **"Not compatible" veya "damaged" hatası alıyorsanız:**
> Bu hata uygulamanın imzasız (unsigned) olmasından kaynaklanır, Intel/Apple Silicon farkıyla ilgisi yoktur. Çözmek için:
> 1. Uygulamaya **sağ tık > Aç (Open)** yapın
> 2. Veya: **Sistem Ayarları > Gizlilik ve Güvenlik** kısmından "Yine de Aç (Open Anyway)" seçin
> 3. Veya terminalde çalıştırın: `xattr -cr /Applications/SplitWire.app`

### Hızlı Başlangıç (Tek Komut)

```bash
brew install spoofdpi && \
git clone https://github.com/quardianwolf/SplitWire-Turkey-MacOS.git && \
cd SplitWire-Turkey-MacOS && \
xcodebuild -scheme SplitWire -configuration Release build && \
cp -r ~/Library/Developer/Xcode/DerivedData/SplitWire-*/Build/Products/Release/SplitWire.app /Applications/ && \
open /Applications/SplitWire.app
```

## Kullanım

### Temel Kullanım

1. **Uygulamayı başlat** - SplitWire menu bar'da görünecek
2. **Connect** - Bypass'ı aktif et
3. **Disconnect** - Bypass'ı kapat

### Menu Bar

| Öğe | Açıklama |
|-----|----------|
| Durum | Bağlantı durumu (Connected/Disconnected) |
| Connect/Disconnect | Bypass'ı aç/kapat |
| Settings | Ayarlar penceresini aç |
| Quit | Uygulamayı kapat |

### Ayarlar

#### DNS Seçenekleri
- **Google** (8.8.8.8) - Varsayılan
- **Cloudflare** (1.1.1.1)
- **Quad9** (9.9.9.9)
- **Custom** - Özel DNS adresi

#### Bypass Seçenekleri
- **Port** - Proxy port numarası (varsayılan: 8080)
- **DNS over HTTPS** - Güvenli DNS sorguları
- **System Proxy** - Otomatik sistem proxy ayarı

## Nasıl Çalışır?

SplitWire, [SpoofDPI](https://github.com/xvzc/SpoofDPI) aracını kullanarak DPI bypass yapar:

1. **Paket Parçalama** - HTTPS paketlerini küçük parçalara böler
2. **Disorder** - Paketleri karışık sırada gönderir
3. **DNS over HTTPS** - DNS sorgularını şifreler

Bu teknikler, ISP'lerin DPI sistemlerinin trafiği analiz etmesini zorlaştırır.

## Teknik Detaylar

### SpoofDPI Parametreleri

```bash
spoofdpi \
  --listen-addr 127.0.0.1:8080 \
  --dns-addr 8.8.8.8:53 \
  --dns-mode https \
  --https-disorder \
  --https-chunk-size 1
```

### Sistem Proxy

Uygulama otomatik olarak şu proxy ayarlarını yapar:
- HTTP Proxy: `127.0.0.1:8080`
- HTTPS Proxy: `127.0.0.1:8080`

## Sorun Giderme

### SpoofDPI yüklü değil hatası

```bash
brew install spoofdpi
```

### Port kullanımda hatası

Başka bir uygulama 8080 portunu kullanıyor olabilir:
```bash
lsof -i :8080
```

Settings'den farklı bir port seçebilirsiniz.

### Bağlantı başarısız

1. SpoofDPI'ın yüklü olduğundan emin olun
2. Settings > Logs kısmından hata mesajlarını kontrol edin
3. Farklı bir DNS sunucusu deneyin

### Discord/Twitter hala açılmıyor

1. Tarayıcı önbelleğini temizleyin
2. Uygulamayı tamamen kapatıp tekrar açın
3. DNS önbelleğini temizleyin:
```bash
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

## Katkıda Bulunma

1. Fork edin
2. Feature branch oluşturun (`git checkout -b feature/amazing`)
3. Commit edin (`git commit -m 'Add amazing feature'`)
4. Push edin (`git push origin feature/amazing`)
5. Pull Request açın

## Lisans

MIT License

## Teşekkürler

- [SpoofDPI](https://github.com/xvzc/SpoofDPI) - DPI bypass motoru
- Tüm katkıda bulunanlara

---

**Not:** Bu uygulama yasal amaçlarla kullanılmak üzere tasarlanmıştır. Lütfen yerel yasalara uygun şekilde kullanın.

---

# SplitWire for macOS (English)

A DPI (Deep Packet Inspection) bypass tool. Native macOS application designed to bypass internet restrictions applied by Turkish ISPs.

## Features

- **One-click connection** - Quick Connect/Disconnect from menu bar
- **Automatic proxy setup** - HTTP and HTTPS proxy configured automatically
- **Turkish ISP optimization** - Special settings for Turkish internet providers
- **DNS over HTTPS** - Secure DNS queries
- **Lightweight and fast** - Written in native Swift/SwiftUI

## Requirements

- macOS 14.0 (Sonoma) or later
- [Homebrew](https://brew.sh) package manager
- Xcode Command Line Tools (for building from source)

## Installation

> **IMPORTANT:** SpoofDPI must be installed, otherwise the app won't work!

### 1. Install Homebrew (if not installed)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2. Install SpoofDPI (REQUIRED)

```bash
brew install spoofdpi
```

Verify installation:
```bash
which spoofdpi
# Output: /opt/homebrew/bin/spoofdpi or /usr/local/bin/spoofdpi
```

### 3. Install SplitWire

#### Build from source (requires Xcode):

```bash
# Install Xcode Command Line Tools (if not installed)
xcode-select --install

# Clone the repository
git clone https://github.com/quardianwolf/SplitWire-Turkey-MacOS.git
cd SplitWire-Turkey-MacOS

# Build
xcodebuild -scheme SplitWire -configuration Release build

# Copy to Applications
cp -r ~/Library/Developer/Xcode/DerivedData/SplitWire-*/Build/Products/Release/SplitWire.app /Applications/

# Launch the app
open /Applications/SplitWire.app
```

#### Pre-built application:
Download `SplitWire.app` from [Releases](https://github.com/quardianwolf/SplitWire-Turkey-MacOS/releases) page and move it to `/Applications` folder.

**Getting "Not compatible" or "damaged" error?**

This happens because macOS blocks apps that are not signed/notarized by Apple. It has nothing to do with your processor (works on both Intel and Apple Silicon). A new release will be available soon, but in the meantime you can fix this by following these steps:

1. Download the latest release and move SplitWire.app to your Applications folder
2. Open Terminal (you can find it in Applications > Utilities > Terminal)
3. Copy and paste this command, then press Enter:
   `xattr -cr /Applications/SplitWire.app`
4. Now open SplitWire.app normally — it should launch without any errors

If you still see a warning, right-click (or Control-click) on SplitWire.app and select "Open" from the menu. macOS will ask you to confirm — click "Open" and it will work from that point on.

### Quick Start (Single Command)

```bash
brew install spoofdpi && \
git clone https://github.com/quardianwolf/SplitWire-Turkey-MacOS.git && \
cd SplitWire-Turkey-MacOS && \
xcodebuild -scheme SplitWire -configuration Release build && \
cp -r ~/Library/Developer/Xcode/DerivedData/SplitWire-*/Build/Products/Release/SplitWire.app /Applications/ && \
open /Applications/SplitWire.app
```

## Usage

### Basic Usage

1. **Launch the app** - SplitWire will appear in menu bar
2. **Connect** - Activate bypass
3. **Disconnect** - Deactivate bypass

### Menu Bar

| Item | Description |
|------|-------------|
| Status | Connection status (Connected/Disconnected) |
| Connect/Disconnect | Toggle bypass on/off |
| Settings | Open settings window |
| Quit | Close application |

### Settings

#### DNS Options
- **Google** (8.8.8.8) - Default
- **Cloudflare** (1.1.1.1)
- **Quad9** (9.9.9.9)
- **Custom** - Custom DNS address

#### Bypass Options
- **Port** - Proxy port number (default: 8080)
- **DNS over HTTPS** - Secure DNS queries
- **System Proxy** - Automatic system proxy configuration

## How It Works

SplitWire uses [SpoofDPI](https://github.com/xvzc/SpoofDPI) for DPI bypass:

1. **Packet Fragmentation** - Splits HTTPS packets into smaller chunks
2. **Disorder** - Sends packets out of order
3. **DNS over HTTPS** - Encrypts DNS queries

These techniques make it harder for ISP DPI systems to analyze traffic.

## Technical Details

### SpoofDPI Parameters

```bash
spoofdpi \
  --listen-addr 127.0.0.1:8080 \
  --dns-addr 8.8.8.8:53 \
  --dns-mode https \
  --https-disorder \
  --https-chunk-size 1
```

### System Proxy

The application automatically configures:
- HTTP Proxy: `127.0.0.1:8080`
- HTTPS Proxy: `127.0.0.1:8080`

## Troubleshooting

### SpoofDPI not installed error

```bash
brew install spoofdpi
```

### Port in use error

Another application might be using port 8080:
```bash
lsof -i :8080
```

You can select a different port in Settings.

### Connection failed

1. Make sure SpoofDPI is installed
2. Check error messages in Settings > Logs
3. Try a different DNS server

### Discord/Twitter still not working

1. Clear browser cache
2. Completely close and reopen the application
3. Flush DNS cache:
```bash
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing`)
5. Open a Pull Request

## License

MIT License

## Acknowledgments

- [SpoofDPI](https://github.com/xvzc/SpoofDPI) - DPI bypass engine
- All contributors

---

**Note:** This application is designed for legal purposes. Please use it in compliance with local laws.
