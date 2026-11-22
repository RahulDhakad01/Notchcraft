# NotchCraft — Project Documentation

The complete profile of the project: what it is, what it is built with, how it is built, every feature, how each feature behaves in normal and unusual situations, and what is still missing.

> Status note: the released version is **v1.0.0**. Everything marked **v2** below is built and working in the source tree but **not yet released** (the bundle version in `Info.plist` is still `1.0`, and no v2 tag or GitHub release exists).

---

## 1. Project at a glance

| | |
|---|---|
| **Name** | NotchCraft |
| **What it is** | A native macOS utility that turns the camera notch into a control center: music, weather, calendar, file tray with format conversion, notes, snippets, timer, recent apps |
| **Bundle identifier** | `com.notchcraft.app` |
| **Platform** | macOS 14 (Sonoma) or newer, Apple Silicon and Intel |
| **Language** | Swift (tools version 5.10 in `Package.swift`; builds with Swift 6 toolchains) |
| **UI** | SwiftUI, with AppKit for the floating window, menus and printing |
| **Build system** | Swift Package Manager (one executable target, no Xcode project) |
| **Third-party dependencies** | None. Apple system frameworks only |
| **Size** | About 21,000 lines of Swift in about 60 files |
| **License** | MIT |
| **Repository** | `RahulDhakad01/Notchcraft` |
| **Network use** | Weather, a coarse location lookup, album art search and lyrics lookup only (see §8). No accounts, no telemetry |

### Design principles
1. **Native and light.** Pure Swift/SwiftUI/AppKit, no web view, no bundled runtime, no cloud service needed for any core feature.
2. **Local first.** Files, notes, clipboard and conversions never leave the Mac.
3. **Never surprise the user.** Ask for a permission only when the feature needs it; explain failures in plain words; never modify an original file.
4. **Fail soft.** If the best route for a task fails, fall back to a simpler one instead of showing nothing.

---

## 2. Tech stack

### 2.1 Language and UI
| Technology | Used for |
|---|---|
| **Swift** | All application code |
| **SwiftUI** | Every view: notch panel pages, cards, settings, calendar, tray |
| **AppKit** | `NSPanel` floating window, status bar item and menu, `NSMenu` pop-ups, `NSPrintOperation` (text to PDF), `NSTextView`, scroll-bar customization, drag and drop |
| **Core Animation (CALayer)** | The animated music bars (kept out of SwiftUI so they cost almost no CPU) |
| **Swift Concurrency** | `async/await`, actors and tasks for conversions, polling and cancellation |

### 2.2 Apple frameworks by purpose
| Framework | Purpose |
|---|---|
| **EventKit** | Reading, creating and deleting calendar events (full access) |
| **UserNotifications** | Event alerts and timer notifications |
| **CoreLocation** | Weather for the current location (only when chosen) |
| **ServiceManagement** | Launch at login (`SMAppService`) |
| **QuickLook / QuickLookThumbnailing** | Tray previews (`Space`) and file thumbnails |
| **AVFoundation / AVFAudio** | The built-in local audio player |
| **Foundation `Process` + `/usr/bin/osascript`** | Talking to Spotify, Music, Notes, browsers and Office apps through AppleScript / Apple Events |
| **PDFKit** | Opening PDFs, rendering pages, checking passwords |
| **CoreGraphics / CGPDF** | Reading PDF content streams (text, shapes, images), rendering regions |
| **CoreText** | Font metrics for non-embedded PDF fonts |
| **ImageIO** | Reading and writing JPG, PNG, HEIC, TIFF, metadata |
| **Vision** | Text recognition (OCR) for scanned PDFs |
| **XMLParser + `/usr/bin/ditto`** | Reading and writing `.xlsx` / `.docx` packages |
| **Security / codesign** | Stable signature for the dev build so permissions persist |

### 2.3 External services (optional, all read-only lookups)
| Service | Used for | Data sent |
|---|---|---|
| **Open-Meteo** | Weather forecast | Rounded latitude/longitude |
| **ipapi.co** | Approximate location when "local" weather is chosen without GPS | Your IP (as for any web request) |
| **iTunes Search API** | Album artwork for tracks that have none (web / local) | Track and artist text |
| **LRCLIB (lrclib.net)** | Time-synced lyrics (can be turned off) | Song title and artist |

### 2.4 Development tools
| Tool | Role |
|---|---|
| **Swift Package Manager** (`swift build`, `swift run`) | Build, run, package |
| **`scripts/dev-run.sh`** | Debug build wrapped in a signed `.app`, so Calendar/Automation prompts appear and permissions stay across rebuilds |
| **`scripts/package-release-app.sh`** | Release build to `.app`, `.zip`, `.dmg` (universal) |
| **GitHub Actions** (`.github/workflows/build.yml`) | CI build on `macos-14` with Xcode 16 |
| **Microsoft Word** | Reference renderer in the PDF → Word quality check |
| **Google Chrome (headless)** | Generates test PDFs from HTML fixtures |

### 2.5 Why native Swift, and what was rejected
- **Web / Electron:** too heavy for an always-on notch utility.
- **Python libraries for PDF → Word (PyMuPDF, pdfplumber, python-docx):** would need a bundled Python (~100 MB), and PyMuPDF is AGPL-licensed, which does not fit a free MIT app. The same technique (read positions and lines, rebuild structure) was implemented natively instead.
- **Cloud converters or LibreOffice:** uploading user files breaks the local-first rule; LibreOffice's PDF import produces text boxes that are hard to edit.
- **`NSAttributedString` for PDF → Word:** this was the v1 approach; it only carries text, which is why formatting was lost.

---

## 3. Architecture

### 3.1 Process model
- A single menu-bar-agent style app. `NotchCraftApp` starts `AppDelegate`, which creates the **status bar item**, the **overlay window controller** and observers for sleep/wake, screen changes and the Esc key.
- The UI lives in one borderless **`NotchPanel`** (`NSPanel`) at status-bar level, joined to all Spaces and fullscreen spaces, positioned over the notch. `OverlayWindowController` owns geometry (notch size, centering, multiple displays).
- `NotchRootView` is the SwiftUI root; `CompactNotchView` is the collapsed pill; `ExpandedNotchView` holds the pages.

### 3.2 State
`AppState` (one `ObservableObject`, ~3,900 lines) is the single source of truth: which page is open, expanded/collapsed, music, weather, calendar, timer, clipboard, snippets, notes, tray files, settings, conversion states. Settings are stored in `UserDefaults`. Features are split into extensions/helpers (`CalendarFeature`, `MusicSource`, `WebPlayerBridge`, `LocalFilePlayer`, `ConversionFeature`, `LyricsService`, `ArtworkResolver`).

### 3.3 Source map
| Area | Files |
|---|---|
| App shell | `NotchCraftApp`, `AppDelegate`, `NotchPanel`, `OverlayWindowController`, `NotchRootView`, `CompactNotchView`, `NotchSurfaceShape`, `LaunchAtLoginController` |
| State and permissions | `AppState`, `PermissionManager`, `PermissionPromptView` |
| Pages and styling | `ExpandedNotchView`, `NowPlayingView`, `CalendarPanelView`, `GlassStyle`, `GlassCard`, `CardButtonStyle`, `RailButtonStyle`, `SlimScrollBar`, `MusicWaveView` |
| Music | `MusicSource`, `WebPlayerBridge`, `LocalFilePlayer`, `LyricsService`, `ArtworkResolver` |
| Calendar | `CalendarFeature`, `CalendarPanelView` |
| Tray | `FileDropResolver`, `TrayManagedStorage`, `TrayPreviewController`, `TrayFileCardView` |
| Conversion | `Conversion/*` (planner, engines, preflight, Office bridge) |
| PDF → Word engine | `Conversion/PDFToDocx/*` (13 files) |
| Tooling | `scripts/*`, `.github/workflows/build.yml` |

---

## 4. How it is built and run

### 4.1 Day-to-day
```bash
swift build                 # debug build
./scripts/dev-run.sh        # build, wrap in a signed .app, relaunch
swift run                   # run the bare binary (macOS permission prompts may not appear)
```
`dev-run.sh` exists because macOS only shows Calendar / Automation prompts for a real app bundle with its own `Info.plist`, and a stable signature keeps granted permissions across rebuilds. It only stops a previous dev instance, never an installed copy.

### 4.2 Release
`./scripts/package-release-app.sh` builds a universal binary (arm64 + x86_64), creates `NotchCraft.app`, `NotchCraft-macOS.zip` and `NotchCraft-macOS.dmg` in `dist/`. CI runs the same script.
**Known limit on the current Mac:** only Command Line Tools are installed (no Xcode), so `swift build --arch arm64 --arch x86_64` fails; the two architectures build separately. The release script needs a `lipo`-based change or a machine with Xcode.

### 4.3 Versioning
v1.0.0 is released. v2 work is uncommitted; to release it: bump `Info.plist`, build, tag, publish (needs explicit go-ahead).

---

## 5. Features, how they were built, and how they behave

### 5.1 The notch panel
- **Built with:** borderless `NSPanel` + SwiftUI, a custom `NotchSurfaceShape`, glass styling helpers.
- **Behavior:** collapsed pill at the notch; expands on hover/click; closes with Esc or when the pointer leaves; each page change keeps the panel size stable. Display modes **Compact** and **Roomy**.
- **Cases:** works on all Spaces and over fullscreen apps; re-centers on display changes and wake; **Reset UI** and **Restart App** in the menu bar recover from a stuck state. Navigation buttons have full-size hit areas, so one click always works.

### 5.2 Home
Music card, weather card, calendar strip, recent apps. Opening the notch always resets the calendar strip to **today**.

### 5.3 Music
- **Sources:** Spotify and Apple Music (AppleScript), **web players** in Chrome, Safari, Brave and Edge, and a **local file player** (AVFoundation) for any other app's files.
- **Built with:** `MusicSource` (source model and preference), `WebPlayerBridge` (reads the active tab's media state by running JavaScript through Apple Events; MediaSession metadata), `LocalFilePlayer`, `ArtworkResolver`, `LyricsService`, `MusicWaveView` (CALayer).
- **Behavior:** shows title, artist, artwork, progress, play/pause/next/previous; animated bars beside the notch; optional synced lyrics. Spotify is started **hidden/minimised** when music is started from the notch.
- **Edge cases:**
  | Situation | Result |
  |---|---|
  | Two players active (Chrome then Safari) | The most recently started one wins |
  | Nothing playing | Empty state shows the logo/tint of the last source (Spotify or Apple Music) |
  | Browser not allowing JavaScript from Apple Events | Settings → Music explains what to enable (Safari: Develop menu / Settings → Developer; Chrome/Brave/Edge: View → Developer) |
  | Automation permission denied | A prompt card explains it and links to System Settings |
  | Track has no artwork | Looked up by title/artist; falls back to the source logo |
  | No lyrics found / lyrics off | Lyrics area stays hidden; no error |
  | Source preference set manually (Settings → Music) | Only that source is used |

### 5.4 Calendar
- **Built with:** EventKit (full access), `CalendarFeature`, `CalendarPanelView`, UserNotifications.
- **Behavior:** a day strip with smooth, momentum-based horizontal scrolling (hand-rolled, no snapping or "pull-back"); day tiles are clickable; a panel lists the day's events and lets you **add** (title, time, calendar, alert) and **delete** events. **Event alerts** (at start, 5, 10, 15, 30 minutes) are sent only for events that have no alert of their own, so you never get two.
- **Edge cases:**
  | Situation | Result |
  |---|---|
  | Calendar access never asked / denied | Permission prompt card; features degrade to an explanation |
  | App run as a bare binary | macOS shows no prompt (this is why `dev-run.sh` builds a real bundle) |
  | Notifications turned off for the app | Orange warning in Settings → Calendar with a shortcut |
  | Multiple accounts (iCloud/Google/Exchange) | Managed in the Calendar app; Settings has an "Open Calendar" shortcut |
  | Event already has its own alert | NotchCraft does not add another |
  | Hidden off-screen strip days | Not clickable and hidden from accessibility, so they never steal clicks |

### 5.5 Weather
Open-Meteo forecast (current temperature, conditions, humidity, daily high/low). City list or current location (CoreLocation, or an approximate IP lookup). **Refresh weather** in Settings. Needs an internet connection.

### 5.6 Timer, stopwatch, reminders
Countdown with presets and custom time, stopwatch with up to 6 recent laps, chime plus notification when a countdown ends, reminders on the same page. 

### 5.7 Snippets (clipboard)
Clipboard history captured automatically (text, paths, links); tap to copy back; up to **10 pinned snippets**.

### 5.8 Notes
A quick note field with a slim Apple-style scroll bar (~10 pt wide knob, no track). Save to **Apple Notes** (AppleScript; first use asks for Automation access) and list recent notes (hide the ones you do not want).

### 5.9 Recent apps
The 5 most recently used apps, one click to open, individually hideable.

### 5.10 Tray (file shelf)
- **Built with:** `FileDropResolver` (drag/drop ingestion), `TrayManagedStorage` (copies into Application Support), `TrayPreviewController` (QuickLook), `TrayFileCardView`.
- **Behavior:** drop files or use **Add Files**; cards show thumbnails; hover shows Copy, Quick Look, Convert, Remove; right-click adds Open, Reveal in Finder, AirDrop, Convert To, Copy Path. Files can be dragged out. **New screenshots** are imported automatically.
- **Limits and cases:**
  | Situation | Result |
  |---|---|
  | More than **18** items | Only the newest 18 are listed |
  | Retention ("Keep" menu) | Until cleared, 5 hours or 1 day; expired items are removed |
  | Same file dropped twice | De-duplicated |
  | File moved or deleted outside the app | Converting it explains "The file is no longer there" |
  | Converted files | Stored in their own `converted-xxxx` folder; folder removed when its file is removed |

### 5.11 Menu bar, startup
Status item menu: **Open Notch**, **Reset UI**, **Restart App**, **Launch on Startup**, **Quit**. Launch at login uses `SMAppService`.

### 5.12 Settings
General (notch size, startup, weather city, reset), Music (source, local files, web players, notch display, lyrics), Calendar (alerts, notification status, accounts shortcut), Appearance (Colourful or Simple).

---

## 6. File conversion

### 6.1 How a conversion runs
1. **Planner** (`ConversionPlanner`) decides which targets a file offers, based on its extension and which apps are installed.
2. **Preflight** (`ConversionPreflight`) checks the file: exists, readable, not a folder, not an undownloaded iCloud placeholder, not empty, correct header (PDF `%PDF`; `.docx/.xlsx/.pptx` must be a zip; an old-container header means a **password-protected** Office file).
3. **Engine** converts into a fresh `converted-xxxx` folder. Engines: image (ImageIO), PDF (PDFKit + own engine), document (AppKit text system / own `.docx` writer), spreadsheet (own XLSX/CSV code), Office (AppleScript to Word/Excel/PowerPoint/Pages/Numbers/Keynote).
4. **Result** is added to the tray with a "Converted to …" message. On failure the folder is deleted and a message with **Details** is shown (and a shortcut to Automation settings when the cause is permissions). **Cancel** stops the job, quits an Office app NotchCraft launched, and removes any partial output.
- Only one conversion per card at a time; Office jobs are queued one at a time because those apps are single-threaded.
- The convert icon opens a native macOS pop-up menu (title, icon, optional note such as "uses Word").

### 6.2 Routes and behavior
| From | To | Engine | Notes |
|---|---|---|---|
| Image | JPG / PNG / HEIC | ImageIO | Rotation applied to pixels; JPEG flattens transparency onto white; capture date, camera and location copied; color profile kept; quality 0.92 |
| Image | PDF | ImageIO / CoreGraphics | Page follows the picture (capped ~1000 pt); photos stay JPEG inside the PDF; **multi-page TIFF → multi-page PDF**; GIFs use the first frame |
| PDF | JPG / PNG | PDFKit | ~200 dpi, long side ≤ 4000 px, crop box, white background; several pages → one zip with zero-padded names |
| PDF | Word | Own engine (§7) | Falls back to the plain text converter if the engine fails or keeps < 85% of the text |
| Word (docx/doc/rtf/odt) | PDF | Word, else Pages, else built-in | Built-in is plainer |
| doc / rtf / odt | docx | Word, else built-in | Word keeps tables and styles |
| Pages | PDF / docx | Pages | |
| Text / Markdown / HTML | PDF | AppKit text system | Markdown: headings, numbered and nested lists, code blocks (monospace, shaded), quotes, tables, rules, links; HTML honors its declared encoding and relative images |
| Markdown | docx | Own `.docx` writer | Real Word headings, lists, table with header row, shaded code, quote bar |
| Text / HTML | docx | AppKit text system | |
| xlsx | CSV | Own parser | Visible sheets only; several sheets → zip; dates as `yyyy-MM-dd`; percent and fixed decimals as shown; float noise removed; UTF-8 with BOM |
| CSV / TSV | xlsx | Own writer | Delimiter detected; UTF-8, UTF-16, Windows-1252 read correctly; leading zeros kept as text; header row bold and frozen; > 1,048,576 rows or > 16,384 columns gives a clear error |
| xlsx / csv / xls | PDF | Excel, else Numbers | Wide sheets fitted one page wide (landscape if > 8 columns) unless the sheet has its own print settings |
| xls / Numbers | xlsx | Excel / Numbers | |
| pptx / ppt | PDF | PowerPoint, else Keynote | |
| Keynote | PDF / pptx | Keynote | |

### 6.3 Behavior in unusual situations
| Situation | Result |
|---|---|
| Empty file | "The file is empty." |
| Damaged PDF / wrong extension | "It doesn't look like a valid PDF (it may be damaged or have the wrong extension)." |
| Password-protected Office file | "This file is password-protected. Remove the password in its original app, then try again." |
| Password-protected PDF | "The PDF is password-protected." |
| Folder dropped on a convert action | "Folders can't be converted." |
| iCloud file not downloaded | Asks the user to download it first |
| Office app not installed | Option is hidden, or a built-in route is offered |
| Automation permission denied | Message with a button to Automation settings |
| Office app just launched and drops the first command | One automatic retry after 4 s |
| Office app stuck on a dialog | Times out after 240 s with a message |
| Office route fails for docx/doc/rtf/odt → pdf/docx | Automatic fallback to the built-in converter |
| Cancel pressed | Job stopped, app closed (if NotchCraft launched it), output deleted |
| Source file changes while converting | Original is never modified; only the copy is read |

---

## 7. The PDF → Word engine (v2)

### 7.1 Why it was hard
A PDF has no paragraphs, headings or tables — only instructions such as "draw this character at x, y" and "draw a line here". The engine has to infer structure from positions. PDFKit's character positions were also unreliable for PDFs with non-embedded standard fonts, so the engine decodes the content stream itself. Word has its own layout rules that had to be measured (§7.4).

### 7.2 Pipeline
1. **Read** (`PDFContentStream`, `PDFVectorScanner`, `PDFFont`): tokenizes the page content, tracks graphics state, decodes text with font encodings, widths and ToUnicode maps (Type1/TrueType/Type0/Type3 basics, Symbol/Zapf), records filled/stroked shapes with clipping and transparency, images and forms.
2. **Text** (`PDFTextExtractor`): glyphs → baselines → segments with font, size, color, bold/italic, underline/strikethrough (thin lines under/through text), links (PDF annotations), super/subscripts; duplicate (double-drawn) glyphs removed.
3. **Analyze** (`PDFLayoutAnalyzer`, `PDFParagraphBuilder`, `PDFColumnsAndBullets`, `PDFDrawingsAndTextTables`):
   - Drawings (charts/diagrams with curves or slanted lines) kept whole as a picture, labels included.
   - **Tables** from ruling lines (merged cells detected from missing lines) and from aligned text without lines (including shaded rows).
   - **Boxes**: colored areas with optional borders/accent strip become one-cell tables.
   - **Paragraphs**, headings (by size ranking), bulleted/numbered lists (also bullets drawn as shapes), alignment, indents, line height, **multi-column** text (Word column sections).
   - **Headers/footers** repeated on pages, with page numbers turned into live `PAGE`/`NUMPAGES` fields and the rule line as a border.
4. **Pictures** (`PDFImageExtractor`): embedded images kept as stored (JPEG as-is, raw decoded incl. soft masks); regions rendered at high resolution for drawings.
5. **Scans**: pages that are one big picture (or whose text cannot be decoded) go through Vision OCR; a hidden OCR text layer is used when present.
6. **Write** (`DocModel`, `DocxWriter`): a real `.docx` package (styles, numbering, settings, header/footer, media, relationships), checked as well-formed XML before use.

### 7.3 Layout decisions
- One Word **section per PDF page** with its own top/bottom margin; exact line heights; spacing computed from positions; tables use cell margins, borders and row heights set from the original rule positions.
- Text wraps at the original width so line breaks match; single-line paragraphs are not narrowed, so editing behaves normally.

### 7.4 Word behaviours measured and relied on
- Exact line height puts the baseline at **80%** of the line.
- Word **ignores "space before" at the top of a page** (even after a page break), hence the per-page sections.
- Row height = height value + cell top/bottom margins + borders; shared borders count once; borders are centered on cell edges; text starts half a border-width in. The engine sets cell margins to zero and uses paragraph spacing instead.
- Compatibility mode 15 aligns the table edge with the margin.

### 7.5 Measured quality
| Test | Result |
|---|---|
| Your 5-page timetable PDF (HTML-made) | 5 pages, 100% of words, text lines within 0.3 pt on average (worst ~1 pt), layout difference ~0.4% per page |
| Four other real PDFs | Page counts match, 100% of words |
| Generated: simple text with links/underline/superscript/lists | 1 page, 100% words |
| Generated: two-column article | 1 page, 100% words (line breaks may differ slightly) |
| Generated: report with merged-cell table, callout, shaded rows, chart, photo, header/footer | 3 pages, layout difference < 1% on most pages |
| Handwritten scanned notes (10 pages) | Text recognized and editable, but pages can spill (14 Word pages) |

### 7.6 Behavior in unusual PDFs
| Situation | Result |
|---|---|
| Password-protected | Clear error; nothing written |
| Not a PDF / empty | Preflight error |
| Scanned (page is one picture) | OCR; font size fitted to each recognized line |
| Searchable scan (hidden text) | Uses the hidden text layer |
| Text that cannot be decoded | That page is read with OCR; a warning is recorded |
| Rotated text | Skipped (warning recorded) |
| Chart / diagram | Kept as a picture (text inside is not editable) |
| Mixed page sizes | Each page keeps its own size |
| Output keeps < 85% of the text | Falls back to the plain text converter |
| Unexpected failure | Falls back to the plain text converter |

---

## 8. Permissions and privacy

| Permission | Asked when | Used for | If denied |
|---|---|---|---|
| **Automation: Spotify / Music** | First time music is read or controlled | Playback info and controls | Prompt card; music for that app unavailable |
| **Automation: Notes** | First save/list of Apple Notes | Notes sync | Prompt card |
| **Automation: Chrome / Safari / Brave / Edge** | When a web player is detected | Reading the playing tab | Settings → Music shows the missing step |
| **Automation: Word / Excel / PowerPoint / Pages / Numbers / Keynote** | First conversion that needs the app | Converting | Message with button to System Settings; built-in fallback where one exists |
| **Calendar (full access)** | First calendar use | Show/add/delete events | Explanation card |
| **Notifications** | When alerts/timers are enabled | Event alerts, timer end | Warning in Settings → Calendar |
| **Location (when in use)** | Only if local weather is chosen | Weather | Falls back to the chosen city |
| **Files** | Only the files you drop/add | Tray and conversions | — |

Privacy facts: no telemetry or analytics; no accounts; notes, clipboard history and tray files stay on the Mac; network lookups are listed in §2.3; conversions are fully local (Office conversions are done by the Office apps on your Mac).

---

## 9. Performance notes
- Animated music bars use Core Animation layers; driving them from SwiftUI re-laid out the whole window each frame, so they were moved out.
- SwiftUI `TimelineView`/animations on large views cause full layout each tick; the app publishes state only on real changes.
- Calendar strip uses manual frame-by-frame momentum (no spring animations) to stay smooth.
- PDF → Word reads each page once; a 5-page document converts in well under a second plus the `.docx` packaging; OCR dominates for scans. Conversions run off the main thread and are cancellable.
- CPU, memory and disk use were measured and the biggest costs removed in v2; no regressions were found in the final smoke test.

---

## 10. Testing and validation

| What | How |
|---|---|
| **PDF → Word quality** | `scripts/pdf-docx-check/run.sh`: converts PDFs, opens the `.docx` in **Microsoft Word**, exports to PDF, compares page count, words kept, per-page layout difference and per-line position error; writes side-by-side pictures |
| **Other conversions** | `scripts/conversion-edge-check/run.sh`: metadata, multi-page TIFF, empty/damaged/locked files, CSV encodings, Excel number formats, Markdown, HTML encoding, Excel and Word routes |
| **Regression harness** | A 36-route run over real images, documents, spreadsheets and PDFs (outside the repo) — all routes pass |
| **In-app** | Tray conversions driven on the real notch: progress, Cancel, failure messages, results appearing as cards |
| **Full smoke test** | Every page and setting exercised in v2 |

---

## 11. Known limitations and not done

- **Not released:** v2 is not committed, tagged or published. Release packaging needs Xcode (or a `lipo` step).
- **Untested routes:** Pages, Numbers and Keynote conversions could not be exercised on the development Mac (those apps did not respond to scripted commands); PowerPoint → PDF was verified earlier but not in the latest round.
- **PDF → Word:** handwriting is recognized poorly and long scans may spill pages; text inside charts/diagrams is not editable; rotated text is skipped; column line breaks can differ slightly from the original; shaded rows in borderless tables can be slightly misaligned; nested tables are not rebuilt.
- **Pictures:** animated GIFs keep only the first frame; several pictures cannot be merged into one PDF.
- **Spreadsheets:** currency symbols and thousands separators are not applied in CSV; CSV dates stay text when converted to Excel.
- **Text:** plain text is set in a monospace font; HTML uses Apple's older HTML importer, so complex CSS may not match a browser.
- **Environment:** weather and artwork/lyrics need internet; a Mac without Word/Excel/PowerPoint gets simpler built-in conversions.

---

## 12. Troubleshooting

| Problem | Fix |
|---|---|
| App blocked on first launch | Right-click → Open, or `xattr -dr com.apple.quarantine /Applications/NotchCraft.app` |
| No Calendar or Automation prompt appears | Run a real app bundle (installed app or `./scripts/dev-run.sh`), not a bare `swift run` binary |
| Safari music not detected | Safari → Settings → Developer → allow JavaScript from Apple Events |
| Chrome/Brave/Edge music not detected | View → Developer → allow JavaScript from Apple Events |
| Event alerts not showing | System Settings → Notifications → NotchCraft |
| A conversion says an app "couldn't convert" | Check System Settings → Privacy & Security → Automation for NotchCraft; try again (first launch of an Office app is slow) |
| Panel looks wrong after a display change | Menu bar → Reset UI, or Restart App |
| Converted Word file looks different in Pages/other apps | Fidelity was verified in Microsoft Word; other apps may render fonts, tables or spacing differently |

---

## 13. Development history

| Stage | What happened |
|---|---|
| **v1.0.0** (released) | Notch panel, tray with drag/drop and screenshots, Apple Music mini-player, timer, clipboard/snippets, Apple Notes, weather, calendar snapshot, app launcher, menu bar, launch at login, CI and packaging |
| **v2 (in progress)** | Spotify and local/web players with latest-source-wins; synced lyrics; full calendar (panel, add/delete, alerts); slim scroll bars; smooth calendar strip; one-click navigation; Settings categories; Colourful/Simple theme; performance work; **tray file conversion** (images, PDF, Word, Excel/CSV, PowerPoint, Markdown, text, HTML); **layout-aware PDF → Word engine**; native pop-up convert menu; quality-check scripts; this documentation |
