# Requirements: Kaset — Sonos S1 Audio Integration

**Defined:** 2026-04-27
**Core Value:** A first-class native macOS YouTube Music experience that also reaches the user's actual home audio gear — including Sonos systems that don't speak AirPlay.

## v1 Requirements

### SPIKE — gate before any build

The spike's deliverable is a structured pass/fail report against four binary technical bets, plus measured latency. If any bet fails without a known workaround, the milestone re-scopes per `PROJECT.md`.

- [ ] **SPIKE-01**: File `com.apple.developer.networking.multicast` entitlement request with Apple on day 1 (1–2 week SLA — calendar-time blocker for SSDP)
- [ ] **SPIKE-02**: Validate that a second consumer of the existing WebKit Core Audio process tap coexists with `EqualizerService` without HAL conflict or audible artifact
- [ ] **SPIKE-03**: Validate that Sonos S1 accepts our HTTP audio stream end-to-end — resolves the encoder-format fork (AAC-in-ADTS / raw WAV / vendored LAME-with-approval)
- [ ] **SPIKE-04**: Validate that Swift-native SSDP discovery (`NWConnectionGroup`) finds the user's S1 hardware from inside the sandboxed app
- [ ] **SPIKE-05**: Measure end-to-end pause-to-silence latency against the user's actual Sonos hardware (target: <2s; honest baseline: AirConnect's 8–10s)
- [ ] **SPIKE-06**: Spike report — per-bet go/no-go + recommended encoder format + measured latency → roadmap continues or re-scopes

### FOUNDATION — pre-Sonos refactor (mandatory before Sonos audio)

Adding a second independent Core Audio tap on the same WebKit PIDs produces undefined HAL behavior. The existing `EqualizerService`-owned tap must be refactored into a multi-consumer coordinator first. This phase ships standalone value to EQ regardless of Sonos outcome.

- [ ] **FOUND-01**: Introduce `WebKitAudioTapCoordinator` owning the single Core Audio process tap on `com.apple.WebKit.WebContent` / `com.apple.WebKit.GPU`
- [ ] **FOUND-02**: Migrate `EqualizerService` to consume from `WebKitAudioTapCoordinator` instead of owning the tap directly
- [ ] **FOUND-03**: Multi-consumer fan-out supports N consumers without buffer underrun
- [ ] **FOUND-04**: Existing EQ behavior unchanged — no audible artifacts, no measurable latency increase, all current EQ tests still pass

### DISCOVERY — find Sonos zones (independently testable, no audio)

- [ ] **DISC-01**: SSDP M-SEARCH discovers Sonos S1 zones on the LAN
- [ ] **DISC-02**: Zone room names parsed from device description via `GetZoneAttributes`
- [ ] **DISC-03**: Manual-IP entry fallback when SSDP returns nothing (VLAN / hostile Wi-Fi case)
- [ ] **DISC-04**: Live device roster updates as zones join/leave the network

### CONTROL — drive transport + volume via SOAP (no audio yet)

- [ ] **CTRL-01**: SOAP `Play` / `Pause` / `Stop` issued to a discovered zone (testable against existing Sonos content before Kaset audio is wired)
- [ ] **CTRL-02**: SOAP `SetVolume` / `SetMute` per zone via `RenderingControl`
- [ ] **CTRL-03**: SOAP error surface mapped to typed `SonosError` enum with retry semantics (mirroring `YTMusicError` pattern)
- [ ] **CTRL-04**: Logging via new `DiagnosticsLogger.sonos` subsystem

### AUDIO — capture + relay pipeline

Depends on FOUNDATION (coordinator must land first) and SPIKE-03 (encoder format decided).

- [ ] **AUDIO-01**: PCM capture registered as a consumer on `WebKitAudioTapCoordinator`
- [ ] **AUDIO-02**: Encoder pipeline (format chosen by SPIKE-03) → bounded `AsyncStream<Data>` ring buffer with backpressure
- [ ] **AUDIO-03**: HTTP relay server on `NWListener` serves the live stream at `/stream/<uuid>.<ext>`
- [ ] **AUDIO-04**: HTTP framing matches Sonos S1 requirements — HTTP/1.0, `Connection: close`, no `Content-Length`, no `Transfer-Encoding: chunked`, `x-rincon-mp3radio://<mac-ip>:<port>/stream.<ext>` URL scheme

### OUTPUT — end-to-end UX

- [ ] **OUT-01**: AirPlay-style picker popover in `PlayerBar` lists discovered zones
- [ ] **OUT-02**: Single source-of-truth output toggle: "This Mac" vs "Sonos zone X" via new `AudioOutputRouter`
- [ ] **OUT-03**: `SetAVTransportURI` call includes minimal DIDL-Lite metadata (title + artist) so Sonos app shows useful track info
- [ ] **OUT-04**: Kaset transport (play / pause / next / prev) routes to the active output
- [ ] **OUT-05**: Kaset volume slider routes to the active output (Sonos volume when Sonos selected)
- [ ] **OUT-06**: "Mac must stay awake" indicator visible on the picker when a Sonos zone is the active output
- [ ] **OUT-07**: Switching back to "This Mac" stops the relay and sends Sonos `Stop`
- [ ] **OUT-08**: Last-selected zone restored on app launch (selection only — never auto-play)

## v1.x Requirements (post-v1, before v2)

These are "next-up" once v1 ships and the core works. Not in the v1 roadmap, but tracked.

### EVENT — bidirectional state sync via UPnP GENA

- **EVENT-01**: SUBSCRIBE / UNSUBSCRIBE to `AVTransport` + `RenderingControl` services on the active zone
- **EVENT-02**: Inbound `NOTIFY` callback HTTP route (shared `NWListener` with audio relay)
- **EVENT-03**: `LastChange` double-encoded XML body parser
- **EVENT-04**: Subscription auto-renewal before timeout
- **EVENT-05**: Volume changed in Sonos app reflects in Kaset's slider; transport state from elsewhere reflects in Kaset's PlayerBar

### POLISH — quality-of-life

- **POLISH-01**: Album art metadata in DIDL-Lite (`upnp:albumArtURI` pointing to YouTube Music thumbnail)
- **POLISH-02**: Smart re-bond after Mac wake / brief Wi-Fi loss
- **POLISH-03**: AppleScript + NL command extensions ("send playback to Living Room")
- **POLISH-04**: Diagnostics overlay (last SOAP error, relay URL, firmware version via `GetZoneInfo`)

### GROUP — multi-zone playback

- **GROUP-01**: Resolve `ZoneGroupTopology` to route commands to the group coordinator
- **GROUP-02**: Group-aware volume via `GroupRenderingControl`
- **GROUP-03**: Read existing groups (never create from Kaset — see Out of Scope)

## v2 Requirements

Acknowledged but not actionable until v1 + v1.x are validated in the wild.

### EQ-ON-SONOS

- **EQONS-01**: Decide whether `EqualizerService` DSP applies to the Sonos stream or is bypassed; UI surface for that decision

### GAPLESS

- **GAPLESS-01**: Server-side continuous stream architecture supporting cross-track gapless playback (significant complexity — fork from per-track relay model)

### S2-MODERN

- **S2-01**: Sonos S2 modern Local Control API integration (only relevant if user upgrades from S1)

## Out of Scope

Explicit exclusions. The reasoning matters — these will be re-proposed otherwise.

| Feature | Reason |
|---------|--------|
| Sonos Music Service / SMAPI partnership | Requires Sonos partnership + YouTube Music licensing — neither achievable for an indie macOS client |
| "Sonos keeps playing after Mac sleeps or Kaset quits" | Architecturally impossible with local relay; only SMAPI could deliver this |
| Auto-resume Sonos playback on app launch | Silently interrupts other Sonos usage; restore picker selection only, never auto-play |
| Creating Sonos stereo pairs / bonded zones from Kaset | UPnP actions exist but `ChannelMapSet` mistakes desynchronize the user's pair — direct to Sonos S1 app |
| Creating Sonos zone groups from Kaset | Failure modes orphan coordinators and split audio — read existing groups only |
| Hi-res / lossless streaming to Sonos S1 | S1 caps FLAC at 16-bit; YouTube Music source is already lossy — encoding lossy to lossless is busywork |
| In-Sonos-app playback control (queue / search / browse) | Requires SMAPI partnership |
| Multi-source mixing / ducking | Mac is an HTTP server from Sonos's POV; ducking causes audible stream glitches |
| Seek via `AVTransport::Seek` against the live relay | Sonos returns error 701 on non-seekable content — seek must happen in the WKWebView, not forwarded to Sonos |
| Non-Sonos UPnP renderer support | Lock to Sonos manufacturer string for v1; generic UPnP is a different product |
| ScreenCaptureKit-based audio capture | DRM-protected WKWebView audio is filtered out of SCK at the application level — research confirmed `ProcessTapHelper` is the only working path |
| Third-party Swift packages for UPnP / Sonos / encoding | Repo policy (`CLAUDE.md`); LAME vendoring requires explicit human approval at SPIKE-03 if AAC fork fails |
| Modern Sonos S2 Cloud Control API | User's test gear is S1; defer to v2 |

## Traceability

Empty until roadmap creation populates it.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SPIKE-01 | TBD | Pending |
| SPIKE-02 | TBD | Pending |
| SPIKE-03 | TBD | Pending |
| SPIKE-04 | TBD | Pending |
| SPIKE-05 | TBD | Pending |
| SPIKE-06 | TBD | Pending |
| FOUND-01 | TBD | Pending |
| FOUND-02 | TBD | Pending |
| FOUND-03 | TBD | Pending |
| FOUND-04 | TBD | Pending |
| DISC-01 | TBD | Pending |
| DISC-02 | TBD | Pending |
| DISC-03 | TBD | Pending |
| DISC-04 | TBD | Pending |
| CTRL-01 | TBD | Pending |
| CTRL-02 | TBD | Pending |
| CTRL-03 | TBD | Pending |
| CTRL-04 | TBD | Pending |
| AUDIO-01 | TBD | Pending |
| AUDIO-02 | TBD | Pending |
| AUDIO-03 | TBD | Pending |
| AUDIO-04 | TBD | Pending |
| OUT-01 | TBD | Pending |
| OUT-02 | TBD | Pending |
| OUT-03 | TBD | Pending |
| OUT-04 | TBD | Pending |
| OUT-05 | TBD | Pending |
| OUT-06 | TBD | Pending |
| OUT-07 | TBD | Pending |
| OUT-08 | TBD | Pending |

**Coverage:**
- v1 requirements: 30 total
- Mapped to phases: 0
- Unmapped: 30 ⚠️ (will be filled by roadmap)

---
*Requirements defined: 2026-04-27*
*Last updated: 2026-04-27 after initial definition*
