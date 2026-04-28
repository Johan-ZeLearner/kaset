# Roadmap: Kaset — Sonos S1 Audio Integration

## Overview

This milestone takes Kaset from "macOS audio output only" to "first-class native YouTube Music client that also reaches the user's Sonos S1 gear." The path is gated by a spike: four independent technical bets must pass before any production code lands. If they pass, the build sequence is dependency-driven — refactor the existing Core Audio tap into a multi-consumer coordinator (standalone value to EQ regardless of Sonos outcome), prove discovery + SOAP control plumbing in isolation, build the capture-encode-relay audio pipeline, then wire it into the PlayerBar UX. If any bet fails without a known workaround, the milestone re-scopes.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Spike** - Time-boxed validation of four technical bets; binary go/no-go gate before any production code
- [ ] **Phase 2: Foundation Refactor** - Extract WebKitAudioTapCoordinator so EQ and Sonos can share one Core Audio process tap
- [ ] **Phase 3: Discovery + Control Plane** - SSDP discovery + UPnP/SOAP transport and volume control against Sonos S1 (no Kaset audio yet)
- [ ] **Phase 4: Audio Capture + HTTP Relay** - PCM capture → encoder → bounded ring buffer → HTTP relay server in Sonos S1 wire format
- [ ] **Phase 5: Output Integration UX** - AudioOutputRouter + PlayerBar picker; end-to-end "pick Sonos, hear Kaset" experience

## Phase Details

### Phase 1: Spike
**Goal**: Validate the four independent technical bets against the user's actual S1 hardware and produce a binary go/no-go report. Spike code lives in `Sources/APIExplorer/main.swift` and is throwaway — production `Services/Sonos/` code begins only after this phase passes. **SPIKE-01 (multicast entitlement filing) MUST be the first action of day 1**: Apple's 1–2 week SLA is a calendar blocker for SPIKE-04 testing in the sandboxed app.
**Depends on**: Nothing (first phase)
**Requirements**: SPIKE-01, SPIKE-02, SPIKE-03, SPIKE-04, SPIKE-05, SPIKE-06
**Success Criteria** (what must be TRUE):
  1. `com.apple.developer.networking.multicast` entitlement requested with Apple on day 1 of the phase (timestamped evidence in spike report)
  2. Spike harness in `Sources/APIExplorer/main.swift` extends with at least `sonos discover` and `sonos play` subcommands and runs cleanly via `swift run api-explorer`
  3. Static test audio file plays out of the user's actual Sonos S1 hardware via hand-built `SetAVTransportURI` + `Play` for >5 minutes uninterrupted
  4. Pause-to-silence latency measured against the user's actual Sonos hardware with a stopwatch (5 trials, median reported)
  5. Spike report committed at `.planning/phases/01-spike/REPORT.md` with explicit go/no-go on each of SPIKE-02 / SPIKE-03 / SPIKE-04 / SPIKE-05 plus chosen encoder format (AAC-in-ADTS / WAV / vendor-LAME-with-approval) and SSDP transport decision (`NWConnectionGroup` vs BSD socket fallback)
**Plans**: 6 plans
  - [x] 01-01-PLAN.md — Day-1 entitlement filing + api-explorer `sonos` dispatcher scaffold + WAV/AAC fixtures
  - [x] 01-02-PLAN.md — SPIKE-04 SSDP discovery via NWConnectionGroup with BSD socket fallback
  - [ ] 01-03-PLAN.md — SPIKE-03 NWListener HTTP/1.0 relay + SOAP-driven Sonos playback (WAV first, AAC second)
  - [ ] 01-04-PLAN.md — SPIKE-02 dual-consumer tap test via in-place fan-out at EqualizerAudioEngine.performRender (gated by #if SPIKE_TAP_COEXIST)
  - [ ] 01-05-PLAN.md — SPIKE-05 5-trial manual-stopwatch pause-to-silence latency measurement
  - [ ] 01-06-PLAN.md — SPIKE-06 thin spike-all runner + REPORT.md generation with full LAN-IP/USN redaction + milestone-level decision

### Phase 2: Foundation Refactor
**Goal**: Refactor the existing `EqualizerService`-owned Core Audio process tap into a standalone `WebKitAudioTapCoordinator` with multi-consumer fan-out. This is **mandatory before any Sonos audio work** because adding a second independent tap on the same WebKit PIDs (`com.apple.WebKit.WebContent` / `com.apple.WebKit.GPU`) produces undefined HAL behavior. This phase ships standalone value to EQ regardless of Sonos outcome — it is independently mergeable.
**Depends on**: Phase 1 (spike must pass; specifically SPIKE-02 confirms second-consumer coexistence is viable)
**Requirements**: FOUND-01, FOUND-02, FOUND-03, FOUND-04
**Success Criteria** (what must be TRUE):
  1. `WebKitAudioTapCoordinator` owns the single tap on `com.apple.WebKit.WebContent` / `com.apple.WebKit.GPU` and exposes a typed consumer-registration API
  2. `EqualizerService` UI behaves identically before/after the refactor (manual A/B test on a known-loud track — no audible artifacts, no audible latency change)
  3. All existing `EqualizerService` unit tests still pass (`swift test --skip KasetUITests`)
  4. Frame-counter test demonstrates two simultaneous registered consumers receive PCM frames without buffer underrun or drift over a 60-second sustained playback test
  5. ADR documenting the refactor and fan-out contract committed under `docs/adr/`
**Plans**: TBD

### Phase 3: Discovery + Control Plane
**Goal**: Build the SSDP discovery + SOAP control plumbing as a working "control existing Sonos playback from Kaset" capability — no Kaset audio is involved yet. This proves the entire UPnP/SOAP stack against the user's real hardware in isolation, surfaces the multicast entitlement and sandbox issues early, and produces a typed `SonosError` enum mirroring `YTMusicError`. All exposed via the existing `api-explorer` convention.
**Depends on**: Phase 1 (spike must confirm SSDP works in sandboxed app per SPIKE-04)
**Requirements**: DISC-01, DISC-02, DISC-03, DISC-04, CTRL-01, CTRL-02, CTRL-03, CTRL-04
**Success Criteria** (what must be TRUE):
  1. `swift run api-explorer sonos discover` lists the user's S1 zones by room name within 3 seconds of invocation
  2. Manual-IP fallback works for the same listing when SSDP is suppressed (simulated VLAN case)
  3. User can issue Play / Pause / Stop / SetVolume / SetMute against any discovered zone via `swift run api-explorer sonos <action>` and the Sonos audibly responds to existing Sonos-native content (not Kaset audio)
  4. Live device roster updates within 5 seconds when a known zone is power-cycled (simulated join/leave)
  5. SOAP error responses (forced via malformed action) surface as typed `SonosError` cases with retry semantics, logged via the new `DiagnosticsLogger.sonos` subsystem
**Plans**: TBD

### Phase 4: Audio Capture + HTTP Relay
**Goal**: Build the audio half of the bridge — register a Sonos-encoder consumer on `WebKitAudioTapCoordinator`, encode PCM into the format chosen by SPIKE-03, drain it through a bounded ring buffer, and serve it from an `NWListener`-based HTTP server in the exact wire format Sonos S1 requires (HTTP/1.0, `Connection: close`, no `Content-Length`, no chunked encoding, `x-rincon-mp3radio://` URI scheme). This is the first time Kaset audio reaches a Sonos speaker — but invoked from the test harness, not the PlayerBar.
**Depends on**: Phase 2 (coordinator must land first), Phase 1 (encoder format decision from SPIKE-03)
**Requirements**: AUDIO-01, AUDIO-02, AUDIO-03, AUDIO-04
**Success Criteria** (what must be TRUE):
  1. PCM capture registered as a consumer on `WebKitAudioTapCoordinator` does not affect EQ behavior (re-validates Phase 2 with second real consumer)
  2. Encoder pipeline produces a valid stream in the SPIKE-03-chosen format, written to a `.wav`/`.aac`/`.mp3` file from the harness and verified playable in QuickTime
  3. Static test audio file served from the HTTP relay plays through to the user's S1 zone for >30 seconds without dropout (invoked via test harness, not PlayerBar)
  4. Live-encoded Kaset audio (current WebView track) plays through to the user's S1 zone for >5 minutes uninterrupted, invoked from the test harness
  5. HTTP response headers verified (via `curl -v` from another LAN device) to use HTTP/1.0, `Connection: close`, no `Content-Length`, no `Transfer-Encoding: chunked`, and the URL handed to Sonos uses the `x-rincon-mp3radio://` scheme
**Plans**: TBD

### Phase 5: Output Integration UX
**Goal**: Wire all subsystems into the real user flow. Introduce `AudioOutputRouter` as the single source-of-truth for active output, build the AirPlay-style picker popover in `PlayerBar`, route PlayerService transport and volume to the active output, and handle the lifecycle (cleanup on switch-back, Mac-stay-awake indicator, last-zone restoration). This is the "first time the user hears Kaset audio out of their Sonos" moment from the actual Kaset UI.
**Depends on**: Phase 3 (discovery + control), Phase 4 (audio + relay)
**Requirements**: OUT-01, OUT-02, OUT-03, OUT-04, OUT-05, OUT-06, OUT-07, OUT-08
**Success Criteria** (what must be TRUE):
  1. User can pick a Sonos zone in `PlayerBar` and hear the current Kaset track playing on it within 5 seconds of the picker selection
  2. Track title + artist appear correctly in the Sonos S1 app for the active Kaset track (DIDL-Lite metadata via `SetAVTransportURI`), including adversarial titles like `Tom & Jerry's "Best" — café`
  3. Play / pause / next / previous in PlayerBar route to the active output (Sonos when Sonos selected, system when "This Mac" selected); volume slider in PlayerBar routes to the active output and reflects current Sonos volume on selection
  4. Switching from Sonos zone back to "This Mac" stops the relay, sends Sonos `Stop`, and audio resumes through Mac speakers within 3 seconds with no orphaned silent stream on the Sonos
  5. "Mac must stay awake" indicator visible on the picker whenever a Sonos zone is the active output
  6. Last-selected Sonos zone is restored as the picker selection on app relaunch (selection only — playback does NOT auto-start)
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

**Parallelization notes (per `config.json` `parallelization: true`):**
- Phase 1 plans: largely sequential (SPIKE-01 must be day 1; SPIKE-02 → 03 → 04 → 05 each gates the next; SPIKE-06 is the report)
- Phase 2 plans: sequential (refactor → migrate → multi-consumer → regression validation)
- Phase 3 plans: **DISC and CTRL plans can run in parallel** once `SonosDevice` model + `DiagnosticsLogger.sonos` subsystem are scaffolded; they share no mutable state
- Phase 4 plans: sequential (capture → encoder → relay → wire-format validation each builds on the previous)
- Phase 5 plans: **router + picker UI plans can run in parallel** with the lifecycle/persistence plan once `AudioOutput` enum is defined

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Spike | 2/6 | In Progress|  |
| 2. Foundation Refactor | 0/TBD | Not started | - |
| 3. Discovery + Control Plane | 0/TBD | Not started | - |
| 4. Audio Capture + HTTP Relay | 0/TBD | Not started | - |
| 5. Output Integration UX | 0/TBD | Not started | - |
