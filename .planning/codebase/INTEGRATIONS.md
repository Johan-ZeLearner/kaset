# External Integrations

**Analysis Date:** 2026-04-27

## APIs & External Services

**YouTube Music (Primary Data Source):**
- API Endpoint: `https://music.youtube.com/youtubei/v1`
- Client: `YTMusicClient` (`Sources/Kaset/Services/API/YTMusicClient.swift`)
- API Key: Public key embedded in client code (`AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30`)
- Client Version: `1.20231204.01.00` (WEB_REMIX user agent)
- Methods:
  - `browse` - Homepage, explore, charts, moods/genres, new releases, podcasts, history
  - `search` - Song, artist, album, playlist, podcast search
  - `next` - Queue generation and mixing
  - `player` - Playback information (lyrics, metadata)
  - Pagination via continuation tokens for infinite scroll
- Response Parsing: Custom parsers in `Services/API/Parsers/` for:
  - Home, search, playlists, artists, podcasts, lyrics, radio queues
- Caching: Integrated `APICache` with configurable TTL per content type
- Auth: SAPISID cookie from Google authentication (extracted via `AuthService`)

**YouTube Music Playback (WebKit/DRM):**
- Embedded URL: `https://music.youtube.com/watch?v=VIDEO_ID`
- Transport: WKWebView (`MiniPlayerWebView`) for DRM-protected audio streaming
- Location: `Sources/Kaset/Views/MiniPlayerWebView.swift`
- Purpose: YouTube Music uses DRM-protected audio; playback must occur in authorized WebView

**Google Authentication:**
- Service: Google OAuth2
- Login URL: `https://accounts.google.com/ServiceLogin?service=youtube...`
- Redirect: Back to `https://music.youtube.com/`
- Cookie: `__Secure-3PAPISID` (primary) or `SAPISID` (fallback) from Google domain
- Storage: WebKit persistent data store (`WKWebsiteDataStore.default()`) with Keychain backup
- Auth Service: `Sources/Kaset/Services/Auth/AuthService.swift`
- Cookie Management: `Sources/Kaset/Services/WebKit/WebKitManager+Cookies.swift`

**Lyrics Providers:**
- LRCLib (Primary):
  - API: `https://lrclib.net/api/search`
  - Query params: `track_name`, `artist_name`
  - Provider: `LRCLibProvider` (`Sources/Kaset/Services/Lyrics/Providers/LRCLibProvider.swift`)
  - Response: JSON with synced (LRC format) and plain lyrics
  - Fallback: YouTube Music synced lyrics via `YTMusicClient.getPlayer()`

- YouTube Music (Secondary):
  - Via `YTMusicClient.getPlayer()` call
  - Returns: Synced lyrics objects parsed by `SyncedLyricsService`
  - Parser: `Services/API/Parsers/LyricsParser.swift`

**Last.fm Scrobbling:**
- Auth Proxy: Cloudflare Worker (for API request signing)
- Worker URL: Configurable via:
  - Environment variable: `KASET_LASTFM_WORKER_URL`
  - Info.plist key: `LastFMWorkerURL`
  - Default: `https://kaset-lastfm.sozercan.workers.dev`
- Service: `LastFMService` (`Sources/Kaset/Services/Scrobbling/LastFMService.swift`)
- Flow:
  1. Request auth token from Worker
  2. User authorizes at Last.fm
  3. Poll Worker for session token
  4. Store session key in Keychain (`KeychainCredentialStore`)
  5. Send scrobbles to Worker (signed via Worker, not client-side)
- Credential Storage: Keychain (session key, username)
- Scrobble Queue: `ScrobbleQueue` batches tracks for async submission

**GitHub Releases (Update Metadata):**
- API: GitHub REST API (used by WhatsNewProvider)
- Endpoints:
  - Get latest release: `https://api.github.com/repos/sozercan/kaset/releases/latest`
  - Get release by tag: `https://api.github.com/repos/sozercan/kaset/releases/tags/{tag}`
- Location: `Sources/Kaset/WhatsNewProvider.swift`
- Purpose: Fetch "What's New" information for app release notes
- User-Agent: `Kaset/1.0`

## Data Storage

**Databases:**
- None (no persistent database; state stored in Keychain and WebKit)

**File Storage:**
- Keychain - Session tokens, Last.fm credentials:
  - YouTube Music SAPISID (not stored, refreshed per session)
  - Last.fm session key and username
- WebKit Data Store - Authentication cookies (`WKWebsiteDataStore.default()`)
- Application Support - Debug cookie export (macOS only, for `api-explorer` CLI)
  - Path: `~/Library/Application Support/Kaset/cookies.dat`
- User Defaults - App settings (via `SettingsManager`):
  - Playback preferences, UI state, Last.fm settings

**Caching:**
- In-Memory: `APICache` for YouTube Music responses with per-content-type TTL
- System URLCache: Transport-level HTTP caching via `URLSession` configuration

## Authentication & Identity

**Auth Provider:**
- Google OAuth2 (implicit via cookies in embedded WebKit)
- No explicit OAuth token flow; authentication is cookie-based

**Implementation:**
- `AuthService` - Tracks login state, initiates login flow
- `WebKitManager` - Manages persistent authentication cookies
- Cookie Extraction: SAPISID from browser cookies (used in `X-SAPISID` header for API requests)
- Token Signing: Server-side signing via `CryptoKit` (SHA256 for request signatures in API calls)

## Monitoring & Observability

**Error Tracking:**
- None (no external error tracking service)

**Logs:**
- Local logging via `DiagnosticsLogger` (wraps `os.Logger`)
- Channels: auth, api, webKit, player, scrobbling, updater, commandBar, lyrics
- Purpose: Debug-only, not sent externally

## CI/CD & Deployment

**Hosting:**
- GitHub Releases (as DMG files)
- Homebrew tap: `sozercan/repo/kaset`

**Update Distribution:**
- Sparkle framework for macOS auto-updates
- Feed URL: `https://raw.githubusercontent.com/sozercan/kaset/main/appcast.xml`
- Feed Format: RSS with Sparkle extensions (`.enclosure` with EdDSA signature)
- Signature: Public EdDSA key in `Info.plist` for update verification
- Check interval: Default 24 hours (configurable via `SUScheduledCheckInterval`)

**CI Pipeline:**
- GitHub Actions (inferred from `appcast.xml` and release distribution)
- Build artifact: DMG containing unsigned app

## Environment Configuration

**Required env vars:**
- None (all critical configuration in Info.plist or defaults)

**Optional env vars:**
- `KASET_LASTFM_WORKER_URL` - Last.fm Cloudflare Worker endpoint
- `UI_TEST_MODE` - Enables mock auth for tests
- `SKIP_AUTH` - Bypasses auth check in test mode

**Secrets location:**
- Keychain (macOS system keychain for credentials)
- Sparkle public key (in `Info.plist`, no secret)
- Cookies (WebKit persistent storage, not readable as files in normal operation)

**Configuration files:**
- `Info.plist` - App metadata, Sparkle feed URL, AppleScript definition, audio permissions
- `Kaset.entitlements` - macOS sandbox entitlements
- `.env` files: Not used

## Webhooks & Callbacks

**Incoming:**
- URL scheme: `kaset://play?v=VIDEO_ID` - Deep link for direct playback
  - Handler: `URLHandler` (`Sources/Kaset/Services/URLHandler.swift`)
  - Supported formats:
    - Songs: `kaset://play?v=dQw4w9WgXcQ`
    - Playlists: `kaset://browse?list=PLxxx` or `kaset://play?list=PLxxx`
    - Albums: `kaset://browse?list=MPRExxx`
    - Artists: `kaset://browse?channel=UCxxx` or `kaset://play?channel=UCxxx`

**Outgoing:**
- Last.fm Scrobble API (via Cloudflare Worker) - Async submission of played tracks
- Share endpoints (create share URLs):
  - Songs: `https://music.youtube.com/watch?v={id}`
  - Playlists: `https://music.youtube.com/playlist?list={id}`
  - Albums: `https://music.youtube.com/browse/{id}`
  - Artists: `https://music.youtube.com/channel/{id}`

## API Rate Limiting

**YouTube Music:**
- No explicit rate limits documented in code
- Connection pooling: 6 connections per host (HTTP/2 multiplexing automatic)
- Timeout: 15 seconds per request, 30 seconds per resource

**LRCLib:**
- No explicit rate limits or authentication required
- User-Agent: `Kaset/1.0`

**Last.fm:**
- Handled by Cloudflare Worker proxy (no client-side rate limiting)

## Brand Accounts

**Multi-Account Support:**
- YouTube Music brand accounts supported via `YTMusicClient.brandIdProvider`
- Brand ID: 21-digit number from Google My Account > Brand Accounts
- Implementation: Optional provider closure passed to client
- User Index: Global index for account switching (0 = primary, 1+ = brand accounts)

---

*Integration audit: 2026-04-27*
