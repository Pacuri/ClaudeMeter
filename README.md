# ClaudeMeter

> Never get rate-limited again. See your Claude usage at a glance, right in the menu bar.

A native macOS menu bar app that tracks your Claude Pro/Max subscription usage in real time.

<p align="center">
  <img src="screenshots/menubar.png" width="200" alt="Menu bar gauge"/>
  <img src="screenshots/popover.png" width="320" alt="Usage popover"/>
</p>

## Features

- **Live gauge icon** in the menu bar that fills up as you use Claude
- **Session usage** (5-hour window) with reset countdown
- **Weekly usage** (7-day window) with reset countdown and pace indicator
- **Sonnet/Opus** model-specific tracking
- **Extra usage** spend tracking when enabled
- **Auto-refresh** every 60 seconds (configurable)
- **Launch at Login** support
- **Privacy-first** — everything runs locally, your session key never leaves your machine

## Install

### Download (easiest)

1. Go to [Releases](https://github.com/Pacuri/ClaudeMeter/releases) and download `ClaudeMeter.app.zip`
2. Unzip and drag to Applications
3. **Important:** Right-click the app > **Open** (first launch only — macOS blocks unsigned apps by default)

### Build from source

1. Clone this repo
2. Open in Xcode (File > Open > select the `ClaudeMeter` folder)
3. Build & Run (Cmd+R)
4. ClaudeMeter appears in your menu bar

**Requirements:** macOS 14.0+ (Sonoma), Xcode 15+, active Claude Pro or Max subscription.

## Setup

1. Launch ClaudeMeter — a gauge icon appears in your menu bar
2. Click it and paste your `sessionKey`:
   - Open [claude.ai](https://claude.ai) in Chrome/Safari/Firefox
   - Open DevTools (`Cmd+Option+I`)
   - Go to **Application** tab > **Cookies** > **claude.ai**
   - Copy the `sessionKey` value
   - Paste it in ClaudeMeter and click **Go**

The session key is stored locally on your Mac. You may need to re-paste it when it expires (roughly every 2 weeks).

## How it works

ClaudeMeter calls the same internal API endpoints that claude.ai uses to show your usage. No third-party servers, no proxies, no data collection. Your session key stays on your machine.

## Settings

Click the gear icon in the popover footer:

- **Refresh interval** — 30s, 1m, 2m, or 5m
- **Show usage % in menu bar** — toggle the percentage text next to the gauge
- **Launch at Login** — start ClaudeMeter when you log in
- **Session key** — update or disconnect your session

## Privacy

- Session key stored locally in UserDefaults
- Only network calls are to `claude.ai`
- No analytics, no telemetry, no third-party services
- Fully open source — read every line

## Tech

- Swift 5.9+ / SwiftUI
- `MenuBarExtra` with `.window` style
- Custom Core Graphics gauge renderer for the menu bar icon
- `SMAppService` for Launch at Login
- `CommonCrypto` for Chrome cookie decryption
- Zero external dependencies

## Credits

Made by [Nikolytics](https://github.com/Pacuri) & Nix.

## License

MIT
