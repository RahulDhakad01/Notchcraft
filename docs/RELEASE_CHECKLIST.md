# NotchCraft v2.0.0 — Release readiness report and checklist

Prepared from a hands-on audit. Everything under **Measured** was actually run on the development Mac (Apple Silicon, macOS 26.4.1, Swift 6.2). Everything under **Not tested** was not, and is listed so nothing is assumed.

---

## 1. Verdict

| Question | Answer |
|---|---|
| Is the code ready? | Yes. Release build succeeds; the only compiler messages are 16 Swift-6-mode concurrency warnings (not errors in the current language mode); no `try!`, no force casts, one unreachable `fatalError` (a required `init(coder:)`). |
| Is the app efficient? | Yes (numbers below). No code was changed for "optimization", on purpose: you asked for zero functional or UI change. |
| Will it work on other Macs? | The build works for Apple Silicon and Intel; it ran on Apple Silicon natively and the Intel slice ran under Rosetta. M1–M5, notch and no-notch screens are handled by reading the screen's real geometry. Older macOS (14, 15) and real Intel hardware are **not tested**. |
| Is it ready to ship to "a large crowd"? | **Not yet.** One thing blocks it: the app is not signed with a **Developer ID** certificate and not **notarized**, so on other people's Macs macOS will warn or block it. See §4. |

---

## 2. Measured

### 2.1 Build
| Item | Result |
|---|---|
| Release build time (clean-ish) | ~40 s (single architecture) |
| Release binary, Apple Silicon | 6.7 MB |
| Universal app bundle (arm64 + x86_64) | 15 MB |
| `.zip` / `.dmg` | 5.6 MB / 6.2 MB |
| Warnings | 16, all "captured var in concurrently-executing code" or `Sendable` notes from the Swift 6 checker |
| Package script on this Mac | **Fixed**: the old script failed here because a universal build needs full Xcode. It now falls back to building both architectures and joining them with `lipo` |

### 2.2 CPU, memory, energy (release build, Apple Silicon)
| State | CPU | Memory (physical footprint) | Threads | Energy impact | Idle wake-ups |
|---|---|---|---|---|---|
| Collapsed, idle (1 min) | 0.0% | 7.7 MB (28 MB RSS) | 3 | 0.0 | 0 |
| Expanded on Home | ~2.2% | 51 MB (peak 52 MB) | 7 | ~2.3 (low) | 0–1 |
| Intel slice under Rosetta, collapsed | 0.1% | 33 MB | — | 0.8 | — |
| Hardened-runtime build (signed with entitlements) | starts and runs normally | — | — | — | — |

Reading this: when collapsed the app costs essentially nothing (no polling that wakes the CPU), so it will not hurt battery. Expanded, it is light. Real use adds a little for music polling, weather refresh, and calendar.

### 2.3 Disk
| What | Size / behavior |
|---|---|
| App | 15 MB (universal) |
| Settings | A few KB in `UserDefaults` |
| Tray files | Copies of dropped files in `~/Library/Application Support/NotchCraft/TrayImports/` (max 18 items listed; retention Until cleared / 5 h / 1 day). Conversion results live in `converted-xxxx` folders there and are removed with their file |
| Temporary Office scratch | Created per job inside the Office group container and deleted when the job ends (also on Cancel) |

### 2.4 Compatibility checks done
- **Notch / screen:** geometry is read from the system (`safeAreaInsets`, `auxiliaryTopLeft/RightArea`), not hard-coded, so 14"/16" Pro and 13"/15" Air notches of any generation (M1–M5) fit. Screens with no notch (external displays, older Macs) use a fixed small gap. The panel follows the screen the pointer is on.
- **Universal binary:** `lipo -info` confirms `x86_64 arm64`.
- **Intel:** x86_64 slice launched and idled correctly under Rosetta 2.
- **Upgrade from v1:** same bundle ID, so settings carry over; the old tray key (`shelfFiles`) is still read, new keys are additive.
- **Entitlements:** a new `scripts/NotchCraft.entitlements` (Apple Events, Calendars, Location) is applied by the packaging script. Without it, a hardened-runtime build would never show the Automation / Calendar prompts (this was seen earlier in the system log).

### 2.5 Changes made while preparing the release (none touch app behavior or UI)
1. `Info.plist`: version `1.0` → **2.0.0**, build `1` → **2**.
2. `scripts/package-release-app.sh`: `lipo` fallback, entitlements applied when signing, optional `NOTCHCRAFT_DIST_DIR` so a test run does not overwrite `dist/`.
3. `scripts/NotchCraft.entitlements`: new.
4. `.gitignore`: ignores the scratch folders `output/` and `tmp/`.

---

## 3. Not tested (do these before announcing)

| Not tested | Why it matters | How |
|---|---|---|
| **macOS 14 and 15** at run time | The app targets 14+; it was only run on macOS 26. The compiler enforces API availability, but visuals and permissions can differ | Test on a Mac or a macOS 14/15 VM (UTM / Tart) |
| **Real Intel Mac** | Only Rosetta was used | Borrow an Intel Mac |
| **Real M4 / M5 MacBook** (Air and Pro) | Notch size and layout read from the system, but not seen on hardware | Test on at least one 14" Pro and one Air |
| **Clean-install permission flow** | Dev machine already has permissions granted | New macOS user account, or `tccutil reset All com.notchcraft.app` |
| **Gatekeeper behavior of the final download** | Needs a signed, notarized build downloaded through a browser | See §4 |
| **Full UI pass of the final build** | The convert pop-up menu could not be hovered/clicked by the test tools; the rest was exercised earlier in v2 | Do a manual run-through (§6) |
| **Pages / Numbers / Keynote conversions** | The apps did not respond to scripted commands on the dev Mac | Test where they work, or remove those options from the first release |
| **Several displays, Spaces, fullscreen apps, sleep/wake, clamshell** | Handled in code; not verified on this run | Manual |

---

## 4. The one blocker: signing and notarization

Right now there is only an **Apple Development** certificate on this Mac. That signature is for your own devices. For people who download the app:

- Without a **Developer ID Application** certificate + **notarization**, macOS shows "cannot be opened because the developer cannot be verified" or "damaged".
- On **macOS 15 (Sequoia) and later** the old Control-click → Open workaround is gone; users must go to System Settings → Privacy & Security → **Open Anyway**, or use the Terminal command in the README. That is a poor first experience for a large audience, and the README's v1 install steps need updating.

What to do:
1. Join the **Apple Developer Program** (paid, yearly).
2. Create a **Developer ID Application** certificate in your keychain; the packaging script detects it and signs with the hardened runtime and the new entitlements.
3. Notarize and staple (one-time setup with an app-specific password or API key):
   ```bash
   xcrun notarytool submit dist/NotchCraft-macOS.zip --keychain-profile "notchcraft" --wait
   xcrun stapler staple dist/NotchCraft.app
   ```
   then rebuild the zip/dmg from the stapled app (and notarize + staple the DMG too).
4. Verify on another Mac: `spctl -a -vv -t exec NotchCraft.app` should say **accepted, source=Notarized Developer ID**.

---

### 4a. Releasing without a paid Apple account (chosen path)

The app is shipped **ad-hoc signed** (the script does this automatically when no Developer ID exists) and users bypass Gatekeeper themselves. The README now explains three ways: click-through (Open Anyway), a Terminal install with `curl` (files downloaded by `curl` are not quarantined, so no warning appears), and `xattr -dr com.apple.quarantine`.
- **Xcode is not needed.** Command Line Tools are enough; the packaging script's `lipo` fallback builds the universal app.
- **Apple Silicon is the supported target**; the universal build still includes Intel at no extra effort (best effort, untested on real hardware).
- **Permissions can be asked again after each update**, because an ad-hoc signature changes with every build. Say so in the release notes (the README does).
- Upload both `NotchCraft-macOS.zip` (used by the Terminal method) and `NotchCraft-macOS.dmg` with exactly these file names, so the `releases/latest/download/…` link keeps working.

## 5. Things to keep in mind (risks and policies)

**Permissions and first-run**
- First launch triggers several macOS prompts over time (Calendar, Automation per app, Notifications, Location). Each appears only when its feature is used. Make sure the in-app explanation cards read well.
- Screenshot auto-import reads the Screenshots folder (usually Desktop or Documents), which can show a "Files and Folders" prompt. The `Info.plist` has no custom text for Desktop/Documents access; consider adding `NSDesktopFolderUsageDescription` / `NSDocumentsFolderUsageDescription` so the prompt explains itself.
- Browser music detection needs the user to allow JavaScript from Apple Events in their browser; this is a setting only the user can change.

**Network services (third parties)**
| Service | Concern |
|---|---|
| **Open-Meteo** | Free tier is for **non-commercial** use; if you ever charge for the app, you need a licence |
| **ipapi.co** | Used for approximate location; free tier has request limits per IP; it sends the user's IP to a third party, so mention it in your privacy notes |
| **iTunes Search API** | Artwork lookup; rate-limited (about 20 requests per minute per IP) — make sure results are cached; follow Apple's usage terms |
| **LRCLIB** | Free community lyrics database; keep the polite User-Agent, consider crediting it in the app/README |
These can fail or change; the app already degrades quietly (no lyrics, no artwork), but watch for support questions.

**Legal / branding**
- The empty music state uses Spotify and Apple Music logos/tints: check each company's brand guidelines for third-party use.
- Lyrics are fetched from a third party; you are not storing or redistributing them, but you are displaying them.
- Add a short privacy statement (the README has one) and keep the "no telemetry" claim true.

**Quality and support**
- There is **no crash reporting**. For a large audience, ask users to attach `Console` logs or add a "Copy diagnostics" button later; set up GitHub Issues templates.
- There is **no auto-update**. Users must download new versions; consider adding Sparkle later and say so in the notes.
- The PDF → Word engine was verified against Microsoft Word; other Word processors may render slightly differently. Handwritten scans and charts are limits, documented in `PROJECT_DOCUMENTATION.md` §7 and §11.
- Conversions that use Word / Excel / PowerPoint need those apps and an Automation approval; without them the built-in route is plainer. Tell users.
- Upgrading: ask v1 users to quit v1 before replacing the app. Settings and tray carry over.

**Engineering follow-ups (not required for 2.0.0)**
- 16 concurrency warnings will become errors if the project moves to Swift 6 language mode.
- `AppState.swift` is ~3,900 lines; splitting it would help maintenance but is risky now.
- Expanded memory is ~51 MB (artwork and view caches); fine, could be trimmed later.
- CI (`.github/workflows/build.yml`) builds the universal package; it does not sign or notarize.

---

## 6. Release flow (in order)

1. **Freeze**: merge/commit v2 work. (Nothing is committed yet: `Conversion/`, music, calendar and other new files are untracked.) Commit in logical chunks; do **not** commit `output/`, `tmp/`, `dist/`, `.build/`.
2. **Version**: `Info.plist` is already 2.0.0 (build 2). Add a `CHANGELOG`/release notes (v2 highlights from `PROJECT_DOCUMENTATION.md` §13).
3. **Clean build and tests**:
   ```bash
   swift build -c release
   scripts/pdf-docx-check/run.sh
   scripts/conversion-edge-check/run.sh
   ```
4. **Manual pass** on the final app (about 20 minutes): open/close notch, every page, play music in Spotify/Music/Chrome, calendar add/delete event, timer, notes, snippets, drop files into the tray and convert one of each type, Cancel a conversion, quit and relaunch (settings and tray kept), launch at login on/off, display change and sleep/wake.
5. **Package** with a Developer ID certificate: `./scripts/package-release-app.sh` (universal, hardened runtime, entitlements).
6. **Notarize + staple** (§4), re-create zip/dmg from the stapled app, run `spctl` check.
7. **Test the download** on a second Mac (and a macOS 14/15 Mac if possible): download from a browser, open, grant permissions on a clean account.
8. **Checksums**: `shasum -a 256 NotchCraft-macOS.dmg NotchCraft-macOS.zip` and publish them.
9. **Tag and publish**: `git tag v2.0.0`, push, create the GitHub Release (keep v1.0.0 listed), upload the DMG and zip, paste release notes, link known limitations.
10. **README**: update the install steps for macOS 15+ (no Control-click Open), version badge, screenshots/GIFs of v2.
11. **After release**: watch Issues for permission and compatibility reports; keep a short FAQ (the troubleshooting table in `PROJECT_DOCUMENTATION.md` §12 is a start).

---

## 7. Support matrix to put in the release notes

| | Status |
|---|---|
| macOS 26 (Tahoe) | Tested (development Mac) |
| macOS 15 (Sequoia) | Expected to work; verify |
| macOS 14 (Sonoma) | Minimum; verify |
| Apple Silicon M1 – M5 | Supported (universal build); notch measured from the system |
| Intel Macs | Supported (universal build); ran under Rosetta, verify on hardware |
| Notched MacBooks / non-notch screens / external displays | Supported |
