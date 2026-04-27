# Testing Patterns

**Analysis Date:** 2026-04-27

## Test Framework

**Runner:**
- Swift Testing (not XCTest)
- Config: `Package.swift` enables strict concurrency
- Swift version: 6.0 with `StrictConcurrency` experimental feature

**Assertion Library:**
- Swift Testing's `#expect()` macro for assertions
- `#require()` macro for optional unwrapping in tests

**Run Commands:**
```bash
swift test --skip KasetUITests              # Run all unit tests
swift test --skip KasetUITests --filter ParserTests  # Run matching pattern
swiftlint --strict && swiftformat .         # Lint and format
swift build                                 # Build only
```

**UI Tests (separate):**
```bash
# Requires Xcode and explicit permission (NOT automatic)
xcodebuild test -scheme Kaset -destination 'platform=macOS' -only-testing:KasetUITests
```

## Test File Organization

**Location:**
- Unit tests in `Tests/KasetTests/` directory
- Test files co-located with sources (naming convention: `SourceName.swift` → `SourceNameTests.swift`)
- UI tests in `Tests/KasetUITests/` directory
- Fixtures in `Tests/KasetTests/Fixtures/` (JSON response files)
- Mocks and helpers in `Tests/KasetTests/Helpers/`
- Custom test utilities in `Tests/KasetTests/SwiftTestingHelpers/`

**Naming:**
- Test files use `*Tests.swift` suffix: `PlayerServiceTests.swift`, `AuthServiceTests.swift`
- Test suites use `@Suite` attribute with descriptive names matching the component
- Test functions use `@Test("descriptive name")` attribute with clear, readable test names

**Structure:**
```
Tests/KasetTests/
├── Helpers/
│   ├── MockEqualizerAudioEngine.swift
│   ├── MockPlayerService.swift
│   ├── MockScrobbleService.swift
│   ├── MockURLProtocol.swift
│   ├── MockWebKitManager.swift
│   ├── MockYTMusicClient.swift
│   └── TestFixtures.swift
├── SwiftTestingHelpers/
│   ├── Tags.swift
│   └── TestStringConvertible.swift
├── Fixtures/
│   ├── home_response.json
│   ├── search_response.json
│   └── playlist_detail.json
├── PerformanceTests/
│   └── ParserPerformanceTests.swift
└── *Tests.swift (100+ test files)
```

## Test Structure

**Suite Organization:**
```swift
import Testing
@testable import Kaset

@Suite("PlayerService", .serialized, .tags(.service))
@MainActor
struct PlayerServiceTests {
    var playerService: PlayerService
    
    init() {
        // Reset state before each test
        UserDefaults.standard.removeObject(forKey: "playerVolume")
        self.playerService = PlayerService()
    }
    
    // MARK: - Initial State Tests
    
    @Test("Initial state is idle")
    func initialState() {
        #expect(self.playerService.state == .idle)
        #expect(self.playerService.currentTrack == nil)
    }
}
```

**Key Patterns:**
- Test suites are `struct` types, not classes (Swift Testing standard)
- Suite names match the component being tested
- Use `init()` for setup (ARC handles teardown automatically)
- Organize tests with `// MARK: - Category` sections
- Each test focuses on one behavior

## Test Structure Details

**Attributes:**
- `@Suite()` marks the struct as a test suite
- `.serialized` required for `@MainActor` tests to prevent race conditions
- `.tags(.service)` categorizes tests for filtering
- `@MainActor` required on test suites that test `@MainActor` classes (e.g., services, ViewModels)
- `@Test("description")` marks individual test functions with human-readable names

**Initialization:**
```swift
struct PlayerServiceTests {
    var playerService: PlayerService
    
    init() {
        // Clean state before test
        UserDefaults.standard.removeObject(forKey: "playerVolume")
        self.playerService = PlayerService()
    }
}
```

**Test Methods:**
```swift
@Test("Does something specific")
func doesSomethingSpecific() {
    // Arrange: Set up test data
    let song = TestFixtures.makeSong(id: "test-123")
    
    // Act: Execute the code being tested
    playerService.load(song)
    
    // Assert: Verify results
    #expect(playerService.currentTrack == song)
    #expect(playerService.isPlaying == false)
}
```

## Async Testing

**Pattern:**
```swift
@Test("Loads data from API")
func loadsDataFromAPI() async throws {
    // Arrange
    mockClient.homeResponse = HomeResponse(sections: [TestFixtures.makeSection()])
    
    // Act
    let viewModel = HomeViewModel(client: mockClient)
    await viewModel.load()
    
    // Assert
    #expect(!viewModel.isLoading)
    #expect(!viewModel.sections.isEmpty)
}
```

**Async with Errors:**
```swift
@Test("Throws error on network failure")
func networkFailure() async throws {
    // Arrange
    mockClient.error = YTMusicError.networkError(underlying: URLError(.notConnectedToInternet))
    
    // Act & Assert
    let viewModel = SearchViewModel(client: mockClient)
    await #expect(throws: YTMusicError.networkError) {
        try await viewModel.search(query: "test")
    }
}
```

## Error Testing

**Pattern:**
```swift
@Test("Error has correct description")
func errorDescription() {
    let error = YTMusicError.authExpired
    #expect(error.errorDescription == "Your session has expired. Please sign in again.")
    #expect(error.recoverySuggestion == "Sign in to your YouTube Music account.")
}

@Test(
    "Auth errors require reauth",
    arguments: [
        YTMusicError.authExpired,
        YTMusicError.notAuthenticated,
    ]
)
func authErrorsRequireReauth(error: YTMusicError) {
    #expect(error.requiresReauth)
}
```

## Mocking

**Framework:** Manual mocks (no third-party mocking framework)

**MockYTMusicClient (API client mock):**
Located at `Tests/KasetTests/Helpers/MockYTMusicClient.swift` — provides response stub properties:
```swift
final class MockYTMusicClient: YTMusicClientProtocol {
    var homeResponse: HomeResponse = .init(sections: [])
    var homeContinuationSections: [[HomeSection]] = []
    var searchResponse: SearchResponse = .empty
    var error: Error?
    
    // Call tracking
    var getSongCalled = false
    var getSongVideoIds: [String] = []
    var onGetLibraryContent: (@MainActor () -> Void)?
}
```

**Usage in Tests:**
```swift
@Test("Home loads sections from API")
func homeLoadsFromAPI() async {
    let mockClient = MockYTMusicClient()
    mockClient.homeResponse = HomeResponse(sections: [
        TestFixtures.makeSection(),
        TestFixtures.makeSection(),
    ])
    
    let viewModel = HomeViewModel(client: mockClient)
    await viewModel.load()
    
    #expect(viewModel.sections.count == 2)
}
```

**MockPlayerService:**
Located at `Tests/KasetTests/Helpers/MockPlayerService.swift` — provides playback state stubs and call tracking

**MockWebKitManager:**
Located at `Tests/KasetTests/Helpers/MockWebKitManager.swift` — provides cookie and auth state simulation:
```swift
mockWebKitManager.sapisidValue = "test-sapisid"
mockWebKitManager.clearAllDataCalled = false
let cookies = await mockWebKitManager.getAllCookies()
```

**MockURLProtocol:**
Located at `Tests/KasetTests/Helpers/MockURLProtocol.swift` — for low-level network testing:
```swift
MockURLProtocol.requestHandler = { request in
    let json = """
    {"sections": []}
    """
    let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
    return (response, json.data(using: .utf8)!)
}
```

**What to Mock:**
- Always: External APIs (YTMusicClient), network calls, file system access
- Usually: WebKit/authentication services, player services
- Rarely: Models, value types (use real instances)
- Never: Core Foundation types (Date, UUID, etc.) — use real values

**What NOT to Mock:**
- Never: Value types (structs) — create real instances with `TestFixtures`
- Never: Pure functions or deterministic logic — test with real implementations
- Never: SwiftUI (use real views with `@State` for testing behavior)

## Fixtures and Factories

**TestFixtures (factory functions):**
Located at `Tests/KasetTests/Helpers/TestFixtures.swift` — provides type-safe fixture creation:
```swift
enum TestFixtures {
    static func makeSong(
        id: String = "test-video-id",
        title: String = "Test Song",
        artistName: String = "Test Artist"
    ) -> Song {
        Song(
            id: id,
            title: title,
            artists: [Artist(id: "UC123", name: artistName)],
            album: nil,
            duration: 180,
            thumbnailURL: URL(string: "https://example.com/thumb.jpg"),
            videoId: id
        )
    }
    
    static func makeSongs(count: Int) -> [Song] {
        (0 ..< count).map { index in
            self.makeSong(
                id: "video-\(index)",
                title: "Song \(index)"
            )
        }
    }
    
    static func makeAlbum(id: String = "MPRE-test-album") -> Album { ... }
    static func makePlaylist(id: String = "VL-test-playlist") -> Playlist { ... }
    static func makeArtist(id: String = "UC123") -> Artist { ... }
}
```

**Location:** `Tests/KasetTests/Helpers/TestFixtures.swift`

**Usage in Tests:**
```swift
@Test("Shows song in UI")
func showsSong() {
    let songs = TestFixtures.makeSongs(count: 5)
    let playlist = TestFixtures.makePlaylist()
    
    #expect(songs.count == 5)
    #expect(playlist.id == "VL-test-playlist")
}
```

## Test Tags

**Available tags:** Defined in `Tests/KasetTests/SwiftTestingHelpers/Tags.swift`
- `.api` — API client and network tests
- `.parser` — Response parsing tests
- `.viewModel` — ViewModel state management tests
- `.service` — Service layer tests
- `.model` — Data model tests
- `.slow` — Tests that take >1 second
- `.integration` — Integration tests requiring multiple components
- `.performance` — Performance/benchmark tests

**Usage:**
```swift
@Suite("HomeResponseParser", .tags(.parser))
struct HomeResponseParserTests { ... }

@Suite("SearchViewModel", .serialized, .tags(.viewModel), .timeLimit(.minutes(1)))
struct SearchViewModelTests { ... }
```

**Filtering:**
```bash
swift test --skip KasetUITests --filter TestName  # Run tests matching name
```

## Coverage

**Requirements:** No hard coverage target enforced

**View Coverage:**
```bash
# Generate coverage in Xcode
xcodebuild -scheme Kaset test -destination 'platform=macOS' -enableCodeCoverage YES
```

**Coverage Strategy:**
- New services: Aim for >80% coverage
- ViewModels: Focus on state transitions and error paths
- Models: 100% for parsing and computed properties
- Views: UI tests cover critical paths (unit test coverage less critical)

## Test Types

### Unit Tests (Primary)

**Scope:** Single function or method in isolation
**Location:** `Tests/KasetTests/*Tests.swift`
**Example:** `EQPresetTests.swift`, `PlayerServiceTests.swift`

```swift
@Suite(.tags(.model))
struct EQPresetTests {
    @Test("Every preset's gain table matches band count")
    func gainTableLengthMatchesBands() {
        let bandCount = EQBand.defaultBands.count
        for preset in EQPreset.allCases {
            #expect(preset.bandGainsDB.count == bandCount)
        }
    }
}
```

### Integration Tests

**Scope:** Multiple components working together
**Location:** `Tests/KasetTests/*IntegrationTests.swift`
**Example:** `MusicIntentIntegrationTests.swift` (AI + command execution)

```swift
@Suite("MusicIntentIntegration", .tags(.integration, .slow), .enabled(if: LanguageModelSession.isAvailable))
@MainActor
struct MusicIntentIntegrationTests {
    @Test("Parses chill music command into MoodQuery", arguments: [
        "Play something chill",
        "Give me relaxing music",
        "I want calm songs",
    ])
    func parseChillMusicCommand(prompt: String) async throws {
        // Use LanguageModelSession to parse natural language
        // Verify intent type and field values
    }
}
```

**AI Integration Specifics:**
- Tests skip gracefully via `.enabled(if: LanguageModelSession.isAvailable)`
- Retry logic: Up to 3 attempts per test with 500ms delays for LLM non-determinism
- Relaxed validation: Check multiple fields for expected content (e.g., mood OR query)
- Case-insensitive string matching
- Fresh `LanguageModelSession` per attempt to avoid context drift
- Tagged `.integration` and `.slow` for easy CI exclusion

### Parameterized Tests

**Pattern:** Multiple inputs tested with same assertion logic
**Syntax:** `@Test("description", arguments: [arg1, arg2, ...])`

```swift
@Test(
    "Duration formatting",
    arguments: [
        (0.0, "0:00"),
        (65.0, "1:05"),
        (3661.0, "1:01:01"),
    ]
)
func durationFormatting(seconds: Double, expected: String) {
    let song = TestFixtures.makeSong(duration: seconds)
    #expect(song.durationDisplay == expected)
}
```

### UI Tests

**Framework:** XCTest with `XCUIApplication`
**Location:** `Tests/KasetUITests/*UITests.swift`
**Base Class:** `KasetUITestCase` at `Tests/KasetUITests/KasetUITestCase.swift`

**Structure:**
```swift
@MainActor
class HomeViewUITests: KasetUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        // Additional setup if needed
    }
    
    func testHomePageLoads() throws {
        launchDefault()
        navigateToHome()
        waitForElement(app.staticTexts["Home Title"], timeout: 5)
        // Assertions
    }
}
```

**Key Helpers from KasetUITestCase:**
- `launchDefault()` — Launch app with no special setup
- `launchWithMockHome(sectionCount:, itemsPerSection:)` — Mock home content
- `launchWithMockSearch(songCount:)` — Mock search results
- `launchWithMockLibrary(playlistCount:)` — Mock library playlists
- `launchWithMockPlayer(isPlaying:, hasVideo:)` — Mock player state
- `launchWithMockFavorites(_:)` — Mock user favorites
- `waitForElement(_:, timeout:)` — Wait for element to appear
- `waitForHittable(_:, timeout:)` — Wait for element to be interactive
- `waitForElementCount(_:, count:, timeout:)` — Wait for specific count
- `waitForElementToDisappear(_:, timeout:)` — Wait for element removal
- `navigateToHome()`, `navigateToSearch()`, `navigateToLibrary()` — Navigation helpers

**Accessibility Identifiers:**
UI tests use accessibility IDs for reliable element targeting defined in `TestAccessibilityID` enum:
```swift
enum TestAccessibilityID {
    enum Sidebar {
        static let container = "sidebar"
        static let searchItem = "sidebar.search"
        static let homeItem = "sidebar.home"
    }
}

// Usage in tests
navigateToSidebarItem(TestAccessibilityID.Sidebar.homeItem)
```

**UI Test Prerequisites:**
- ⚠️ **Requires explicit human approval** — Never run UI tests automatically
- Requires installed Kaset.app at `/Applications/Kaset.app` or Xcode project with bundle ID
- App launched with `-UITestMode` and `-SkipAuth` arguments to bypass authentication
- Animations disabled for reliable testing

## Performance Tests

**Location:** `Tests/KasetTests/PerformanceTests/ParserPerformanceTests.swift`

**Pattern:**
```swift
@Test("Parser handles large responses efficiently")
func largeResponsePerformance() {
    let largeData = TestFixtures.makeHomeResponse(sectionCount: 100, itemsPerSection: 50)
    
    let startTime = Date()
    let result = HomeResponseParser.parse(largeData)
    let elapsed = Date().timeIntervalSince(startTime)
    
    #expect(elapsed < 0.5)  // Should parse in under 500ms
}
```

**Marked with:** `.tags(.performance)` and `.timeLimit(.seconds(10))`

## Common Patterns

### Testing UserDefaults Isolation

```swift
init() {
    // Reset to clean state for each test
    UserDefaults.standard.removeObject(forKey: "playerVolume")
    UserDefaults.standard.removeObject(forKey: "playerVolumeBeforeMute")
    self.playerService = PlayerService()
}
```

### Testing State Transitions

```swift
@Test("Login transitions through states")
func loginStateTransitions() async {
    let authService = AuthService(webKitManager: mockWebKit)
    
    #expect(authService.state == .initializing)
    
    authService.startLogin()
    #expect(authService.state == .loggingIn)
    
    authService.completeLogin(sapisid: "test-sapisid")
    #expect(authService.state == .loggedIn(sapisid: "test-sapisid"))
}
```

### Testing Call Sequences

```swift
@Test("Cookie restore happens before SAPISID fetch")
func callSequence() async {
    let mock = MockWebKitManager()
    let authService = AuthService(webKitManager: mock)
    
    await authService.checkLoginStatus()
    
    #expect(mock.callSequence == [
        "waitForInitialCookieRestore",
        "getSAPISID"
    ])
}
```

### Testing Error Paths

```swift
@Test("Handles API errors with recovery suggestions")
func apiErrorHandling() {
    let error = YTMusicError.apiError(message: "Rate limited", code: 429)
    
    #expect(error.errorDescription?.contains("Rate limited") == true)
    #expect(error.recoverySuggestion?.contains("Try again") == true)
}
```

## Test Execution

**Local Development Loop:**
```bash
# Daily verification (CLI only)
swift build                          # Verify compilation
swift test --skip KasetUITests       # Run unit tests
swiftlint --strict                   # Check linting
swiftformat .                        # Auto-format
```

**Escalate to Xcode for:**
- Simulator/device testing
- UI test debugging
- WebKit/runtime inspection
- Performance profiling

**CI/CD (GitHub Actions):**
- Runs full unit test suite
- Excludes integration tests (AI non-determinism)
- Uses Xcode 26+ on macOS 26 runner

---

*Testing analysis: 2026-04-27*
