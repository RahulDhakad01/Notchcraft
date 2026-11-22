<div align="center">

<img src="Sources/NotchCraft/Resources/AppIcon.png" alt="NotchCraft Icon" width="128" height="128" />

# NotchCraft

**A sleek, native macOS notch utility and Dynamic Island control center built with SwiftUI & AppKit.**

[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-black?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Release](https://img.shields.io/github/v/release/RahulDhakad01/Notchcraft?style=flat-square&color=blue)](https://github.com/RahulDhakad01/Notchcraft/releases/latest)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange?style=flat-square&logo=swift)](https://swift.org/)
[![Architecture](https://img.shields.io/badge/arch-arm64%20%7C%20x86__64-blue?style=flat-square)](https://apple.com)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

</div>

---

## 🌟 Overview

**NotchCraft** turns the camera notch of your Mac into a small control center. Hover or click the notch and it expands into a panel with music, weather, your calendar, a file tray, notes, a timer, snippets and your recent apps. Drag a file to the top of the screen and it lands in the tray, ready to convert, preview or drag out again.

Everything runs locally on your Mac. There are no accounts, no telemetry and no third-party dependencies.

---

## ✨ Features

| Page | What it does |
|---|---|
| 🏠 **Home** | Now-playing music card, live weather, a calendar strip and your recent apps in one view. |
| ⏱️ **Timer** | Countdown (presets and custom times), stopwatch with laps, chime and notification when time is up, and reminders. |
| 📋 **Snippets** | Clipboard history plus pinned snippets you can copy back with one click. |
| 📝 **Notes** | Quick notes you can sync to Apple Notes, and your recent Apple Notes. |
| 📥 **Tray** | A temporary shelf for files: preview, convert, AirDrop, drag out, copy. New screenshots drop in automatically. |
| ⚙️ **Settings** | General, Music, Calendar and Appearance options. |

### 🎵 Music
- Works with **Spotify**, **Apple Music**, **web players in Chrome, Safari, Brave and Edge**, and a **built-in player for local audio files** (pick a file and play it, for any other music app you use).
- Album art, progress bar, play/pause, next/previous, and an animated wave beside the notch while music plays.
- **Live lyrics** (looked up from lrclib.net by song and artist) can be turned on or off.
- If you switch between players (for example Chrome, then Safari), the most recent one wins.
- Pick the source in **Settings → Music**: automatic, or a specific player.
- Web players need the browser to allow Apple Events JavaScript (Safari: Settings → Developer → *Allow JavaScript from Apple Events*; Chrome/Brave/Edge: View → Developer). Settings → Music shows what is missing.

### 📅 Calendar
- A smooth, horizontally scrolling day strip. Opening the notch always shows today.
- Open the calendar panel to see the day's events, **add** events (title, time, calendar, alert) and **delete** them.
- **Event alerts**: get a notification before events that don't already have an alert in Calendar (at start, 5, 10, 15 or 30 minutes).
- Accounts (iCloud, Google, Exchange…) are managed in the Calendar app: Settings → Calendar has a shortcut to open it.

### 🌤️ Weather
Current temperature, conditions and a short forecast from Open-Meteo (no API key). Choose your city or use your current location in **Settings → General**.

### 📥 Tray and file conversion
Drag files onto the notch (or use **Add Files**) to keep them in the tray. Each file card offers, on hover:
- **Copy**, **Quick Look** preview, **Convert** and **Remove**. Right-click for **Open**, **Reveal in Finder**, **Send via AirDrop**, **Convert To**, **Copy Path** and more.
- You can drag a file out of the tray into any app, and new screenshots are added automatically.
- Choose how long files are kept with the **Keep** menu.

**Converting:** click the convert icon on a card and pick a format from the menu. A progress overlay with a **Cancel** button appears, and the result lands in the tray as a new file. The original is never changed.

| You have | You can convert to |
|---|---|
| **Pictures** (PNG, JPG, HEIC, GIF, BMP, TIFF, WebP) | JPG, PNG, HEIC, PDF |
| **PDF** | Word (.docx), JPG, PNG (a zip for several pages) |
| **Word** (.docx, .doc, .rtf, .odt) | PDF; old formats also to .docx |
| **Pages** | PDF, Word |
| **Text, Markdown, HTML** | PDF, Word |
| **Excel** (.xlsx, .xls) | PDF; .xlsx also to CSV, .xls also to .xlsx |
| **CSV / TSV** | Excel (.xlsx), PDF |
| **Numbers** | PDF, Excel |
| **PowerPoint** (.pptx, .ppt) | PDF |
| **Keynote** | PDF, PowerPoint |

How good are the results:
- **PDF → Word** rebuilds the document instead of dumping text: fonts, sizes and colors, headings, paragraphs, bulleted and numbered lists, real tables (with merged cells and shading), shaded boxes, columns, links, underlines, pictures and charts, plus headers, footers and page numbers. Scanned pages are read with text recognition (handwriting is poor and long scans can spill onto extra pages).
- **Pictures** keep their date and camera info. A multi-page TIFF becomes a multi-page PDF.
- **Markdown → Word** keeps headings, numbered and nested lists, code blocks, quotes, tables and links.
- **Wide Excel sheets** are fitted one page wide when exported to PDF.
- Word, Excel, PowerPoint, Pages, Numbers and Keynote conversions use the apps you already have installed (macOS asks once for Automation access). Without them, simpler built-in conversions are used where possible.
- Empty, damaged, wrong-extension and password-protected files get a plain explanation instead of failing silently.

### 📝 Notes, 📋 Snippets and ⏱️ Timer
- **Notes**: write a quick note and save it to Apple Notes, or open recent notes. The scroll bar is slim and Apple-style.
- **Snippets**: clipboard history is captured automatically. Pin the ones you reuse.
- **Timer**: pick a countdown preset or set your own, or switch to the stopwatch and record laps. **Reminders** can be added on the same page.

### 🚀 Recent apps and menu bar
- **Recent apps** on Home give one-click access to what you use most, and you can hide the ones you don't want.
- The menu bar icon offers **Open Notch**, **Reset UI**, **Restart App**, **Launch on Startup** and **Quit**.

### ⚙️ Settings
- **General**: notch size (Compact or Roomy), launch on startup, weather city, reset the interface.
- **Music**: source, local files, web players, music in the notch, live lyrics.
- **Calendar**: event alerts, notification status, a shortcut to your calendar accounts.
- **Appearance**: Colourful (tints follow the album art) or Simple.

---

## 🧭 How to use

1. **Open the notch**: hover over or click the notch at the top of the screen, or choose **Open Notch** from the menu bar icon. Click outside or press `Esc` to close it.
2. **Switch pages** with the round buttons in the top bar: Home, Snippets, Timer on the left; Notes, Tray and Settings on the right.
3. **Play music**: start a song in Spotify, Apple Music or a browser and it appears on Home. For other players, open **Settings → Music → Local files** and choose an audio file.
4. **Check your day**: scroll the day strip on Home, click a day to see its events, and use **+** to add one. Allow Calendar access when macOS asks.
5. **Convert a file**: drop it on the notch (or **Tray → Add Files**), hover the card, click the convert icon and pick a format. The converted file appears as a new card; drag it where you need it.
6. **Keep notes or timers**: use **Notes** for quick text and **Timer** for focus sessions.
7. **Tune it**: **Settings** has music, calendar, weather and appearance options.

> The first time you use a feature, macOS may ask for permission (Calendar, Automation for Spotify/Music/Notes/browsers/Office apps, Notifications, Location). You can change these any time in **System Settings → Privacy & Security**.

---

## 🛠️ Architecture & Tech Stack

- **Pure native Swift & SwiftUI**, with AppKit for the floating panel.
- **No third-party dependencies**: only Apple frameworks (`AppKit`, `SwiftUI`, `EventKit`, `CoreLocation`, `ServiceManagement`, `QuickLook`, `UserNotifications`, `PDFKit`, `CoreGraphics`, `ImageIO`, `Vision`).
- **Own PDF engine**: reads a PDF's drawing instructions directly (text decoding, fonts, lines, boxes, pictures), analyses the layout, and writes the `.docx` itself. No Python, Office or cloud service is needed for PDF → Word.
- **Multi-Space & fullscreen**: an `NSPanel` at `.statusBar` level that joins all Spaces.

---

## 🚀 Getting Started

### 📥 Installing NotchCraft

NotchCraft is a free, open-source app and is **not notarized by Apple** (that needs a paid developer account). Because of that, macOS shows a warning the first time you open it. **The app is safe to open, and the source code is right here to read.** Pick whichever option is easiest for you.

> Made for **Apple Silicon Macs (M1, M2, M3, M4, M5)** with macOS 14 Sonoma or newer. It also runs on Intel Macs, but that is not the main focus.

#### Option 1 — Download and click (no Terminal)

1. Open the [**Releases page**](https://github.com/RahulDhakad01/Notchcraft/releases/latest) and download **`NotchCraft-macOS.dmg`**.
2. Double-click the DMG, then drag **NotchCraft** into the **Applications** folder.
3. Open **Applications** and double-click **NotchCraft**. macOS will say it *can't verify the app*. Click **Done** (or **OK**).
4. Open **System Settings → Privacy & Security** and scroll down to the **Security** section.
5. You will see *"NotchCraft was blocked…"*. Click **Open Anyway**, enter your Mac password or use Touch ID, then click **Open**.
6. From now on it opens normally. Look for it at the notch at the top of your screen.

> On macOS 14 (Sonoma) you can also just **right-click the app → Open → Open**.

#### Option 2 — Terminal, no warning at all (copy and paste)

Files downloaded with Terminal aren't marked "from the internet", so macOS doesn't show the warning. Open **Terminal** (press `⌘ Space`, type `Terminal`, press Enter) and paste each step, one at a time, pressing Enter after each:

**Step 1 — download the app**
```bash
curl -L -o ~/Downloads/NotchCraft-macOS.zip https://github.com/RahulDhakad01/Notchcraft/releases/latest/download/NotchCraft-macOS.zip
```

**Step 2 — unzip it**
```bash
unzip -o ~/Downloads/NotchCraft-macOS.zip -d ~/Downloads/NotchCraft-install
```

**Step 3 — move it to Applications** (this replaces an older version if you have one)
```bash
rm -rf /Applications/NotchCraft.app && mv ~/Downloads/NotchCraft-install/NotchCraft.app /Applications/
```

**Step 4 — open it**
```bash
open /Applications/NotchCraft.app
```

**Step 5 — tidy up** (optional)
```bash
rm -rf ~/Downloads/NotchCraft-install ~/Downloads/NotchCraft-macOS.zip
```

#### Option 3 — You already downloaded it and macOS blocks it

If you downloaded it in a browser and macOS says the app is **"damaged"** or **"can't be opened"**, drag it to **Applications**, then paste this in Terminal and press Enter:

```bash
xattr -dr com.apple.quarantine /Applications/NotchCraft.app
```

Then open the app again. (This only removes the "downloaded from the internet" mark. It changes nothing else.)

#### First launch and permissions

NotchCraft asks for permissions only when you use a feature that needs one: **Calendar** (events), **Automation** (control Spotify, Music, Notes, your browser, or Word/Excel/PowerPoint for conversions), **Notifications** (alerts) and **Location** (local weather). Click **Allow** when asked. You can change these any time in **System Settings → Privacy & Security**.

Since the app isn't notarized, macOS may ask for these permissions again after you **update** to a new version. That's normal.

#### Updating, removing, and problems

- **Update:** quit NotchCraft (menu bar icon → **Quit NotchCraft**), then repeat Option 1 or 2. Your settings and tray are kept.
- **Remove:** quit it, then drag **NotchCraft** from Applications to the Trash. To also remove its data, run `rm -rf ~/Library/Application\ Support/NotchCraft`.
- **The notch doesn't appear:** menu bar icon → **Reset UI**, or **Restart App**.
- **"The app can't be opened because Apple cannot check it":** use Option 1 step 4–5, or Option 3.

---

### 💻 Building from Source

#### Prerequisites

- macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia)
- Xcode 16+ or Swift 6.0+ toolchain

#### Running Directly

Clone the repository and run directly with Swift Package Manager:

```bash
# Clone the repository
git clone https://github.com/RahulDhakad01/Notchcraft.git
cd Notchcraft

# Run directly
swift run
```

#### Compiling Release Binary

```bash
swift build -c release
```

---

## 📦 Packaging a Standalone `.app` / DMG

The repository includes an automated release packaging script that produces a universal binary (Apple Silicon + Intel) and packages it into an `.app` bundle, `.zip`, and `.dmg`:

```bash
./scripts/package-release-app.sh
```

The script will generate:
- `dist/NotchCraft.app`
- `dist/NotchCraft-macOS.zip`
- `dist/NotchCraft-macOS.dmg`

---

## ✅ Checking conversion quality

Two scripts test the converters. Both write their results under `.build/`.

```bash
# PDF → Word: converts sample PDFs, opens the result in Microsoft Word, and compares it with the original
scripts/pdf-docx-check/run.sh               # built-in fixtures (needs Word and Google Chrome)
scripts/pdf-docx-check/run.sh my-file.pdf   # or your own PDFs (needs Word)

# Everything else: pictures, CSV, Excel, Markdown, HTML and damaged-file handling
scripts/conversion-edge-check/run.sh
```

---

## 📂 Project Structure

```
NotchCraft/
├── Package.swift                    # Swift Package manifest
├── Sources/
│   └── NotchCraft/
│       ├── NotchCraftApp.swift      # Main application lifecycle entry point
│       ├── AppDelegate.swift        # Status item, wake/sleep observers, ESC handler
│       ├── AppState.swift           # Central state engine & background monitors
│       ├── NotchPanel.swift         # Floating borderless AppKit panel
│       ├── OverlayWindowController.swift # Window geometry & screen coordinate management
│       ├── NotchRootView.swift      # Interactive root SwiftUI view & drop resolver
│       ├── CompactNotchView.swift   # Collapsed notch pill UI
│       ├── ExpandedNotchView.swift  # Expanded control center & tab views
│       ├── PermissionManager.swift  # Privacy preflights (Calendar, Location, AppleScript)
│       ├── LaunchAtLoginController.swift # ServiceManagement & LaunchAgent startup controller
│       ├── FileDropResolver.swift   # Drag-and-drop ingestion & file staging
│       ├── TrayManagedStorage.swift # Shelf file management in Application Support
│       ├── TrayPreviewController.swift # QuickLook preview controller
│       ├── Conversion/              # Tray file conversion (images, PDF, Word, Excel, PowerPoint)
│       │   └── PDFToDocx/           # Layout-aware PDF → Word engine (PDF reader, layout analysis, .docx writer)
│       └── Resources/
│           ├── NotchCraft-Info.plist# Usage descriptions & bundle metadata
│           ├── AppIcon.icns         # macOS app icon
│           └── navbar.png           # Menu bar icon asset
├── scripts/
│   ├── package-release-app.sh       # Universal release packaging script
│   ├── pdf-docx-check/              # PDF → Word quality check (renders the result in Word and compares)
│   └── conversion-edge-check/       # Edge cases for the other conversions (pictures, CSV, Excel, Markdown, damaged files)
├── web-prototype/                   # Interactive web prototype & design concept
└── .github/
    └── workflows/
        └── build.yml                # GitHub Actions automated CI build
```

---

## 🔒 Privacy & Permissions

NotchCraft does **not** collect telemetry, track usage, or connect to third-party ad networks. All user data, notes, clipboard history, and staged files remain entirely local on your Mac:

- **Apple Events (`NSAppleEventsUsageDescription`)**: Used solely to control Apple Music playback and sync Apple Notes.
- **Calendar (`NSCalendarsFullAccessUsageDescription`)**: Used strictly to display your next upcoming appointment inside the notch.
- **Automation (Word / Excel / PowerPoint / Pages / Numbers / Keynote)**: Asked only the first time you convert a file that needs one of those apps. Files never leave your Mac.
- **Location (`NSLocationWhenInUseUsageDescription`)**: Used only when "Use Local" weather is selected to query Open-Meteo.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE) - see the LICENSE file for details.
