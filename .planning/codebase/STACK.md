# Technology Stack

**Analysis Date:** 2026-04-27

## Languages

**Primary:**
- Swift 6.0+ - Application code, all source targets

**Build Definition:**
- Swift tools version: 6.2

## Runtime

**Environment:**
- macOS 26.0 or later (minimum requirement)

**Package Manager:**
- Swift Package Manager (SPM)
- Lockfile: `Package.swift` (swift-tools-version: 6.2)

## Frameworks

**Core UI:**
- SwiftUI - All user interface code
- AppKit - Native macOS window management, menus, and integration (NSWindow, WKWebView, Process tap)

**Web & Playback:**
- WebKit (`WKWebView`) - Embedded browser for DRM-protected YouTube Music playback and authentication
- Web Extensions API (`WKWebExtensionController`, `WKWebExtensionContext`) - Browser extension support for enhanced web functionality (macOS 14.0+)

**Audio:**
- AVAudioEngine - Core Audio engine for playback
- AudioToolbox - Core Audio process tap for system-wide EQ via tap on macOS 14.2+

**AI/ML:**
- FoundationModels (macOS 26.0+) - On-device language models for:
  - Natural language command parsing
  - Lyrics explanation and analysis
  - Queue description generation
  - Playlist refinement

**Authentication & Security:**
- Security framework - Keychain storage for credentials and session tokens
- CryptoKit - Cryptographic operations (SHA256 for request signing)

**Scripting & Automation:**
- AppleScript - AppleScript support (OSAKit). Kaset exposes scripting interface via `.sdef` definition file
- User Notifications - Track change notifications

**Concurrency:**
- Swift Concurrency (`async`/`await`) - Strict concurrency (Swift 6 language mode enabled)
- Task-based state management

**Testing:**
- Swift Testing - Unit tests using `@Test` macro
- XCTest - UI test support via KasetUITests.xcodeproj

## Key Dependencies

**External:**
- `Sparkle` (2.8.1+) - macOS application auto-update framework
  - Configured via `Info.plist` with feed URL pointing to `appcast.xml`
  - Automatic checks enabled: every 24 hours by default

**Standard Library:**
- Foundation - Core networking, JSON decoding, file I/O
- Observation - SwiftUI data binding via `@Observable` and `@MainActor`
- os.Logger - Unified logging (DiagnosticsLogger wrapper)

## Configuration

**Environment:**
- Test mode environment variables:
  - `UI_TEST_MODE` - Enables UI test mode
  - `SKIP_AUTH` - Bypasses authentication in tests
  - `XCTestConfigurationFilePath` - Set by XCTest framework
  - `SWIFT_TESTING_ENABLED` - Set by Swift Testing
- Last.fm configuration:
  - `KASET_LASTFM_WORKER_URL` - Optional environment variable for Last.fm Cloudflare Worker endpoint
  - Falls back to `Info.plist` key `LastFMWorkerURL` if env var not set
  - Default: `https://kaset-lastfm.sozercan.workers.dev` (placeholder if not configured)

**Build:**
- `.swiftformat` - Code formatting rules with `--self insert` for strict self reference
- `.swiftlint.yml` - Linting rules (strict mode)
- `Package.swift` - SPM package definition with strict concurrency enabled
  - All targets use `enableExperimentalFeature("StrictConcurrency")`
  - Language mode set to Swift 6 for all targets

**App Configuration:**
- `Info.plist` - Contains:
  - Sparkle auto-update feed URL: `https://raw.githubusercontent.com/sozercan/kaset/main/appcast.xml`
  - Public EdDSA key for Sparkle signature verification
  - URL scheme registration: `kaset://` for deep linking
  - AppleScript support with `.sdef` definition file
  - Audio and screen capture usage descriptions (for Core Audio process tap)
- `Kaset.entitlements` - macOS app sandbox entitlements

**Updates:**
- appcast.xml - Sparkle update feed (RSS format with Sparkle extensions)
- Update feed URL: `https://raw.githubusercontent.com/sozercan/kaset/main/appcast.xml`

## Platform Requirements

**Development:**
- Swift 6.0+
- macOS SDK for target platform (26.0+)
- Xcode 16+ (recommended for Swift 6 and Foundation Models support)

**Production:**
- macOS 26.0 or later
- Google account for YouTube Music Premium authentication
- Deployment: GitHub Releases as DMG (unsigned, can be verified via `xattr` to clear quarantine)
- Distribution: Homebrew formula available (`sozercan/repo/kaset`)

## Architecture Notes

- **Strict Concurrency:** All targets compiled with `StrictConcurrency` experimental feature enabled
- **`@MainActor` enforcement:** All UI-related classes marked with `@MainActor`
- **WebView data storage:** Uses persistent `WKWebsiteDataStore.default()` with Keychain backup for authentication cookies
- **Test compatibility:** Separate UI test target (`KasetUITests`) with mock authentication support
- **API caching:** Integrated cache layer for YouTube Music API responses (configurable TTL per content type)

---

*Stack analysis: 2026-04-27*
