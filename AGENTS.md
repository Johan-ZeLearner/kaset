# AGENTS.md

Guidance for AI coding assistants working on this repository.

## Role

You are a Senior Swift Engineer specializing in SwiftUI, Swift Concurrency, and macOS development. Your code must adhere to Apple's Human Interface Guidelines. Target **Swift 6.0+** and **macOS 26.0+**.

Kaset is a native macOS YouTube Music client (Swift/SwiftUI) using a hidden WebView for DRM playback and `YTMusicClient` API calls for all data fetching.

## Critical Rules

> 🚨 **NEVER leak secrets, cookies, API keys, or tokens** — Under NO circumstances include real cookies, authentication tokens, API keys, SAPISID values, or any sensitive credentials in code, comments, logs, documentation, test fixtures, or any output. Always use placeholder values like `"REDACTED"`, `"mock-token"`, or `"test-cookie"`. **Violation of this rule is a critical security incident.**

> ⚠️ **ALWAYS confirm before running UI tests** — UI tests launch the app and can be disruptive. Ask the human for permission before executing any UI test.

> ⚠️ **No Third-Party Frameworks** — Do not introduce third-party dependencies without asking first.

> ⚠️ **Prefer API over WebView** — Always use `YTMusicClient` API calls when functionality exists. Only use WebView for playback (DRM-protected audio) and authentication.

> 🔧 **Improve API Explorer, Don't Write One-Off Scripts** — When exploring or debugging API-related functionality, **always enhance `Sources/APIExplorer/main.swift`** instead of writing temporary scripts.

> 📝 **Document Architectural Decisions** — For significant design changes, create an ADR in `docs/adr/`.

> ⌨️ **Preserve Standard macOS Shortcuts** — Do not override standard app/window shortcuts such as `⌘M`, `⌘W`, `⌘Q`, `⌘H`, or `⌘,` unless the human explicitly asks for it. When adding media shortcuts, prefer native macOS and Apple Music conventions, and update `docs/keyboard-shortcuts.md`.

## Build & Code Quality

```bash
# Build
swift build

# Unit Tests (never combine with UI tests)
swift test --skip KasetUITests

# Lint & Format
swiftlint --strict && swiftformat .
```

Default local workflow is CLI-first: use the commands above for day-to-day verification, and escalate to Xcode/`xcodebuild` only for simulator, UI, or runtime debugging, screenshots, or scheme-specific investigation.

> ⚠️ **SwiftFormat `--self insert` rule**: The project uses `--self insert` in `.swiftformat`. This means:
> - In static methods, call other static methods with `Self.methodName()` (not bare `methodName()`)
> - In instance methods, use `self.property` explicitly
>
> Always run `swiftformat .` before completing work to auto-fix these issues.

## API Discovery

> ⚠️ **MANDATORY**: Before implementing ANY feature that requires a new or modified API call, you MUST explore the endpoint first using `swift run api-explorer`. Do NOT guess or assume API response structures.

```bash
swift run api-explorer auth          # Check auth status
swift run api-explorer list          # List known endpoints
swift run api-explorer browse FEmusic_home -v  # Explore with verbose output
```

Put repeatable, repo-specific workflows in `.agents/skills/` so `AGENTS.md` stays focused on repo-wide rules.

## Coding Rules

These are project-specific rules that differ from standard Swift/SwiftUI conventions:

| ❌ Avoid | ✅ Use | Why |
|----------|--------|-----|
| `print()` | `DiagnosticsLogger` | Project-specific logging |
| `.background(.ultraThinMaterial)` | `.glassEffect()` | macOS 26+ Liquid Glass |
| `DispatchQueue` | Swift concurrency (`async`/`await`) | Strict concurrency policy |
| Force unwraps (`!`) | Optional handling or `guard` | Project policy |

- Mark `@Observable` classes with `@MainActor`
- Use Swift Testing (`@Test`, `#expect`) for all new unit tests
- Throw `YTMusicError.authExpired` on HTTP 401/403
- Use `.task` instead of `.onAppear { Task { } }`
- See `docs/common-bug-patterns.md` for concurrency anti-patterns and pre-submit checklists

## Task Planning

For non-trivial tasks: **Research → Plan → Get approval → Implement → QA**. Run `swift build` continuously during implementation. If things go wrong, revert and re-scope rather than patching.

<!-- GSD:project-start source:PROJECT.md -->
## Project

**Kaset**

Kaset is a native macOS YouTube Music client (Swift 6 / SwiftUI, macOS 26+) that uses a hidden `WKWebView` for DRM-protected audio playback and `YTMusicClient` for all data fetching. Today it relies on macOS-level audio output, so external speakers only work when the user's gear supports AirPlay.

**Core Value:** A first-class native macOS YouTube Music experience that **also reaches the user's actual home audio gear** — including Sonos systems that don't speak AirPlay.

### Constraints

- **Tech stack**: Swift 6.0+ / SwiftUI / macOS 26+ — locked by `Package.swift` and `CLAUDE.md`
- **Dependencies**: No new third-party Swift packages without explicit approval — per `CLAUDE.md`
- **Coding rules**: No `print()` (use `DiagnosticsLogger`), no `DispatchQueue` (Swift Concurrency only), no force unwraps, no `.background(.ultraThinMaterial)` (use `.glassEffect()`), `@MainActor` on `@Observable` classes — per `CLAUDE.md`
- **Test hardware**: Sonos S1 only — narrows protocol surface to legacy UPnP/SOAP
- **Audio source**: DRM-protected WebView audio — rules out direct stream URL handoff (the trick Spotify uses)
- **Privacy / entitlements**: Audio + screen capture usage descriptions already declared in `Info.plist`; tap-based capture may require additional sandbox concessions
- **API parity**: API > WebView always (per `CLAUDE.md`); but for *audio*, WebView is the only path Kaset has
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages
- Swift 6.0+ - Application code, all source targets
- Swift tools version: 6.2
## Runtime
- macOS 26.0 or later (minimum requirement)
- Swift Package Manager (SPM)
- Lockfile: `Package.swift` (swift-tools-version: 6.2)
## Frameworks
- SwiftUI - All user interface code
- AppKit - Native macOS window management, menus, and integration (NSWindow, WKWebView, Process tap)
- WebKit (`WKWebView`) - Embedded browser for DRM-protected YouTube Music playback and authentication
- Web Extensions API (`WKWebExtensionController`, `WKWebExtensionContext`) - Browser extension support for enhanced web functionality (macOS 14.0+)
- AVAudioEngine - Core Audio engine for playback
- AudioToolbox - Core Audio process tap for system-wide EQ via tap on macOS 14.2+
- FoundationModels (macOS 26.0+) - On-device language models for:
- Security framework - Keychain storage for credentials and session tokens
- CryptoKit - Cryptographic operations (SHA256 for request signing)
- AppleScript - AppleScript support (OSAKit). Kaset exposes scripting interface via `.sdef` definition file
- User Notifications - Track change notifications
- Swift Concurrency (`async`/`await`) - Strict concurrency (Swift 6 language mode enabled)
- Task-based state management
- Swift Testing - Unit tests using `@Test` macro
- XCTest - UI test support via KasetUITests.xcodeproj
## Key Dependencies
- `Sparkle` (2.8.1+) - macOS application auto-update framework
- Foundation - Core networking, JSON decoding, file I/O
- Observation - SwiftUI data binding via `@Observable` and `@MainActor`
- os.Logger - Unified logging (DiagnosticsLogger wrapper)
## Configuration
- Test mode environment variables:
- Last.fm configuration:
- `.swiftformat` - Code formatting rules with `--self insert` for strict self reference
- `.swiftlint.yml` - Linting rules (strict mode)
- `Package.swift` - SPM package definition with strict concurrency enabled
- `Info.plist` - Contains:
- `Kaset.entitlements` - macOS app sandbox entitlements
- appcast.xml - Sparkle update feed (RSS format with Sparkle extensions)
- Update feed URL: `https://raw.githubusercontent.com/sozercan/kaset/main/appcast.xml`
## Platform Requirements
- Swift 6.0+
- macOS SDK for target platform (26.0+)
- Xcode 16+ (recommended for Swift 6 and Foundation Models support)
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
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Naming Patterns
- Swift files use PascalCase (e.g., `PlayerService.swift`, `CommandBarView.swift`)
- Protocol files group protocols with `// MARK:` comments (e.g., `Protocols.swift` contains `WebKitManagerProtocol`, `YTMusicClientProtocol`, `AuthServiceProtocol`, `PlayerServiceProtocol`)
- Test files match source file names with "Tests" suffix (e.g., `PlayerService.swift` → `PlayerServiceTests.swift`)
- Fixture and helper files use descriptive names (e.g., `MockYTMusicClient.swift`, `TestFixtures.swift`)
- camelCase for all functions and methods
- Use verb-based names for actions: `loadHome()`, `playSong()`, `updatePlaybackState()`
- Prefix boolean properties with `is` or `has`: `isPlaying`, `hasVideo`, `hasMoreSections`
- Query functions use get prefix only when disambiguating: `getSong()`, `getSAPISID()`
- camelCase for all variable names
- Descriptive names preferred over abbreviations: `currentTrack` not `curTrack`, `userDefaults` not `ud`
- Mark mutable state with leading underscore in `@State` declarations: `@State private var _viewModel`
- Use `self` prefix explicitly in instance methods and `Self` in static methods (enforced by SwiftFormat `--self insert` rule)
- PascalCase for all type names (structs, classes, enums, protocols)
- Prefix protocols with Protocol suffix when describing behavior: `YTMusicClientProtocol`, `PlayerServiceProtocol`
- Enum cases use camelCase: `.playing`, `.paused`, `.idle`
- Generic type parameters use single uppercase letters or descriptive names: `T`, `Element` or `Value`
## Code Style
- Tool: SwiftFormat with custom configuration in `.swiftformat`
- Swift version: 6.0
- Indentation: 4 spaces
- Line endings: LF (Unix)
- No trailing whitespace
- Brace style: Allman false (opening brace on same line)
- Always use explicit `self` in instance methods (enforced by `--self insert`)
- Always use `Self` in static methods (enforced by `--self insert`)
- Tool: SwiftLint with configuration in `.swiftlint.yml`
- Strict mode enforced: `swiftlint --strict`
- Key rules:
## Import Organization
- No custom path aliases used in project
- All imports use full module names
## Error Handling
- Create `YTMusicError` enum cases for specific error conditions in `Sources/Kaset/Models/YTMusicError.swift`
- Throw `YTMusicError.authExpired` on HTTP 401/403 responses
- Throw `YTMusicError.networkError(underlying: URLError)` for network failures
- Throw `YTMusicError.parseError(message: String)` for JSON/response parsing failures
- Include `errorDescription`, `recoverySuggestion`, `debugDescription`, and `requiresReauth` properties for user-facing error handling
- Use `#expect(throws:)` in unit tests to validate error throwing behavior
- Handle `CancellationError` separately from other error types (see `docs/common-bug-patterns.md`)
- Auth errors set `needsReauth` flag and trigger login sheet
- Network errors suggest checking connection and retrying
- Parse errors suggest trying again or reporting if persistent
- Playback errors suggest trying a different track
## Logging
- Use `DiagnosticsLogger.{category}` where category matches subsystem (e.g., `DiagnosticsLogger.api`, `DiagnosticsLogger.player`, `DiagnosticsLogger.auth`)
- `.info()` for major operations: "Loading library", "Playlist loaded with X tracks"
- `.debug()` for state transitions and detailed flow: "Queue updated", "Preserving snapshot"
- `.error()` reserved for unexpected failures that may indicate bugs
- Log at operation start and completion, not in tight loops
- Include relevant IDs in log messages: "Loading playlist: \(id)", not just "Loading playlist"
- Include counts in completion messages: "Loaded X tracks" not "Loaded tracks"
## Comments
- Comment public APIs: All public types, functions, and properties have documentation comments
- Comment complex algorithms: If business logic is non-obvious, explain the "why" not the "what"
- Comment workarounds: Mark with `FIXME:` or `TODO:` if temporary or incomplete
- Mark known limitations: Note conditions under which code may fail
- Use triple-slash `///` documentation comments for public APIs
- Include parameter descriptions and return value descriptions
- Mark parameters as `- Parameter name: Description`
- Mark return values as `- Returns: Description`
- Add availability attributes when applicable: `@available(macOS 26.0, *)`
## Function Design
- Target: Under 30 lines for most functions
- Hard limit: SwiftLint warns at 100 lines, errors at 150 lines for function bodies
- Break large functions into smaller helper functions with clear responsibilities
- Limit: Aim for fewer than 6 parameters
- Use structs for logically related parameters rather than many individual parameters
- Mark closures as trailing closures when they're the last parameter
- Use default parameter values conservatively for clarity
- Return optional (`T?`) when value may not exist
- Return `Result<T, E>` for operations that may fail with specific error types
- Return `Void` explicitly or use implicit return for simple expressions
- Async functions use `async throws` pattern: signature states that errors may be thrown
## Module Design
- Services export protocol types, not concrete implementations
- ViewModels marked with `@Observable @MainActor` and exported for dependency injection
- Models (structs, enums) export concrete types
- Internal helpers marked `private` or `fileprivate`
- Not used in this project — each file has a single primary type
- Avoid creating `__all__.swift` or re-export modules
- Use `// MARK: - SectionName` to organize code into logical sections
- Order: Type definition, `// MARK: - Initializers`, `// MARK: - State`, `// MARK: - Lifecycle`, `// MARK: - Public Methods`, `// MARK: - Private Methods`, nested types at end
- Keep mark sections focused (1-10 items per section)
## Concurrency
- Use `async`/`await` exclusively — no `DispatchQueue`
- Mark UI classes with `@MainActor` when they interact with SwiftUI
- Use `.task` modifier instead of `.onAppear { Task { } }` for lifecycle-managed async operations
- Use `@Binding` for two-way state sync with parent views
- Use `Environment` for injecting dependencies down view hierarchy
- Cancel tasks explicitly in deallocators or when state changes
## Accessibility
- All icon-only buttons must have `.accessibilityLabel()`
- Use `.accessibilityIdentifier()` for UI test targeting
- Provide meaningful descriptions for complex UI patterns
- Respect system accessibility settings (e.g., `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`)
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## System Overview
```text
```
## Component Responsibilities
| Component | Responsibility | File |
|-----------|----------------|------|
| **KasetApp** | App entry point, service initialization, environment injection | `Sources/Kaset/KasetApp.swift` |
| **MainWindow** | Root UI container, view caching, tab navigation, viewport management | `Sources/Kaset/Views/MainWindow.swift` |
| **Sidebar** | Navigation menu, account switcher, favorites sidebar | `Sources/Kaset/Views/Sidebar.swift` |
| **PlayerBar** | Transport controls, progress slider, now playing info | `Sources/Kaset/Views/PlayerBar.swift` |
| **ViewModels** | State management, API client calls, pagination, data fetching | `Sources/Kaset/ViewModels/` |
| **YTMusicClient** | API HTTP requests, response parsing, pagination tokens | `Sources/Kaset/Services/API/YTMusicClient.swift` |
| **PlayerService** | Playback control via WebView, queue management, state tracking | `Sources/Kaset/Services/Player/PlayerService.swift` |
| **AuthService** | Login state machine, session validation | `Sources/Kaset/Services/Auth/AuthService.swift` |
| **WebKitManager** | Cookie management, persistent WKWebsiteDataStore, Keychain backup | `Sources/Kaset/Services/WebKit/WebKitManager.swift` |
| **Data Models** | Song, Playlist, Album, Artist, Podcast, etc. (Codable structs) | `Sources/Kaset/Models/` |
## Pattern Overview
- **Strict Concurrency**: Swift 6 concurrency enforced; all main-thread services marked `@MainActor`
- **Protocol-Driven**: Concrete services implement protocols for testability (`YTMusicClientProtocol`, `WebKitManagerProtocol`, etc.)
- **Dependency Injection**: Views receive services via `@Environment`, ViewModels accept clients via init parameters
- **Singleton Pattern**: Key services (`WebKitManager`, `PlayerService`, `EqualizerService`) are shared singletons accessed via `.shared`
- **Observable State**: `@Observable` macro on services enables reactive SwiftUI view updates without `@Published`
## Layers
- Purpose: Render UI and manage view state
- Location: `Sources/Kaset/Views/`, `Sources/Kaset/ViewModels/`
- Contains: SwiftUI views, @Observable ViewModels, state machines
- Depends on: Services, Models, Environment values
- Used by: SwiftUI rendering system, system events
- Purpose: Business logic, API calls, playback control, authentication
- Location: `Sources/Kaset/Services/`
- Contains: YTMusicClient, PlayerService, AuthService, WebKitManager, EqualizerService, NotificationService, etc.
- Depends on: Models, system frameworks (WebKit, AVFoundation, AppKit)
- Used by: Views and ViewModels via @Environment
- Purpose: Data structures representing domain entities
- Location: `Sources/Kaset/Models/`
- Contains: Codable structs (Song, Playlist, Artist, Album, Podcast, etc.)
- Depends on: Foundation
- Used by: Services, ViewModels, Views
- Purpose: Cross-cutting concerns
- Location: `Sources/Kaset/Utilities/`
- Contains: DiagnosticsLogger, UITestConfig, image caching, accessibility IDs
- Depends on: Foundation
- Used by: All layers
## Data Flow
### Primary Request Path (Search → Display)
- View state (text input): Local @State in SearchView
- Async data: ViewModel's @Observable properties trigger view updates
- Shared state (user login): AuthService (@Observable singleton) via @Environment
- Player state: PlayerService (@Observable singleton) via @Environment
### Playback Flow (Queue → Play)
### Authentication Flow
## Key Abstractions
- Purpose: Abstract API client for dependency injection and testing
- Examples: `YTMusicClient` (real), `MockUITestYTMusicClient` (test)
- Pattern: Each method is a typed async function returning a Model (e.g., `getHome() async throws -> HomeResponse`)
- Purpose: Abstract authentication interface
- State machine with cases: `.initializing`, `.loggedOut`, `.loggingIn`, `.loggedIn(sapisid:)`
- Used by: All services that need to know login status
- Purpose: Abstract WebKit/cookie management
- Methods: `getSAPISID()`, `getAllCookies()`, `hasAuthCookies()`, `clearAllData()`
- Used by: AuthService, YTMusicClient (for cookie-based auth)
- Purpose: Standardized async state for ViewModels
- Cases: `.idle`, `.loading`, `.loaded`, `.loadingMore`, `.error(LoadingError)`
- Used by: HomeViewModel, SearchViewModel, PlaylistDetailViewModel, etc.
- Purpose: Abstract playback control
- Operations: play, pause, seek, next, previous, addToQueue, removeFromQueue
- State: currentTrack, queue, progress, isPlaying, repeatMode, shuffleEnabled
## Entry Points
- Location: `Sources/Kaset/KasetApp.swift:25`
- Triggers: macOS app launch
- Responsibilities: 
- Location: `Sources/Kaset/Views/MainWindow.swift:7`
- Triggers: After KasetApp initializes
- Responsibilities:
- Location: Not shown (NSApplicationDelegate)
- Triggers: App lifecycle events
- Responsibilities: 
## Architectural Constraints
- **Threading:** @MainActor isolation enforced on all UI-touching services. PlayerService, AuthService, WebKitManager are main-thread only. API calls use Swift Concurrency (async/await) but callbacks always run on main thread.
- **Global state:** 
- **Circular imports:** None detected. Model → Service → View dependency flow is acyclic.
- **API Rate Limiting:** None built-in. YouTube Music's internal API does not enforce strict per-client limits.
- **WebView Lifecycle:** Singleton WKWebView is managed by AppDelegate, never deallocated during app lifetime to preserve JavaScript state and audio context.
## Anti-Patterns
### Direct print() Logging
```swift
```
### Force Unwraps (!)
```swift
```
### DispatchQueue for Async Work
```swift
```
### Weak Self Closure Cycles
```swift
```
## Error Handling
```swift
```
## Cross-Cutting Concerns
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

| Skill | Description | Path |
|-------|-------------|------|
| api-exploration | Use when a task needs a new or modified YouTube Music API call, response parser validation, authenticated endpoint investigation, or fixture capture; explore endpoints with `swift run api-explorer` before changing production code. | `.agents/skills/api-exploration/SKILL.md` |
| dev-loop-packaging | Use when you need a fresh packaged `.app` bundle, a fast build-package-relaunch loop, or a packaged runtime repro for Kaset instead of a compile-only verification. | `.agents/skills/dev-loop-packaging/SKILL.md` |
| playback-webview-debugging | Use when playback, auth recovery, queue sync, or hidden WebView state diverges from native Swift state and you need to debug the DRM playback WebView, bridge events, or cookie/auth behavior. | `.agents/skills/playback-webview-debugging/SKILL.md` |
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
