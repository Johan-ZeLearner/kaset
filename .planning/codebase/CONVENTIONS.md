# Coding Conventions

**Analysis Date:** 2026-04-27

## Naming Patterns

**Files:**
- Swift files use PascalCase (e.g., `PlayerService.swift`, `CommandBarView.swift`)
- Protocol files group protocols with `// MARK:` comments (e.g., `Protocols.swift` contains `WebKitManagerProtocol`, `YTMusicClientProtocol`, `AuthServiceProtocol`, `PlayerServiceProtocol`)
- Test files match source file names with "Tests" suffix (e.g., `PlayerService.swift` → `PlayerServiceTests.swift`)
- Fixture and helper files use descriptive names (e.g., `MockYTMusicClient.swift`, `TestFixtures.swift`)

**Functions:**
- camelCase for all functions and methods
- Use verb-based names for actions: `loadHome()`, `playSong()`, `updatePlaybackState()`
- Prefix boolean properties with `is` or `has`: `isPlaying`, `hasVideo`, `hasMoreSections`
- Query functions use get prefix only when disambiguating: `getSong()`, `getSAPISID()`

**Variables:**
- camelCase for all variable names
- Descriptive names preferred over abbreviations: `currentTrack` not `curTrack`, `userDefaults` not `ud`
- Mark mutable state with leading underscore in `@State` declarations: `@State private var _viewModel`
- Use `self` prefix explicitly in instance methods and `Self` in static methods (enforced by SwiftFormat `--self insert` rule)

**Types:**
- PascalCase for all type names (structs, classes, enums, protocols)
- Prefix protocols with Protocol suffix when describing behavior: `YTMusicClientProtocol`, `PlayerServiceProtocol`
- Enum cases use camelCase: `.playing`, `.paused`, `.idle`
- Generic type parameters use single uppercase letters or descriptive names: `T`, `Element` or `Value`

## Code Style

**Formatting:**
- Tool: SwiftFormat with custom configuration in `.swiftformat`
- Swift version: 6.0
- Indentation: 4 spaces
- Line endings: LF (Unix)
- No trailing whitespace
- Brace style: Allman false (opening brace on same line)
- Always use explicit `self` in instance methods (enforced by `--self insert`)
- Always use `Self` in static methods (enforced by `--self insert`)

**Linting:**
- Tool: SwiftLint with configuration in `.swiftlint.yml`
- Strict mode enforced: `swiftlint --strict`
- Key rules:
  - No `NavigationView` — use `NavigationSplitView` or `NavigationStack` instead
  - No `DispatchQueue` — use Swift concurrency (`async`/`await`) instead
  - No bare `print()` — use `DiagnosticsLogger` instead
  - No `.foregroundColor()` — use `.foregroundStyle()` instead
  - No `.cornerRadius()` — use `.clipShape(.rect(cornerRadius:))` instead
  - Identifier min length: 1, max: 60
  - Type names min length: 3, max: 50
  - File length warning: 900 lines, error: 1500 lines
  - Function body length warning: 100 lines, error: 150 lines
  - Type body length warning: 700 lines, error: 1000 lines
  - Cyclomatic complexity warning: 15, error: 25
  - Type nesting max: 3 levels
  - Function nesting max: 3 levels

## Import Organization

**Order:**
1. Standard library imports (`Foundation`, `CoreTransferable`, etc.)
2. Apple framework imports (`AppKit`, `SwiftUI`, `FoundationModels`, etc.)
3. Third-party imports (`@preconcurrency import XCTest`, Sparkle, etc.)
4. Test imports (`@testable import Kaset`)

**Path Aliases:**
- No custom path aliases used in project
- All imports use full module names

**Example from `CommandBarView.swift`:**
```swift
import FoundationModels
import SwiftUI
```

## Error Handling

**Patterns:**
- Create `YTMusicError` enum cases for specific error conditions in `Sources/Kaset/Models/YTMusicError.swift`
- Throw `YTMusicError.authExpired` on HTTP 401/403 responses
- Throw `YTMusicError.networkError(underlying: URLError)` for network failures
- Throw `YTMusicError.parseError(message: String)` for JSON/response parsing failures
- Include `errorDescription`, `recoverySuggestion`, `debugDescription`, and `requiresReauth` properties for user-facing error handling
- Use `#expect(throws:)` in unit tests to validate error throwing behavior
- Handle `CancellationError` separately from other error types (see `docs/common-bug-patterns.md`)

**Common Error Recovery:**
- Auth errors set `needsReauth` flag and trigger login sheet
- Network errors suggest checking connection and retrying
- Parse errors suggest trying again or reporting if persistent
- Playback errors suggest trying a different track

## Logging

**Framework:** `DiagnosticsLogger` (project-specific logger in `Sources/Kaset/Utilities/DiagnosticsLogger.swift`)

**Patterns:**
- Use `DiagnosticsLogger.{category}` where category matches subsystem (e.g., `DiagnosticsLogger.api`, `DiagnosticsLogger.player`, `DiagnosticsLogger.auth`)
- `.info()` for major operations: "Loading library", "Playlist loaded with X tracks"
- `.debug()` for state transitions and detailed flow: "Queue updated", "Preserving snapshot"
- `.error()` reserved for unexpected failures that may indicate bugs
- Log at operation start and completion, not in tight loops
- Include relevant IDs in log messages: "Loading playlist: \(id)", not just "Loading playlist"
- Include counts in completion messages: "Loaded X tracks" not "Loaded tracks"

**Example from `LibraryViewModel.swift`:**
```swift
private let logger = DiagnosticsLogger.api

self.logger.info("Loading library content")
self.logger.info("Loaded playlist with \(trackCount) tracks")
self.logger.debug("Library load cancelled")
```

## Comments

**When to Comment:**
- Comment public APIs: All public types, functions, and properties have documentation comments
- Comment complex algorithms: If business logic is non-obvious, explain the "why" not the "what"
- Comment workarounds: Mark with `FIXME:` or `TODO:` if temporary or incomplete
- Mark known limitations: Note conditions under which code may fail

**JSDoc/TSDoc:**
- Use triple-slash `///` documentation comments for public APIs
- Include parameter descriptions and return value descriptions
- Mark parameters as `- Parameter name: Description`
- Mark return values as `- Returns: Description`
- Add availability attributes when applicable: `@available(macOS 26.0, *)`

**Example from `HapticService.swift`:**
```swift
/// Whether haptic feedback is currently enabled.
/// Checks both user preference and system accessibility settings.
private static var isEnabled: Bool { ... }

/// Performs haptic feedback of the specified type.
/// - Parameter type: The type of feedback to perform.
static func perform(_ type: FeedbackType) { ... }
```

## Function Design

**Size:** 
- Target: Under 30 lines for most functions
- Hard limit: SwiftLint warns at 100 lines, errors at 150 lines for function bodies
- Break large functions into smaller helper functions with clear responsibilities

**Parameters:**
- Limit: Aim for fewer than 6 parameters
- Use structs for logically related parameters rather than many individual parameters
- Mark closures as trailing closures when they're the last parameter
- Use default parameter values conservatively for clarity

**Return Values:**
- Return optional (`T?`) when value may not exist
- Return `Result<T, E>` for operations that may fail with specific error types
- Return `Void` explicitly or use implicit return for simple expressions
- Async functions use `async throws` pattern: signature states that errors may be thrown

**Example from `TestFixtures.swift`:**
```swift
static func makeSong(
    id: String = "test-video-id",
    title: String = "Test Song",
    artistName: String = "Test Artist",
    artistId: String = "UC123",
    duration: TimeInterval? = 180
) -> Song {
    // Implementation
}
```

## Module Design

**Exports:**
- Services export protocol types, not concrete implementations
- ViewModels marked with `@Observable @MainActor` and exported for dependency injection
- Models (structs, enums) export concrete types
- Internal helpers marked `private` or `fileprivate`

**Barrel Files:**
- Not used in this project — each file has a single primary type
- Avoid creating `__all__.swift` or re-export modules

**File Organization:**
- Use `// MARK: - SectionName` to organize code into logical sections
- Order: Type definition, `// MARK: - Initializers`, `// MARK: - State`, `// MARK: - Lifecycle`, `// MARK: - Public Methods`, `// MARK: - Private Methods`, nested types at end
- Keep mark sections focused (1-10 items per section)

**Example from `CommandBarView.swift`:**
```swift
// MARK: - CommandBarView

struct CommandBarView: View {
    // Properties grouped at top
    let client: any YTMusicClientProtocol
    @State private var viewModel: CommandBarViewModel
    
    // MARK: - Initializers
    
    init(...) { ... }
    
    // MARK: - Body
    
    var body: some View { ... }
}
```

## Concurrency

**Patterns:**
- Use `async`/`await` exclusively — no `DispatchQueue`
- Mark UI classes with `@MainActor` when they interact with SwiftUI
- Use `.task` modifier instead of `.onAppear { Task { } }` for lifecycle-managed async operations
- Use `@Binding` for two-way state sync with parent views
- Use `Environment` for injecting dependencies down view hierarchy
- Cancel tasks explicitly in deallocators or when state changes

**Example from `AuthServiceTests.swift`:**
```swift
@Suite(.serialized, .tags(.service))
@MainActor
struct AuthServiceTests {
    var authService: AuthService
    
    @Test("Check login status waits for restore")
    func checkLoginStatus() async {
        await self.authService.checkLoginStatus()
        #expect(self.authService.state == .loggedIn(sapisid: "persisted-sapisid"))
    }
}
```

## Accessibility

**Patterns:**
- All icon-only buttons must have `.accessibilityLabel()`
- Use `.accessibilityIdentifier()` for UI test targeting
- Provide meaningful descriptions for complex UI patterns
- Respect system accessibility settings (e.g., `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`)

**Example from `CommandBarView.swift`:**
```swift
Button {
    viewModel.inputText = ""
} label: {
    Image(systemName: "xmark.circle.fill")
        .foregroundStyle(.secondary)
}
.buttonStyle(.plain)
.accessibilityLabel(String(localized: "Clear input"))
```

---

*Convention analysis: 2026-04-27*
