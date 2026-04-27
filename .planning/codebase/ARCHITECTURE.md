<!-- refreshed: 2026-04-27 -->
# Architecture

**Analysis Date:** 2026-04-27

## System Overview

Kaset is a native macOS YouTube Music client built with Swift/SwiftUI that uses a hidden WebKit browser for DRM-protected audio playback and YTMusicClient for all data operations.

```text
┌──────────────────────────────────────────────────────────────────────┐
│                         SwiftUI Views Layer                          │
│    MainWindow, Sidebar, PlayerBar, HomeView, SearchView, etc.       │
│              (16,580 lines across 49 view files)                     │
└────────────┬─────────────────────────┬──────────────────┬───────────┘
             │                         │                  │
             ▼                         ▼                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    ViewModels + State Management                     │
│    HomeViewModel, SearchViewModel, PlaylistDetailViewModel, etc.    │
│         (3,137 lines / @Observable @MainActor pattern)              │
└────────────┬────────────────────────┬──────────────────┬───────────┘
             │                        │                  │
             ▼                        ▼                  ▼
┌──────────────────────────┬──────────────────────┬──────────────────┐
│  API Layer (4,880 LOC)   │  Auth Layer          │  Player Layer    │
│  YTMusicClient (API      │  AuthService         │  PlayerService   │
│  calls + parsers)        │  WebKitManager       │  (media control) │
│                          │  (cookies + WebKit)  │                  │
└──────────────┬───────────┴──────────┬───────────┴────────┬──────────┘
               │                      │                    │
               ▼                      ▼                    ▼
┌──────────────────────────┬──────────────────────┬──────────────────┐
│  YouTube Music           │  macOS System        │  Hidden           │
│  Internal API            │  Keychain Storage    │  WKWebView       │
│  (REST endpoints)        │  + Cookie Backup     │  (playback only) │
└──────────────────────────┴──────────────────────┴──────────────────┘
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

**Overall:** Service-Based MVC with @Observable singletons

**Key Characteristics:**
- **Strict Concurrency**: Swift 6 concurrency enforced; all main-thread services marked `@MainActor`
- **Protocol-Driven**: Concrete services implement protocols for testability (`YTMusicClientProtocol`, `WebKitManagerProtocol`, etc.)
- **Dependency Injection**: Views receive services via `@Environment`, ViewModels accept clients via init parameters
- **Singleton Pattern**: Key services (`WebKitManager`, `PlayerService`, `EqualizerService`) are shared singletons accessed via `.shared`
- **Observable State**: `@Observable` macro on services enables reactive SwiftUI view updates without `@Published`

## Layers

**Presentation (Views + ViewModels):**
- Purpose: Render UI and manage view state
- Location: `Sources/Kaset/Views/`, `Sources/Kaset/ViewModels/`
- Contains: SwiftUI views, @Observable ViewModels, state machines
- Depends on: Services, Models, Environment values
- Used by: SwiftUI rendering system, system events

**Service Layer:**
- Purpose: Business logic, API calls, playback control, authentication
- Location: `Sources/Kaset/Services/`
- Contains: YTMusicClient, PlayerService, AuthService, WebKitManager, EqualizerService, NotificationService, etc.
- Depends on: Models, system frameworks (WebKit, AVFoundation, AppKit)
- Used by: Views and ViewModels via @Environment

**Model/Data Layer:**
- Purpose: Data structures representing domain entities
- Location: `Sources/Kaset/Models/`
- Contains: Codable structs (Song, Playlist, Artist, Album, Podcast, etc.)
- Depends on: Foundation
- Used by: Services, ViewModels, Views

**Utilities:**
- Purpose: Cross-cutting concerns
- Location: `Sources/Kaset/Utilities/`
- Contains: DiagnosticsLogger, UITestConfig, image caching, accessibility IDs
- Depends on: Foundation
- Used by: All layers

## Data Flow

### Primary Request Path (Search → Display)

1. User types in SearchView (`Sources/Kaset/Views/SearchView.swift`)
2. View updates `@State` which triggers SearchViewModel.search() (`Sources/Kaset/ViewModels/SearchViewModel.swift`)
3. ViewModel calls `client.search(query:)` (YTMusicClientProtocol) (`Sources/Kaset/Services/API/YTMusicClient.swift:241`)
4. YTMusicClient:
   - Builds HTTP request with authenticated cookie header
   - Makes POST to `https://music.youtube.com/youtubei/v1/search`
   - Parses response via `SearchResponseParser` (`Sources/Kaset/Services/API/Parsers/SearchResponseParser.swift`)
5. ViewModel receives SearchResponse, updates `loadingState` and `results` @Observable state
6. SwiftUI re-renders SearchView with new results

**State Management:**
- View state (text input): Local @State in SearchView
- Async data: ViewModel's @Observable properties trigger view updates
- Shared state (user login): AuthService (@Observable singleton) via @Environment
- Player state: PlayerService (@Observable singleton) via @Environment

### Playback Flow (Queue → Play)

1. User clicks "Play" on a song
2. PlayerBar/Song action calls `playerService.play(videoId:)`
3. PlayerService (`Sources/Kaset/Services/Player/PlayerService.swift:200+`):
   - Updates `state` = `.loading`
   - Sends message to hidden WebView to load player and play videoId
   - WebView uses DRM-protected YouTube player for audio
4. WebView notifies PlayerService of playback events via JavaScript bridge
5. PlayerService updates `currentTrack`, `isPlaying`, `progress` (Observable)
6. Views re-render with updated now-playing info

### Authentication Flow

1. User clicks "Login"
2. AuthService.startLogin() sets `state` = `.loggingIn`
3. LoginSheet appears showing LoginWebView (hidden WKWebView pointed at music.youtube.com)
4. User logs into YouTube in WebView
5. WebKitManager observes HTTPCookieStore for SAPISID/`__Secure-3PAPISID` cookie
6. When auth cookie found:
   - AuthService.completeLogin() sets `state` = `.loggedIn(sapisid:)`
   - WebKitManager backs up cookie to macOS Keychain (`Sources/Kaset/Services/WebKit/WebKitManager+Cookies.swift:52`)
7. On app restart, WebKitManager restores cookies from Keychain to WebKit datastore (startup restore)

## Key Abstractions

**YTMusicClientProtocol:**
- Purpose: Abstract API client for dependency injection and testing
- Examples: `YTMusicClient` (real), `MockUITestYTMusicClient` (test)
- Pattern: Each method is a typed async function returning a Model (e.g., `getHome() async throws -> HomeResponse`)

**AuthServiceProtocol:**
- Purpose: Abstract authentication interface
- State machine with cases: `.initializing`, `.loggedOut`, `.loggingIn`, `.loggedIn(sapisid:)`
- Used by: All services that need to know login status

**WebKitManagerProtocol:**
- Purpose: Abstract WebKit/cookie management
- Methods: `getSAPISID()`, `getAllCookies()`, `hasAuthCookies()`, `clearAllData()`
- Used by: AuthService, YTMusicClient (for cookie-based auth)

**LoadingState:**
- Purpose: Standardized async state for ViewModels
- Cases: `.idle`, `.loading`, `.loaded`, `.loadingMore`, `.error(LoadingError)`
- Used by: HomeViewModel, SearchViewModel, PlaylistDetailViewModel, etc.

**PlayerServiceProtocol:**
- Purpose: Abstract playback control
- Operations: play, pause, seek, next, previous, addToQueue, removeFromQueue
- State: currentTrack, queue, progress, isPlaying, repeatMode, shuffleEnabled

## Entry Points

**KasetApp:**
- Location: `Sources/Kaset/KasetApp.swift:25`
- Triggers: macOS app launch
- Responsibilities: 
  - Initialize all singletons (AuthService, WebKitManager, PlayerService, YTMusicClient)
  - Wire dependencies (PlayerService.setYTMusicClient, brandIdProvider closure)
  - Create environment for views
  - Start startup tasks (check login, fetch accounts, warm up ML models)

**MainWindow:**
- Location: `Sources/Kaset/Views/MainWindow.swift:7`
- Triggers: After KasetApp initializes
- Responsibilities:
  - Create NavigationSplitView (Sidebar + content area)
  - Manage tab navigation (Home, Search, Library, Explore, etc.)
  - Cache ViewModels to persist state across tab switches
  - Handle keyboard shortcuts (⌘K for search, ⌘; for command bar)

**AppDelegate:**
- Location: Not shown (NSApplicationDelegate)
- Triggers: App lifecycle events
- Responsibilities: 
  - Manage main window lifecycle
  - Queue restoration on app restart
  - Dock menu handling

## Architectural Constraints

- **Threading:** @MainActor isolation enforced on all UI-touching services. PlayerService, AuthService, WebKitManager are main-thread only. API calls use Swift Concurrency (async/await) but callbacks always run on main thread.
- **Global state:** 
  - `WebKitManager.shared` (WKWebsiteDataStore singleton)
  - `PlayerService.shared` (for AppleScript access)
  - `EqualizerService.shared` (audio processing)
  - `FavoritesManager.shared` (liked songs cache)
  - Accessed via `@Environment` in views for testability
- **Circular imports:** None detected. Model → Service → View dependency flow is acyclic.
- **API Rate Limiting:** None built-in. YouTube Music's internal API does not enforce strict per-client limits.
- **WebView Lifecycle:** Singleton WKWebView is managed by AppDelegate, never deallocated during app lifetime to preserve JavaScript state and audio context.

## Anti-Patterns

### Direct print() Logging

**What happens:** Code calls `print()` for debug output, bypassing structured logging.
**Why it's wrong:** Print statements are invisible in Release builds and unstructured in logs.
**Do this instead:** Use `DiagnosticsLogger` singleton from `Sources/Kaset/Utilities/DiagnosticsLogger.swift`:
```swift
// Bad:
print("Loading home content")

// Good:
let logger = DiagnosticsLogger.api
logger.info("Loading home content")
```

### Force Unwraps (!)

**What happens:** Code uses `!` to unwrap optionals without error handling.
**Why it's wrong:** Crashes the app if optional is nil; violates Swift safety.
**Do this instead:** Use `guard let`, `if let`, or throw errors:
```swift
// Bad:
let url = URL(string: urlString)!

// Good:
guard let url = URL(string: urlString) else {
    throw YTMusicError.invalidURL
}
```

### DispatchQueue for Async Work

**What happens:** Code uses `DispatchQueue.main.async` instead of Swift Concurrency.
**Why it's wrong:** Strict Concurrency is enforced. DispatchQueue is not Sendable.
**Do this instead:** Use `async`/`await`:
```swift
// Bad:
DispatchQueue.main.async {
    self.updateUI()
}

// Good:
Task {
    await self.updateUI()
}
```

### Weak Self Closure Cycles

**What happens:** Closures capture `self` without `[weak self]`, creating retain cycles.
**Why it's wrong:** Causes memory leaks; services are singletons so cycles are permanent.
**Do this instead:** Use `[weak self]` in async closures:
```swift
// Bad:
Task {
    let data = try await client.fetch()
    self.data = data
}

// Good:
Task { [weak self] in
    let data = try await client.fetch()
    self?.data = data
}
```

## Error Handling

**Strategy:** Typed error enum with user-friendly fallbacks

**Pattern:**
1. Services throw `YTMusicError` enum (defined in `Sources/Kaset/Models/YTMusicError.swift`)
2. ViewModels catch errors and convert to `LoadingError` with user-friendly messages
3. Views display LoadingError.message in ErrorView
4. HTTP 401/403 triggers `AuthService.sessionExpired()` for re-authentication

**Example:**
```swift
// In ViewModel:
do {
    let response = try await client.getHome()
    self.sections = response.sections
} catch {
    self.loadingState = .error(LoadingError(from: error))
}

// YTMusicError provides:
enum YTMusicError: Error {
    case networkError(URLError)
    case authExpired  // 401/403 response
    case invalidJSON  // Parse error
    case notFound     // 404
    
    var userFriendlyTitle: String { ... }
    var userFriendlyMessage: String { ... }
    var isRetryable: Bool { ... }
}
```

## Cross-Cutting Concerns

**Logging:** `DiagnosticsLogger` with subsystems (api, auth, player, ui, webkit). Uses os.Logger under the hood.

**Validation:** YTMusicClient validates all responses before parsing; ParsingHelpers provide safe optional access.

**Authentication:** AuthService state machine + WebKitManager cookie management. 401/403 → `sessionExpired()` → show login sheet.

**Caching:** APICache in YTMusicClient with continuation token deduplication. CachedAsyncImage for thumbnails.

**Concurrency:** All main-thread services use `@MainActor` + `@Observable`. API calls use `async`/`await`. No DispatchQueue.

---

*Architecture analysis: 2026-04-27*
