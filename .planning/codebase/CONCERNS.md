# Codebase Concerns

**Analysis Date:** 2026-04-27

## Tech Debt

**Force Unwraps in File Path Resolution:**
- Issue: Multiple critical file path operations use force unwraps when accessing file system URLs
- Files: 
  - `Sources/Kaset/Services/FavoritesManager.swift:28` - `FileManager.urls(...).first!`
  - `Sources/Kaset/Services/Scrobbling/ScrobbleQueue.swift:134` - `FileManager.urls(...).first!`
  - `Sources/Kaset/Utilities/ImageCache.swift:27` - `FileManager.urls(...).first!`
- Impact: App will crash if system returns empty URL array (extremely rare but possible)
- Fix approach: Use guard-let chains or assertion with informative error handling; add unit tests verifying URL retrieval

**Force Unwraps in LyricsProvider:**
- Issue: Forced unwraps when accessing first elements of optional arrays
- Files: `Sources/Kaset/Services/Lyrics/Providers/LRCLibProvider.swift:53,59`
- Impact: Crashes if filtered results become empty between validation and access
- Fix approach: Use optional chaining or safer unwrapping with fallback values

**HomeResponseParser params Force Unwrap:**
- Issue: Forced unwrap when constructing cache key with params
- Files: `Sources/Kaset/Services/API/Parsers/HomeResponseParser.swift:340`
- Impact: Could crash if params conditional is reached but value is nil
- Fix approach: Use nil-coalescing operator or safer unwrapping

**MiniPlayerWebView Coordinator Force Unwrap:**
- Issue: Force unwrap of coordinator in userContentController setup
- Files: `Sources/Kaset/Views/MiniPlayerWebView.swift:273`
- Impact: Crash if coordinator creation fails
- Fix approach: Use guard or throw error

## Complex Code Areas

**PlayerService Core Logic:**
- Issue: PlayerService is large and manages multiple concerns (playback, queue, library, web sync)
- Files: 
  - `Sources/Kaset/Services/Player/PlayerService.swift` (1568 lines across multiple files)
  - `Sources/Kaset/Services/Player/PlayerService+Queue.swift` (654 lines)
  - `Sources/Kaset/Services/Player/PlayerService+WebQueueSync.swift` (562 lines)
- Impact: High complexity makes it difficult to understand state transitions and debug playback issues
- Fix approach: Consider further decomposition; add architectural tests for state machine transitions

**API Parsing Complexity:**
- Issue: Multiple parser files with complex nested dictionary navigation
- Files:
  - `Sources/Kaset/Services/API/Parsers/PlaylistParser.swift` (1360 lines)
  - `Sources/Kaset/Services/API/Parsers/ArtistParser.swift` (922 lines)
  - `Sources/Kaset/Services/API/Parsers/HomeResponseParser.swift` (595 lines)
  - `Sources/Kaset/Services/API/Parsers/ParsingHelpers.swift` (559 lines)
- Impact: Brittle to API changes; difficult to debug when parsing fails
- Fix approach: Consider Decodable-based parsing where possible; add parser tests for each API version variant

**Synced Lyrics Service:**
- Issue: Multiple service layers (SyncedLyricsService, LyricsView, LyricsProvider implementations)
- Files: `Sources/Kaset/Views/LyricsView.swift` (534 lines)
- Impact: State management across services could cause sync issues
- Fix approach: Add integration tests for lyrics fetch → display → cleanup lifecycle

**View Size:**
- Issue: Several Views approach 900+ lines combining UI logic and state management
- Files:
  - `Sources/Kaset/Views/ArtistDetailView.swift` (920 lines)
  - `Sources/Kaset/Views/PlaylistDetailView.swift` (741 lines)
  - `Sources/Kaset/Views/QueueSidePanelView.swift` (687 lines)
- Impact: Difficult to test, high cognitive load, hidden state mutations
- Fix approach: Extract ViewModels for each view; split into smaller sub-views

**YTMusicClient:**
- Issue: Large monolithic API client (1568 lines)
- Files: `Sources/Kaset/Services/API/YTMusicClient.swift`
- Impact: Difficult to maintain, pagination token management scattered across multiple private methods
- Fix approach: Extract endpoint-specific sub-clients or use protocol-based endpoint definitions

## Known Fragile Areas

**Queue Synchronization (Web ↔ Native):**
- Files: `Sources/Kaset/Services/Player/PlayerService+WebQueueSync.swift`
- Why fragile: Complex state machine reconciling YouTube's autoplay with native queue management; multiple edge cases around repeat mode, shuffle, and track changes
- Safe modification: 
  - Add comprehensive logging at decision points
  - Write tests for each repeat mode + shuffle combination
  - Review "re-assert" comments for safety conditions
- Test coverage: 
  - `Tests/KasetTests/PlayerServiceWebQueueSyncTests.swift` exists but check for repeat-one edge cases
  - Missing: Tests for concurrent queue mutations during sync

**WebKit Message Handlers:**
- Files: `Sources/Kaset/Views/MiniPlayerWebView.swift`, `Sources/Kaset/Views/ExtensionOptionsView.swift`
- Why fragile: Message handler deregistration happens in `dismantleNSView` which may not be called reliably; duplicate handlers can accumulate
- Safe modification: Verify `dismantleNSView` is called before removing handlers; add assertion
- Test coverage: UI tests may not exercise dismantling reliably

**Authentication & Session Restoration:**
- Files: 
  - `Sources/Kaset/Services/Auth/AuthService.swift`
  - `Sources/Kaset/Services/Player/PlayerService+PlaybackRestoration.swift`
- Why fragile: Session restoration interacts with auth expiry; cookies persisted to Keychain; DEBUG mode writes plaintext cookies to disk
- Safe modification: Never modify persistence paths without understanding Keychain entry structure
- Test coverage: Integration tests needed for auth-expiry → re-login → resume playback flow

**Repeat One Mode:**
- Files: `Sources/Kaset/Services/Player/PlayerService+WebQueueSync.swift`
- Why fragile: Multiple "re-assert" safety nets for YouTube's autoplay behavior; complex condition checking
- Safe modification: Understand YouTube's autoplay bypass requirement before changing
- Test coverage: Dedicated UI test needed: play song → set repeat one → wait for track end → verify replayed

**Optimistic Playback State Updates:**
- Files: 
  - `Sources/Kaset/Services/Player/PlayerService+PlaybackControls.swift`
  - `Sources/Kaset/Services/Player/PlayerService+Library.swift`
- Why fragile: Optimistic state changes before API confirms; rollback on error may not restore full state
- Safe modification: Review all property mutations in these files before/after API calls
- Test coverage: Missing: Tests for API failure scenarios (network timeout, 401, 403)

**Image Cache with Memory Pressure:**
- Files: `Sources/Kaset/Utilities/ImageCache.swift`
- Why fragile: Uses `nonisolated(unsafe)` for DispatchSource memory pressure handler
- Safe modification: Ensure all cache operations are actor-isolated; test under memory pressure
- Test coverage: Performance tests exist but check memory pressure simulation

## Security Considerations

**Cookie Management:**
- Risk: Authentication cookies stored in Keychain (production) and plaintext `cookies.dat` file (DEBUG only)
- Files: 
  - `Sources/Kaset/Services/WebKit/WebKitManager+Cookies.swift:80`
  - `Sources/Kaset/Services/WebKit/WebKitManager.swift:150`
- Current mitigation: DEBUG mode writing only in dev builds; Keychain used for production
- Recommendations: 
  - Verify `cookies.dat` path is never accessible in release builds
  - Add code comment documenting Keychain entry structure for future maintainers
  - Consider periodic cookie refresh/rotation for long-lived sessions

**API Key Exposure:**
- Risk: YouTube Music API key hardcoded in client (standard practice but visible in binary)
- Files: `Sources/Kaset/Services/API/YTMusicClient.swift:53`
- Current mitigation: Public API key (same as web client); no sensitive scope
- Recommendations: Document that this is not a security credential; monitor for API quota abuse

**Foundation Models (Apple Intelligence):**
- Risk: User input sent to on-device models; potential data retention if models cache
- Files: `Sources/Kaset/Services/AI/FoundationModelsService.swift`
- Current mitigation: On-device processing only; no network transmission
- Recommendations: Verify no caching in model logs; test privacy with network monitoring tools

## Performance Bottlenecks

**Large Home/Explore Responses:**
- Problem: HomeResponseParser handling deep nested API responses; JSONSerialization allocation heavy
- Files: `Sources/Kaset/Services/API/Parsers/HomeResponseParser.swift`
- Cause: Full response parsed upfront; no streaming or lazy parsing
- Improvement path: 
  - Profile parsing time with large responses
  - Consider incremental parsing if > 100ms detected
  - Measure memory allocation in `measure {}` blocks

**Search Debouncing:**
- Problem: SearchView may issue queries without debouncing for every keystroke
- Files: `Sources/Kaset/Views/SearchView.swift`
- Cause: Unknown debounce interval or missing debounce logic
- Improvement path: Verify debounce is implemented; test with rapid input; profile API call frequency

**Image Download Concurrency:**
- Problem: ImageCache prefetch limited to 4 concurrent tasks; may serialize large thumb batches
- Files: `Sources/Kaset/Utilities/ImageCache.swift:12`
- Cause: Conservative concurrency limit (value: 4)
- Improvement path: Benchmark with 8 and 16 concurrent tasks; measure battery drain and network efficiency

**Memory Cache Pressure:**
- Problem: NSCache memory limit 50MB; may cause excessive evictions with large artwork
- Files: `Sources/Kaset/Utilities/ImageCache.swift:24`
- Cause: Fixed cache size; no adaptive sizing based on device RAM
- Improvement path: Query available RAM and scale cache dynamically; monitor eviction rate

**Queue Reorder Performance:**
- Problem: Reordering queue entries may trigger full table refresh
- Files: `Sources/Kaset/Views/QueueSidePanelView.swift`
- Cause: Unknown if NSTableView diff-based updates are used
- Improvement path: Profile reorder operations; verify animations are smooth; check for unnecessary re-renders

## Test Coverage Gaps

**Untested Area: PlayerService State Machine:**
- What's not tested: Full state transitions (idle → loading → playing → ended → repeat one replayed)
- Files: `Sources/Kaset/Services/Player/PlayerService.swift`
- Risk: State corruption not caught until user action fails
- Priority: **High** - Playback is core functionality
- Approach: Add state machine tests with before/after verification

**Untested Area: API Error Handling:**
- What's not tested: Network failures (timeout, 502, 503), auth failures (401, 403), rate limiting (429)
- Files: `Sources/Kaset/Services/API/YTMusicClient.swift`
- Risk: Unhandled errors crash app or leave UI in broken state
- Priority: **High** - Users with bad connections or auth issues will hit these
- Approach: Add throwing test variants; mock URLSession to inject errors

**Untested Area: Playback Restoration:**
- What's not tested: Session restoration on app relaunch; seekbar position accuracy after restore
- Files: `Sources/Kaset/Services/Player/PlayerService+PlaybackRestoration.swift`
- Risk: Users lose queue/position; confusing UX
- Priority: **High** - Frequent use case
- Approach: Add integration tests with synthetic saved sessions

**Untested Area: Queue Undo/Redo:**
- What's not tested: Undo/redo history behavior with multiple rapid mutations
- Files: `Sources/Kaset/Services/Player/PlayerService+Queue.swift`
- Risk: Undo history corruption
- Priority: **Medium** - Feature is less critical
- Approach: Add property-based tests with randomized queue operations

**Untested Area: Lyrics Sync Accuracy:**
- What's not tested: Line timing accuracy when playback progress changes
- Files: `Sources/Kaset/Views/SyncedLyricsDisplayView.swift`
- Risk: Lyrics display out of sync with playback
- Priority: **Medium** - Nice-to-have feature
- Approach: Add synthetic playback progress tests

**Untested Area: Extension Manager:**
- What's not tested: Extension process lifecycle (launch, crash, recovery)
- Files: `Sources/Kaset/Services/ExtensionsManager.swift`
- Risk: Extensions hang or fail silently
- Priority: **Medium** - Not all users enable extensions
- Approach: Add mock extension process tests

**Untested Area: Equalizer Settings Persistence:**
- What's not tested: Equalizer settings survive app restart
- Files: `Sources/Kaset/Services/Audio/EqualizerService.swift`
- Risk: Users lose custom presets
- Priority: **Low** - Settings stored reliably but no round-trip test
- Approach: Add persistence tests

## Scaling Limits

**API Cache Capacity:**
- Current capacity: Max 50 entries with LRU eviction
- Limit: Heavy browsing can evict frequently-used pages (home, search results)
- Scaling path:
  - Monitor cache hit rate in DiagnosticsLogger
  - Increase maxEntries to 100 if hit rate < 80%
  - Consider compression for large responses

**Queue Size:**
- Current capacity: Queue stored in memory; no practical limit enforced
- Limit: If queue grows > 10,000 songs, UI updates may lag
- Scaling path:
  - Add queue size limit enforcement
  - Implement virtual scrolling in queue view if not present
  - Consider persistent queue storage for massive queues

**Image Cache Disk:**
- Current capacity: 200MB disk cache
- Limit: May exceed disk quota on systems with tight storage
- Scaling path:
  - Monitor disk usage periodically
  - Allow user-configurable cache size
  - Implement more aggressive eviction for old images

## Dependencies at Risk

**No identified at-risk third-party dependencies** - Project follows "no third-party frameworks" policy (uses Apple frameworks only).

**Internal Dependency: WebKit/WKWebView:**
- Risk: YouTube Music player initialization depends on user interaction; autoplay blocked in background
- Impact: Playback requires visible WebView; cannot play in background without visible UI
- Migration plan: Monitor YouTube Music API for native playback endpoint; current architecture requires WebView due to DRM

**Internal Dependency: Foundation Models (Apple Intelligence):**
- Risk: Only available on macOS 15.1+; feature degrades gracefully on older OS
- Impact: AI-powered features disabled on unsupported macOS versions
- Mitigation: Version guards in place; documented in IntelligenceSettingsView

## Missing Critical Features

**No feature gaps identified** - Core playback, queue management, library sync, and API integration are complete.

**Potential Enhancement:** Background playback with remote commands requires further integration testing to ensure macOS remote controls work correctly with WebView-based playback.

---

*Concerns audit: 2026-04-27*
