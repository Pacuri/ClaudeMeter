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
- **Privacy-first** — your session key never leaves your machine

## Install

### Download (easiest)

1. Go to [Releases](https://github.com/Pacuri/ClaudeMeter/releases/latest) and download `ClaudeMeter.app.zip`
2. Unzip and drag to Applications
3. **Important:** Right-click the app > **Open** (first launch only — macOS blocks unsigned apps by default)

### Build from source

```bash
git clone https://github.com/Pacuri/ClaudeMeter.git
cd ClaudeMeter
swift build -c release
```

Or open in Xcode and hit Cmd+R.

**Requirements:** macOS 14.0+ (Sonoma), Xcode 15+, active Claude Pro or Max subscription.

## Setup

ClaudeMeter uses a 3-step setup:

### 1. Get your free license key
Enter your email and how you use Claude. We'll send a license key to your inbox instantly.

### 2. Activate
Paste the license key from your email (format: `CM-XXXX-XXXX-XXXX`).

### 3. Connect to Claude
Paste your session key from claude.ai:

**Chrome:**
1. Open [claude.ai](https://claude.ai) and press `Cmd+Option+I`
2. Go to **Application** tab > **Cookies** > **claude.ai**
3. Copy the `sessionKey` value

**Safari:**
1. Enable the Develop menu in Safari > Settings > Advanced
2. Open [claude.ai](https://claude.ai) > Develop > Show Web Inspector
3. Go to **Storage** > **Cookies** > **claude.ai**
4. Copy the `sessionKey` value

The session key is stored locally on your Mac. You may need to re-paste it when it expires (roughly every 2 weeks).

## How it works

ClaudeMeter calls the same internal API endpoints that claude.ai uses to show your usage. No third-party servers, no proxies. Your session key stays on your machine.

## Settings

Click the gear icon in the popover footer:

- **Refresh interval** — 30s, 1m, 2m, or 5m
- **Show usage % in menu bar** — toggle the percentage text next to the gauge
- **Launch at Login** — start ClaudeMeter when you log in
- **Session key** — update or disconnect your session

## Support

Having trouble? Email us at **hello@nikolytics.com** — we're happy to help with license keys, setup issues, or anything else.

## Tech

- Swift 5.9+ / SwiftUI
- `MenuBarExtra` with `.window` style
- Custom Core Graphics gauge renderer for the menu bar icon
- `SMAppService` for Launch at Login
- Zero external dependencies

## Credits

Made by [Nikolytics](https://nikolytics.com).

## License

MIT
