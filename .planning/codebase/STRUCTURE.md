# Codebase Structure

**Analysis Date:** 2026-04-27

## Directory Layout

```
kaset/
├── Sources/
│   ├── Kaset/                          # Main app target (Swift 6, macOS 26+)
│   │   ├── KasetApp.swift              # App entry point, @main
│   │   ├── AppDelegate.swift           # Window lifecycle, queue restoration
│   │   ├── Models/                     # Domain entities (Codable structs)
│   │   │   ├── Song.swift              # Track representation
│   │   │   ├── Playlist.swift          # User and editorial playlists
│   │   │   ├── Album.swift             # Album metadata
│   │   │   ├── Artist.swift            # Artist with tracks/albums
│   │   │   ├── Podcast.swift           # Podcast episodes
│   │   │   ├── YTMusicError.swift      # Error enum for API failures
│   │   │   ├── LoadingState.swift      # Async state machine
│   │   │   ├── HomeSection.swift       # Shelf/section container
│   │   │   ├── SearchResponse.swift    # Search API response
│   │   │   ├── HomeResponse.swift      # Home/Explore/Charts response
│   │   │   ├── EQPreset.swift          # Equalizer configuration
│   │   │   ├── LikeStatus.swift        # Like/dislike state
│   │   │   ├── Lyrics.swift            # Synced lyrics
│   │   │   └── AI/                     # AI-related models
│   │   │       ├── MusicIntent.swift   # Parsed command intent
│   │   │       ├── LyricsSummary.swift # AI lyric summary
│   │   │       └── ...
│   │   ├── Services/                   # Business logic + singletons
│   │   │   ├── API/                    # YouTube Music API client
│   │   │   │   ├── YTMusicClient.swift # HTTP requests + parsing
│   │   │   │   ├── APICache.swift      # Response caching
│   │   │   │   └── Parsers/            # JSON → Model conversion
│   │   │   │       ├── HomeResponseParser.swift
│   │   │   │       ├── SearchResponseParser.swift
│   │   │   │       ├── SongMetadataParser.swift
│   │   │   │       ├── ArtistParser.swift
│   │   │   │       ├── PlaylistParser.swift
│   │   │   │       ├── PodcastParser.swift
│   │   │   │       ├── LyricsParser.swift
│   │   │   │       ├── ParsingHelpers.swift  # Safe optional access
│   │   │   │       └── ...
│   │   │   ├── Player/                 # Playback control
│   │   │   │   ├── PlayerService.swift # Singleton + API (play, pause, seek, queue)
│   │   │   │   ├── PlayerService+Queue.swift    # Queue manipulation
│   │   │   │   ├── PlayerService+PlaybackControls.swift
│   │   │   │   ├── PlayerService+WebQueueSync.swift
│   │   │   │   ├── PlayerService+PlaybackRestoration.swift
│   │   │   │   ├── PlayerService+Episodes.swift # Podcast playback
│   │   │   │   ├── PlayerQueueModels.swift      # QueueEntry struct
│   │   │   │   └── NowPlayingManager.swift      # Media keys (F7, F8, F9)
│   │   │   ├── Auth/                   # Authentication state machine
│   │   │   │   ├── AuthService.swift   # Login state + status checking
│   │   │   │   └── AccountService.swift # Multi-account management
│   │   │   ├── WebKit/                 # Cookie + WebKit management
│   │   │   │   ├── WebKitManager.swift # Singleton WKWebsiteDataStore
│   │   │   │   └── WebKitManager+Cookies.swift  # Keychain backup/restore
│   │   │   ├── Audio/                  # Equalizer + audio processing
│   │   │   │   ├── EqualizerService.swift
│   │   │   │   ├── EqualizerAudioEngine.swift
│   │   │   │   └── ...
│   │   │   ├── Lyrics/                 # Synced lyrics providers
│   │   │   │   ├── LyricsProvider.swift # Protocol
│   │   │   │   ├── Providers/
│   │   │   │   │   ├── YTMusicSyncedProvider.swift
│   │   │   │   │   └── LRCLibProvider.swift
│   │   │   │   ├── Romanization/       # Script romanizers (CJK → Latin)
│   │   │   │   │   ├── TextCanonicalizer.swift
│   │   │   │   │   ├── ScriptDetector.swift
│   │   │   │   │   └── Romanizers/
│   │   │   │   │       ├── JapaneseRomanizer.swift (Hiragana → Romaji)
│   │   │   │   │       ├── KoreanRomanizer.swift (Hangul → Romaja)
│   │   │   │   │       ├── ChineseRomanizer.swift (Pinyin)
│   │   │   │   │       └── ...
│   │   │   ├── Scrobbling/             # Last.fm integration
│   │   │   │   ├── ScrobbleServiceProtocol.swift
│   │   │   │   ├── LastFMService.swift
│   │   │   │   └── ScrobblingCoordinator.swift
│   │   │   ├── AI/                     # Foundation Models + command parsing
│   │   │   │   ├── FoundationModelsService.swift # On-device ML
│   │   │   │   ├── CommandIntentParser.swift    # NLU for commands
│   │   │   │   ├── CommandExecutor.swift        # Execute parsed intents
│   │   │   │   ├── ContentSourceResolver.swift  # Resolve music from intent
│   │   │   │   ├── FoundationModelsPromptLibrary.swift
│   │   │   │   ├── AIErrorHandler.swift
│   │   │   │   └── Tools/               # Command execution tools
│   │   │   │       ├── MusicSearchTool.swift
│   │   │   │       └── QueueTool.swift
│   │   │   ├── Scripting/              # AppleScript integration
│   │   │   │   └── ScriptCommands.swift # play(), pause(), next(), etc.
│   │   │   ├── Notification/           # Notch + badge notifications
│   │   │   │   └── NotificationService.swift
│   │   │   ├── Protocols.swift          # Protocol definitions (YTMusicClientProtocol, etc.)
│   │   │   ├── SettingsManager.swift   # Preferences persistence
│   │   │   ├── FavoritesManager.swift  # Liked songs cache
│   │   │   ├── SongLikeStatusManager.swift # Like/unlike operations
│   │   │   ├── UpdaterService.swift    # Sparkle auto-update
│   │   │   ├── HapticService.swift     # Trackpad haptics
│   │   │   ├── ShareService.swift      # URL sharing
│   │   │   ├── URLHandler.swift        # Incoming URL routing (spotify:, yt-music:)
│   │   │   ├── ExtensionsManager.swift # Web extensions
│   │   │   ├── NetworkMonitor.swift    # Reachability
│   │   │   ├── ErrorPresenter.swift    # Error dialog presentation
│   │   │   └── WhatsNewVersionStore.swift # Release notes
│   │   ├── ViewModels/                 # @Observable state management
│   │   │   ├── HomeViewModel.swift     # Home page (curated + continuations)
│   │   │   ├── SearchViewModel.swift   # Search results + suggestions
│   │   │   ├── PlaylistDetailViewModel.swift # Playlist/album/artist songs
│   │   │   ├── ExploreViewModel.swift  # Discover page
│   │   │   ├── ChartsViewModel.swift   # Charts page
│   │   │   ├── MoodsAndGenresViewModel.swift # Moods/genres page
│   │   │   ├── NewReleasesViewModel.swift    # New releases
│   │   │   ├── PodcastsViewModel.swift      # Podcast discovery
│   │   │   ├── LibraryViewModel.swift       # User playlists
│   │   │   ├── HistoryViewModel.swift       # Play history
│   │   │   ├── CommandBarViewModel.swift    # AI command bar
│   │   │   ├── ArtistDetailViewModel.swift  # Artist songs/albums/episodes
│   │   │   ├── ArtistDiscographyViewModel.swift
│   │   │   ├── ArtistEpisodesListViewModel.swift
│   │   │   ├── MoodCategoryViewModel.swift
│   │   │   └── TopSongsViewModel.swift
│   │   ├── Views/                      # SwiftUI UI components
│   │   │   ├── MainWindow.swift        # Root view (NavigationSplitView)
│   │   │   ├── Sidebar.swift           # Left sidebar navigation
│   │   │   ├── PlayerBar.swift         # Bottom transport controls
│   │   │   ├── HomeView.swift          # Home tab
│   │   │   ├── SearchView.swift        # Search tab + suggestions
│   │   │   ├── ExploreView.swift       # Discover tab
│   │   │   ├── ChartsView.swift        # Charts tab
│   │   │   ├── MoodsAndGenresView.swift # Moods/genres tab
│   │   │   ├── NewReleasesView.swift   # New releases tab
│   │   │   ├── PodcastsView.swift      # Podcasts tab
│   │   │   ├── LibraryView.swift       # Liked music + playlists
│   │   │   ├── HistoryView.swift       # Play history
│   │   │   ├── PlaylistDetailView.swift # Playlist/album/artist content
│   │   │   ├── ArtistDetailView.swift  # Artist profile
│   │   │   ├── ArtistDiscographyView.swift # Albums
│   │   │   ├── ArtistEpisodesListView.swift # Podcasts for artist
│   │   │   ├── CommandBarView.swift    # AI command input
│   │   │   ├── LyricsView.swift        # Synced lyrics display
│   │   │   ├── QueueView.swift         # Playback queue
│   │   │   ├── QueueSidePanelView.swift # Right queue panel
│   │   │   ├── LoginSheet.swift        # Auth UI (login prompt)
│   │   │   ├── LoginWebView.swift      # WebView for YouTube login
│   │   │   ├── SingletonPlayerWebView.swift  # Hidden playback WebView
│   │   │   ├── MiniPlayerWebView.swift      # Floating player (if used)
│   │   │   ├── MiniPlayerViews.swift
│   │   │   ├── EqualizerSettingsView.swift  # Audio settings
│   │   │   ├── GeneralSettingsView.swift    # App preferences
│   │   │   ├── ExtensionsSettingsView.swift # Web extensions
│   │   │   ├── ScrobblingSettingsView.swift # Last.fm settings
│   │   │   ├── IntelligenceSettingsView.swift # AI model settings
│   │   │   ├── SharedViews/            # Reusable components
│   │   │   │   ├── ErrorView.swift     # Error display
│   │   │   │   ├── LoadingView.swift   # Skeleton loader
│   │   │   │   ├── SkeletonView.swift  # Placeholder animation
│   │   │   │   ├── SongThumbnailView.swift # Album art
│   │   │   │   ├── CachedAsyncImage.swift # Image caching
│   │   │   │   ├── SongActionsHelper.swift # Play, like, radio, share
│   │   │   │   ├── FavoritesContextMenu.swift # Like/unlike menu
│   │   │   │   ├── FavoritesSection.swift # Favorite songs display
│   │   │   │   ├── HomeSectionItemCard.swift # Shelf item card
│   │   │   │   ├── InteractiveCardStyle.swift # Click feedback
│   │   │   │   ├── ShareContextMenu.swift # Share options
│   │   │   │   ├── StartRadioContextMenu.swift # Radio creation
│   │   │   │   ├── EqualizerView.swift # EQ UI control
│   │   │   │   ├── NavigationDestinationsModifier.swift # Navigation routing
│   │   │   │   ├── AnimationModifiers.swift # Transition effects
│   │   │   │   └── AccentBackground.swift # Themed backgrounds
│   │   │   ├── SharedViews/ListComponents/ # List row builders
│   │   │   ├── CassetteIcon.swift      # App icon display
│   │   │   ├── VideoPlayerWindow.swift # Video player (music videos)
│   │   │   ├── WhatsNewView.swift      # Release notes modal
│   │   │   ├── ToastView.swift         # Toast notifications
│   │   │   ├── SyncedLyricsDisplayView.swift # Lyrics in player
│   │   │   └── AccountRowView.swift    # Account switcher row
│   │   ├── Utilities/                  # Cross-cutting helpers
│   │   │   ├── DiagnosticsLogger.swift # Structured logging
│   │   │   ├── UITestConfig.swift      # Test mode flags
│   │   │   ├── Extensions.swift        # Foundation extensions
│   │   │   ├── ImageCache.swift        # Thumbnail caching
│   │   │   ├── AccessibilityIdentifiers.swift # UI test IDs
│   │   │   ├── PackageResourceLookup.swift # Bundle resources
│   │   │   ├── AppLocalization.swift   # i18n support
│   │   │   ├── ColorExtractor.swift    # Thumbnail dominant color
│   │   │   ├── RetryPolicy.swift       # Exponential backoff
│   │   │   ├── AnimationConfiguration.swift # Transition timing
│   │   │   └── IntelligenceModifier.swift # AI badge display
│   │   ├── Resources/                  # App assets + localization
│   │   │   ├── Assets.xcassets/        # Images, colors, icons
│   │   │   ├── ar.lproj/               # Arabic strings
│   │   │   ├── fr.lproj/               # French strings
│   │   │   ├── id.lproj/               # Indonesian strings
│   │   │   ├── ko.lproj/               # Korean strings
│   │   │   ├── tr.lproj/               # Turkish strings
│   │   │   └── kaset.icon/             # App icon
│   │   ├── Extensions/                 # Swift extensions
│   │   │   └── .gitkeep                # (Empty; extension files in other dirs)
│   │   └── WhatsNewProvider.swift      # Release notes data
│   └── APIExplorer/                    # CLI tool for API exploration
│       └── main.swift                  # `swift run api-explorer` entry
├── Tests/
│   └── KasetTests/                     # Unit tests (Swift Testing)
│       ├── Fixtures/                   # Test data (JSON responses)
│       ├── PlayerServiceTests.swift    # Playback tests
│       ├── SearchViewModelTests.swift  # Search tests
│       ├── EQPresetTests.swift         # Equalizer tests
│       ├── ScroblingCoordinatorTests.swift
│       ├── NewReleasesViewModelTests.swift
│       ├── SongThumbnailSourceTests.swift
│       └── ...
│   └── KasetUITests/                   # UI tests (XCTest)
│       ├── KasetUITestCase.swift       # Base test class
│       ├── AppLaunchUITests.swift      # Startup flow
│       ├── SearchViewUITests.swift     # Search interaction
│       ├── PlayerBarUITests.swift      # Transport controls
│       ├── LibraryViewUITests.swift    # Liked music
│       ├── AccountSwitcherUITests.swift
│       ├── CommandBarUITests.swift
│       ├── HomeViewUITests.swift
│       ├── ExploreViewUITests.swift
│       └── ...
├── docs/                               # Documentation
│   ├── adr/                            # Architecture Decision Records
│   │   ├── 0001-*.md                   # ADRs for major decisions
│   │   └── ...
│   ├── architecture.md                 # System overview
│   ├── playback.md                     # Playback implementation details
│   ├── api-discovery.md                # API exploration guide
│   ├── applescript.md                  # AppleScript commands
│   ├── keyboard-shortcuts.md           # Key bindings
│   ├── testing.md                      # Testing guide
│   ├── extensions.md                   # Web extensions docs
│   ├── url-scheme.md                   # URL scheme handling
│   ├── common-bug-patterns.md          # Concurrency anti-patterns
│   └── task-planning.md                # Development workflow
├── .agents/                            # Agent skills
│   └── skills/                         # Reusable skill documentation
├── .planning/                          # GSD execution planning
│   ├── phases/                         # Phase execution logs
│   └── codebase/                       # Codebase maps (ARCHITECTURE.md, etc.)
├── .github/                            # GitHub workflows
│   └── workflows/                      # CI/CD pipelines
├── Scripts/                            # Build & utility scripts
├── Package.swift                       # Swift Package manifest
├── CLAUDE.md / AGENTS.md               # AI assistant instructions
├── .swiftformat                        # Code formatter config (--self insert)
├── .swiftlint.yml                      # Linter rules
├── Kaset.entitlements                  # App sandbox entitlements
├── Info.plist                          # App metadata
└── README.md                           # Project overview
```

## Directory Purposes

**Sources/Kaset:**
- Purpose: Main macOS application target
- Contains: Views, ViewModels, Models, Services, Utilities
- Key files: `KasetApp.swift` (entry), `MainWindow.swift` (root view)

**Sources/Kaset/Models:**
- Purpose: Domain entities that flow through the app
- Contains: Codable structs for API responses (Song, Playlist, Artist, etc.) and value types (LoadingState, LikeStatus)
- Key files: `Song.swift`, `Playlist.swift`, `YTMusicError.swift`

**Sources/Kaset/Services:**
- Purpose: Business logic, API calls, state management, integrations
- Contains: YTMusicClient (API), PlayerService (playback), AuthService (login), WebKitManager (cookies), EqualizerService (audio), etc.
- Key files: `Services/Protocols.swift` (all protocols), `Services/API/YTMusicClient.swift` (API client)

**Sources/Kaset/Views:**
- Purpose: SwiftUI UI components
- Contains: Screen views (HomeView, SearchView, PlaylistDetailView), layout (MainWindow, Sidebar, PlayerBar), settings (EqualizerSettingsView, GeneralSettingsView), shared components (SharedViews/)
- Key files: `MainWindow.swift` (root), `Sidebar.swift` (navigation), `PlayerBar.swift` (transport)

**Sources/Kaset/ViewModels:**
- Purpose: @Observable state management for views
- Contains: One ViewModel per major feature (HomeViewModel, SearchViewModel, PlaylistDetailViewModel)
- Key files: All use protocol YTMusicClientProtocol for dependency injection

**Sources/Kaset/Utilities:**
- Purpose: Cross-cutting concerns and helpers
- Contains: DiagnosticsLogger, UITestConfig, Extensions, Caching
- Key files: `DiagnosticsLogger.swift` (logging), `UITestConfig.swift` (test mode)

**Tests/KasetTests:**
- Purpose: Unit tests using Swift Testing framework
- Contains: Tests for ViewModels, Services, Models; fixtures for JSON responses
- Key files: `Fixtures/` (mock API responses)

**Tests/KasetUITests:**
- Purpose: UI tests using XCTest framework
- Contains: Tests for user flows (launch, search, playback, auth)
- Key files: `KasetUITestCase.swift` (base class), individual view tests

**docs/**
- Purpose: Developer documentation
- Contains: ADRs, architecture overview, API exploration guide, keyboard shortcuts
- Key files: `architecture.md` (system design), `common-bug-patterns.md` (Swift concurrency)

## Key File Locations

**Entry Points:**
- `Sources/Kaset/KasetApp.swift`: App initialization, service wiring
- `Sources/Kaset/AppDelegate.swift`: Window lifecycle, queue restoration
- `Sources/Kaset/Views/MainWindow.swift`: Root UI container

**Configuration:**
- `Package.swift`: Build targets, dependencies (Sparkle)
- `.swiftformat`: Code formatter settings (--self insert rule active)
- `.swiftlint.yml`: Linter rules
- `Kaset.entitlements`: App sandbox permissions
- `Info.plist`: App metadata (version, name, bundle ID)

**Core Logic:**
- `Sources/Kaset/Services/API/YTMusicClient.swift`: HTTP API client
- `Sources/Kaset/Services/Player/PlayerService.swift`: Playback control
- `Sources/Kaset/Services/Auth/AuthService.swift`: Login state machine
- `Sources/Kaset/Services/WebKit/WebKitManager.swift`: Cookie persistence

**Testing:**
- `Tests/KasetTests/Fixtures/`: Mock API responses (JSON)
- `Tests/KasetTests/*.swift`: Unit tests
- `Tests/KasetUITests/*.swift`: UI tests

## Naming Conventions

**Files:**
- Views: `{Name}View.swift` (e.g., `HomeView.swift`, `SearchView.swift`)
- ViewModels: `{Feature}ViewModel.swift` (e.g., `HomeViewModel.swift`)
- Services: `{Service}Service.swift` (e.g., `PlayerService.swift`) or `{Service}Manager.swift` (e.g., `FavoritesManager.swift`)
- Models: PascalCase singular (e.g., `Song.swift`, `Playlist.swift`)
- Extensions: `{Type}+{Category}.swift` (e.g., `PlayerService+Queue.swift`)
- Tests: `{Class}Tests.swift` (e.g., `PlayerServiceTests.swift`)

**Directories:**
- Feature folders: lowercase plural (e.g., `Services/`, `Views/`, `Models/`)
- Subsystems: lowercase (e.g., `Services/API/`, `Services/Player/`)
- Localization: `{language}.lproj/` (e.g., `ar.lproj/`, `ko.lproj/`)

**Code Symbols:**
- Classes/Structs: PascalCase (Song, PlayerService, HomeViewModel)
- Functions/Variables: camelCase (play(), currentTrack, isPlaying)
- Enums: PascalCase (PlayerService.PlaybackState, LoadingState)
- Constants: camelCase or UPPER_CASE (authCookieName, maxContinuations)

## Where to Add New Code

**New Feature (e.g., New Page Tab):**
1. **ViewModel:** `Sources/Kaset/ViewModels/{Feature}ViewModel.swift`
   - Extends `@Observable final class`
   - Accepts `client: YTMusicClientProtocol` in init
   - Manages `LoadingState` and feature-specific `@Observable` state
2. **View:** `Sources/Kaset/Views/{Feature}View.swift`
   - @Environment(ViewModel) to access state
   - Displays results, error states, loading states
3. **API method (if new endpoint):** `Sources/Kaset/Services/API/YTMusicClient.swift`
   - Add function returning typed Model (e.g., `func getFeature() async throws -> FeatureResponse`)
   - Update `YTMusicClientProtocol` in `Services/Protocols.swift`
4. **Parser (if complex response):** `Sources/Kaset/Services/API/Parsers/{Feature}Parser.swift`
   - Create parser struct with static `parse()` method
   - Handle nil checks using ParsingHelpers
5. **Navigation:** Add case to `NavigationItem` enum in `Sidebar.swift`

**New Service/Manager:**
1. Create `Sources/Kaset/Services/{Service}.swift` as `@MainActor @Observable final class`
2. Make it a singleton with `static let shared = {Service}()`
3. Add protocol in `Services/Protocols.swift` if used by ViewModels
4. Wire into `KasetApp.init()` for environment injection
5. Create tests in `Tests/KasetTests/{Service}Tests.swift`

**Shared UI Component:**
1. Create `Sources/Kaset/Views/SharedViews/{Component}.swift`
2. Accept parameters for data and callbacks
3. Use `.glassEffect()` for backgrounds (macOS 26+), `.task` for async
4. Include preview in #Preview block for Xcode canvas

**Test Data (Fixtures):**
1. Create `Tests/KasetTests/Fixtures/{Feature}Response.json`
2. Add helper in test file to load: `try JSONDecoder().decode(ModelType.self, from: fixtureData)`

## Special Directories

**Sources/Kaset/Resources/:**
- Purpose: App assets, localized strings, icons
- Generated: No (checked into git)
- Committed: Yes
- Includes: Assets.xcassets (images, colors), {language}.lproj (Localizable.strings)

**Sources/Kaset/Extensions/:**
- Purpose: Swift extensions (currently unused, .gitkeep only)
- Generated: No
- Committed: Yes (placeholder)

**docs/adr/:**
- Purpose: Architecture Decision Records for major design choices
- Generated: No (manually created as needed)
- Committed: Yes
- Example: `0001-singleton-player-webview.md` (why WebView is singleton)

**.planning/:**
- Purpose: GSD orchestrator planning and execution logs
- Generated: Yes (by gsd commands)
- Committed: No (gitignored)
- Subdirs: `phases/` (phase logs), `codebase/` (maps like ARCHITECTURE.md)

**.agents/skills/:**
- Purpose: Reusable AI agent skill documentation
- Generated: No (checked into git)
- Committed: Yes
- Example: `api-exploration/SKILL.md` describes API discovery patterns

**Tests/KasetTests/Fixtures/:**
- Purpose: Mock JSON API responses for unit tests
- Generated: No (checked into git)
- Committed: Yes
- Used by: Tests that can't make real API calls

---

*Structure analysis: 2026-04-27*
