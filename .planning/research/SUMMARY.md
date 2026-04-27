# Project Research Summary

**Project:** Kaset — Sonos S1 Audio Integration Milestone
**Domain:** Mac-side real-time audio relay to Sonos S1 via HTTP + UPnP/SOAP (brownfield Swift 6 / SwiftUI / macOS 26)
**Researched:** 2026-04-27
**Confidence:** MEDIUM-HIGH overall (HIGH on protocol surface and existing code reuse; MEDIUM on Sonos S1 firmware behaviour and encoder format acceptance — both require spike confirmation)

---

## Executive Summary

Kaset already ships the hardest half of this milestone. The existing `EqualizerService` proves that real-time audio can be captured from the hidden `WKWebView` using a Core Audio process tap (`ProcessTapHelper.swift`) — the exact mechanism the Sonos pipeline needs. The right build strategy is therefore to reuse that proven tap path, not to introduce ScreenCaptureKit or any other new capture API. What is genuinely unvalidated is the output half: whether Sonos S1 will accept an HTTP audio stream in AAC-in-ADTS format (the only native macOS encoder option), whether end-to-end latency can be kept under 2 seconds given Sonos's documented ~2-second pre-buffer, and whether Swift-native SSDP discovery works correctly inside an App Sandbox without the Apple-gated multicast entitlement.

Because four independent technical bets remain unconfirmed, the milestone must start with a time-boxed spike before any build phase is scoped. The spike's output is a binary yes/no on each bet, not working product code. If all four pass, an eight-phase build sequence follows: (1) refactor the existing tap into a `WebKitAudioTapCoordinator` that fans out to multiple consumers — this ships standalone value to the EQ regardless of Sonos outcome; (2) discovery and SOAP control; (3) audio capture pipeline; (4) HTTP relay server; (5) end-to-end `SonosOutputSession` glue; (6) UPnP event subscriptions for bidirectional state sync; and (7) polish. The coordinator refactor is mandatory before any Sonos audio work begins because adding a second independent tap on the same WebKit PIDs produces undefined Core Audio behaviour.

The two most important facts for planning are: (a) the multicast entitlement (`com.apple.developer.networking.multicast`) must be requested from Apple at spike start, not at build start — Apple's approval turnaround is one to two weeks and it is a hard calendar blocker for SSDP discovery; and (b) the encoder format fork (AAC-in-ADTS vs vendored LAME vs raw WAV) must be resolved in the spike before the audio pipeline can be scoped. Absent a native MP3 encoder on macOS, AAC-in-ADTS is the recommended attempt, but Sonos S1 acceptance of AAC over `x-rincon-mp3radio://` is unconfirmed and must be treated as a hypothesis, not a guarantee.

---

## Key Findings

### Recommended Stack

The entire Sonos milestone can be built with frameworks already shipping in macOS 26 and already imported by Kaset. No new Swift Package Manager dependencies are required or approved. Core Audio (`CATapDescription` + `AudioHardwareCreateProcessTap` + `AVAudioEngine`) handles capture; `AVAudioConverter` handles encoding; `Network.framework` (`NWConnectionGroup` for SSDP multicast, `NWListener` for the HTTP relay and GENA callback server) handles networking; `URLSession` + `XMLParser` handle SOAP and device description parsing.

The one entitlement not yet in `Kaset.entitlements` that requires a formal Apple request is `com.apple.developer.networking.multicast`. The sandbox also needs `com.apple.security.network.server` to allow the HTTP relay listener to accept inbound connections from Sonos. Both must be in place before the spike can fully run inside the `.app` bundle (the multicast entitlement being the calendar-blocked one).

**Core technologies:**

- **Core Audio process tap** (`ProcessTapHelper.swift` — existing): captures PCM from `com.apple.WebKit.WebContent` / `com.apple.WebKit.GPU` XPC processes — do not replace with ScreenCaptureKit (SCK audio is application-level only, not XPC-process-level)
- **`AVAudioConverter`** (AVFoundation): PCM Float32 48 kHz stereo → AAC-in-ADTS (preferred attempt) or raw LPCM WAV (fallback if AAC rejected by S1)
- **`NWConnectionGroup` + `NWMulticastGroup`** (Network): SSDP `M-SEARCH` to `239.255.255.250:1900` — the only Apple-blessed multicast path; requires the gated entitlement
- **`NWListener`** (Network): serves the audio stream (HTTP) and receives UPnP GENA `NOTIFY` callbacks on a second URL path — use one listener, two routes
- **`URLSession`**: SOAP `SetAVTransportURI` / `Play` / `Pause` / `SetVolume` POST requests to Sonos port 1400
- **`XMLParser`** (Foundation): device description parsing and `LastChange` event body parsing (double-encoded XML)

**Wire format (Sonos S1 requirements — HIGH confidence from community cross-reference):**

- URI scheme: `x-rincon-mp3radio://<mac-lan-ip>:<port>/stream.mp3` — plain `http://` routes through a track-oriented code path that expects `Content-Length`
- HTTP framing: HTTP/1.0, `Connection: close`, no `Content-Length`, **no `Transfer-Encoding: chunked`** — Sonos S1 does not handle chunked streaming correctly
- `Content-Type: audio/mpeg` for MP3; `audio/aac` or `audio/mp4` for AAC — URL suffix and Content-Type must match

### Expected Features

**Must have — table stakes (v1):**

- SSDP-based Sonos zone discovery with a manual-IP fallback (SSDP fails on VLANs and hostile Wi-Fi)
- AirPlay-style speaker picker popover in `PlayerBar` listing discovered zones by room name (`GetZoneAttributes`)
- Single source-of-truth output toggle: "This Mac" vs "Sonos zone X"
- Local HTTP audio relay serving captured WebView audio
- `SetAVTransportURI` + `Play` with minimal DIDL-Lite metadata (title + artist) so the Sonos app shows useful track info
- Play / pause / next / previous forwarded as UPnP `AVTransport` commands to the zone coordinator
- Per-zone volume and mute via `RenderingControl` (single speaker) or `GroupRenderingControl` (grouped)
- "Mac must stay awake" indicator on the picker — pre-empts the inevitable bug report
- Stop relay + Sonos transport when switching back to Mac speakers
- Last-selected zone restored on launch (selection only, never auto-play)
- Discovery empty-state with manual-IP entry

**Should have — differentiators (v1.x after validation):**

- GENA event subscriptions (`AVTransport` + `RenderingControl`) for bidirectional state sync — volume changed in the Sonos app should reflect in Kaset's slider
- Group-aware playback: resolve `ZoneGroupTopology` to route commands to the group coordinator
- Album-art metadata in DIDL-Lite (`upnp:albumArtURI` pointing to YouTube Music thumbnail URL)
- Smart re-bond after Mac wake / brief Wi-Fi loss
- AppleScript + NL command extensions ("send playback to Living Room")
- Diagnostics overlay (last SOAP error, relay URL, firmware version via `GetZoneInfo`)

**Defer to v2+:**

- EQ-on-Sonos handling (whether `EqualizerService` DSP applies to the Sonos stream or is bypassed)
- Gapless cross-track playback (requires server-side continuous stream; significant complexity)
- Non-Sonos UPnP renderer support
- Sonos S2 modern Local Control API

### Anti-Features (copy verbatim to PROJECT.md Out of Scope)

The requirements stage should add these to "Out of Scope" without further discussion:

- **"Sonos keeps playing after Mac sleeps or Kaset quits"** — architecturally impossible with local relay; only SMAPI partnership (excluded by `PROJECT.md`) could deliver this
- **Auto-resume Sonos playback on app launch** — silently interrupts other Sonos usage; restore picker selection only, never auto-play
- **Creating Sonos stereo pairs or bonded zones from Kaset** — UPnP actions exist but getting `ChannelMapSet` wrong desynchronizes the user's pair; direct to Sonos S1 app
- **Creating Sonos zone groups from Kaset** — read existing groups from `ZoneGroupTopology`, never create them; failure modes include orphaned coordinators and audio splitting
- **Hi-res / lossless streaming to Sonos** — S1 caps FLAC at 16-bit; YouTube Music source is already lossy; encoding lossy to lossless is busywork
- **In-Sonos-app playback control (queue, search, browse)** — requires SMAPI partnership; excluded
- **Multi-source mixing / ducking** — Mac is an HTTP server from Sonos's point of view; ducking causes audible stream glitches
- **Seek via `AVTransport::Seek` against the live relay URL** — Sonos returns error 701 on non-seekable content; seek must be handled in the WebView, not forwarded to Sonos
- **Discovering or controlling non-Sonos UPnP renderers** — lock to Sonos manufacturer string for v1
- **"Spotify Connect for YouTube Music" (Kaset appearing inside the Sonos app)** — requires SMAPI + YouTube Music licensing; not achievable

### Architecture Approach

The integration is a classic push-in / pull-out bridge: Core Audio tap pushes PCM into a bounded ring buffer; an HTTP relay server on `NWListener` drains the ring buffer as the HTTP response body; a UPnP/SOAP client tells the Sonos to fetch that URL. The highest-risk refactor is `WebKitAudioTapCoordinator` — currently `EqualizerService` owns `ProcessTapHelper` exclusively, and adding a second independent tap on the same WebKit PIDs produces undefined HAL behaviour. This refactor must land before the Sonos audio pipeline starts. Once it lands, both the EQ and the Sonos encoder are registered consumers of the same single tap.

All new code lives under `Sources/Kaset/Services/Sonos/` with subdirectories mirroring the conceptual subsystems (Discovery / Control / Eventing / Audio / Relay / Routing). `PlayerService` does not import any Sonos type directly — it delegates to `AudioOutputRouter` which owns the active `SonosOutputSession`. This keeps `PlayerService` (already 445 lines + 7 extensions) from absorbing a multi-thousand-line subsystem.

**Major components (new):**

1. `WebKitAudioTapCoordinator` — single tap, multi-consumer fan-out; refactors `ProcessTapHelper` ownership out of `EqualizerService`
2. `SonosDiscoveryService` — SSDP M-SEARCH + passive NOTIFY listener; builds and maintains a live device roster
3. `SonosControlClient` — per-device SOAP client (`SetAVTransportURI`, `Play`, `Pause`, `Stop`, `SetVolume`, `GetTransportInfo`)
4. `AudioCapturePipeline` + `AudioEncoder` — tap consumer → encoder → bounded `AsyncStream<Data>` ring buffer
5. `HTTPRelayServer` — `NWListener`-based; serves the live audio body on `/stream/<uuid>.mp3`; shares the listener with the GENA callback handler
6. `SonosEventSubscriber` — SUBSCRIBE/UNSUBSCRIBE/renewal + `LastChangeParser`
7. `AudioOutputRouter` — `@MainActor @Observable` strategy dispatcher; `enum AudioOutput { case system; case sonos(SonosDevice) }`
8. `SonosOutputSession` — per-session coordinator wiring pipeline → encoder → relay → control → events
9. `OutputDevicePicker` (View) + `OutputDevicePickerViewModel` — AirPlay-style popover in `PlayerBar`

### Critical Pitfalls

1. **ScreenCaptureKit silently produces silence on DRM-protected WebView audio (BLOCKER).** SCK audio is filtered at the application level, not the XPC-subprocess level — it captures Kaset-the-app, not the `WebContent` XPC where YouTube's audio is decoded. The existing `ProcessTapHelper` is already the correct approach. Do not use SCK for this purpose.

2. **Second Core Audio tap on the same WebKit PIDs causes undefined HAL behaviour (HIGH).** Two taps with `mutedWhenTapped` semantics on the same process PIDs are not guaranteed to compose. The `WebKitAudioTapCoordinator` refactor is mandatory before any Sonos audio work begins. This is the highest-risk code change in the milestone and must be validated in isolation — with EQ confirmed still working — before the Sonos encoder is wired up.

3. **Multicast entitlement is a calendar-time blocker (HIGH).** `com.apple.developer.networking.multicast` requires a formal Apple request with a one-to-two-week approval window. It must be filed at spike start. If not yet approved when the spike runs, prototype SSDP using a non-sandboxed `api-explorer` CLI; ship the sandboxed app with a manual-IP fallback behind a feature flag until the entitlement lands.

4. **Chunked transfer encoding breaks Sonos MP3 streaming (HIGH).** Sonos S1 follows the Shoutcast/Icecast radio model: it expects a continuous byte stream with no `Transfer-Encoding: chunked`. Use HTTP/1.0 + `Connection: close` + no `Content-Length` for live streams. AirConnect, swyh-rs, and the Sonos community confirm this is the only reliable path.

5. **Encoder format fork is unresolved (HIGH).** macOS ships an MP3 decoder but not an MP3 encoder. `AVAudioConverter` can produce AAC-in-ADTS (native, no deps, requires manual 7-byte ADTS header prepend), but whether Sonos S1 accepts AAC over `x-rincon-mp3radio://` is unconfirmed. Raw LPCM WAV is the widest-compatibility fallback (~1.4 Mbps) but is fragile over Wi-Fi. Vendoring LAME (LGPL) requires explicit human approval per `CLAUDE.md`. The spike must answer this question before the audio pipeline phase is scoped.

6. **End-to-end latency may exceed the 2-second target (HIGH).** Sonos's documented ~2-second input pre-buffer is not user-configurable. AirConnect users report 8–10 seconds in practice. Kaset's <2s target is aspirational. The spike must stopwatch pause-to-silence and report an actual number. Mitigation: use `Stop` (discards Sonos buffer quickly) rather than `Pause` for the user's pause action; accept and document whatever latency the spike measures.

---

## Implications for Roadmap

### Spike Go/No-Go Questions

The spike must answer all four binary questions before the build phase is scoped. A spike that reports "it worked" without naming which bets were confirmed is not a valid spike output.

| # | Question | Day-1 falsification test | Go signal | No-go signal |
|---|----------|--------------------------|-----------|--------------|
| 1 | Can the existing Core Audio process tap capture DRM-protected WebView audio while `EqualizerService` is also active? | Run peak-amplitude measurement on a `.caf` capture of a loud DRM track with EQ on. Target: > -60 dBFS. | Both EQ and Sonos frame counters increment simultaneously with no audio artifacts | Either path goes silent, sample-rate artifacts, or OS error codes |
| 2 | Will Sonos S1 fetch and play the HTTP audio stream (static MP3 first, then live-encoded)? | Serve a hardcoded MP3 file from `NWListener`; issue hand-built SOAP `SetAVTransportURI` + `Play`; audio comes out of the speaker | Sonos plays static file; then plays live-encoded stream for >5 minutes uninterrupted | UPnP error 714, transport cycles STOPPED→TRANSITIONING→STOPPED, or connection closed after first buffer |
| 3 | Can SSDP discovery work in a sandboxed app with `NWConnectionGroup`? | Confirm multicast entitlement granted; run `tcpdump` to verify M-SEARCH packets leave the Mac; replies arrive and parse to device IP+name | Device found automatically on first M-SEARCH in `.app` bundle | No packets leave, no replies, or discovery works only in non-sandboxed CLI |
| 4 | Is pause-to-silence latency at or below 2.5 seconds? | Stopwatch from "click pause" to silence at the speaker; measure 5 times and report median | Median ≤ 2.5s with `Stop`-as-pause strategy | Median > 3s and no tuning strategy closes the gap |

**Calendar blocker:** Request `com.apple.developer.networking.multicast` on day 1 of the spike. Do not wait until the spike "needs" it.

### Architectural Forks the Spike Must Commit To

1. **Encoder format.** Try AAC-in-ADTS first (`AVAudioConverter` + manual ADTS header). If Sonos S1 rejects it, surface the three options to the human before proceeding: (a) explicit approval to vendor LAME (LGPL), (b) raw WAV (~1.4 Mbps), (c) scope-reduction to Sonos S2 hardware only. Do not silently vendor a third-party encoder.

2. **Per-track vs continuous-stream relay.** Per-track: one HTTP response per song (`SetAVTransportURI` on each track change); enables seek path later; adds a clean gap on skip. Continuous-stream: one long-lived HTTP body; gapless across tracks; forecloses scrubbing entirely. Research recommendation: ship per-track for v1 (simpler failure recovery, seek path preserved).

3. **`WebKitAudioTapCoordinator` refactor vs EQ mutex.** Research recommendation: refactor (single tap, multiple consumers) because the mutex approach ("Sonos disables EQ") removes a feature users are actively using. The refactor also delivers standalone value by making the EQ tap's ownership explicit and testable.

### Suggested Phase Outline

#### Phase 0: Spike (time-boxed 2–3 days)
**Rationale:** Four unvalidated technical bets; cheaper to fail here than mid-build.
**Delivers:** Binary go/no-go on all four questions; encoder format decision; latency measurement; multicast entitlement status; spike report with ADR recommendations.
**Implements via:** `Sources/APIExplorer/main.swift` extension (`swift run api-explorer sonos discover`, `sonos play`). No production code committed.
**Must request on day 1:** `com.apple.developer.networking.multicast` entitlement.
**Pitfalls to invalidate:** 1 (DRM capture), 2 (EQ coexistence), 3 (MIME type / HTTP framing), 4 (chunked encoding), 6 (SSDP multicast), 9 (latency), 10 (sandbox server entitlement).
**Research flag:** The spike IS the validation. No `/gsd-research-phase` needed for this phase.

#### Phase 1: Foundation Refactor — `WebKitAudioTapCoordinator`
**Rationale:** Must land before any Sonos audio work. Refactoring a working subsystem in isolation is far safer than doing it alongside new Sonos code. Ships standalone EQ quality improvement regardless of Sonos milestone outcome.
**Delivers:** `WebKitAudioTapCoordinator` with fan-out consumer API; `EqualizerAudioEngine` migrated to be a consumer; frame-counter unit test confirming two simultaneous consumers work without artifacts; ADR in `docs/adr/`.
**Pitfalls to avoid:** Double-tap conflict; Conflict 3 (system output keeps playing while Sonos plays — `EqualizerService` entry point for "go quiet" mode added here).
**Research flag:** Well-documented fan-out pub-sub pattern. No additional research pass needed.

#### Phase 2: Discovery and Control Plane
**Rationale:** Independently testable (no audio involved). Validates the UPnP/SOAP stack and SSDP discovery against real hardware before audio complexity enters.
**Delivers:** `SonosDiscoveryService` (SSDP + device roster), `SonosControlClient` (SOAP), `OutputDevicePicker` UI shell (shows discovered zones, no audio yet), `AudioOutputRouter` skeleton.
**Pitfalls to avoid:** SSDP entitlement; always issue transport commands to the group coordinator resolved from `ZoneGroupTopology`, not to member players.
**Research flag:** SOAP/UPnP protocol surface is fully specified. No additional research needed.

#### Phase 3: Audio Capture and HTTP Relay
**Rationale:** First phase where audio leaves the Mac. Start with a static file before wiring live capture to isolate network-shaped failure modes from audio-quality failure modes.
**Delivers:** `AudioCapturePipeline`, `AudioEncoder` (AAC-in-ADTS or WAV per spike decision), `AudioRingBuffer`, `HTTPRelayServer`, `StreamURLProvider`. Static file serves; live-encoded stream serves; Sonos plays live stream.
**Pitfalls to avoid:** MIME type mismatch (error 714); HTTP/1.0 + no chunked encoding; sandbox server entitlement; firewall prompt UX (sign + notarize).
**Research flag:** ADTS framing details are niche if AAC is the chosen codec. Half-day focused read of Apple Forums thread 67106 and `kAudioFormatMPEG4AAC` ADTS wrapping before implementation.

#### Phase 4: End-to-End Integration
**Rationale:** First time all subsystems run together. Everything before here was buildable and testable in isolation; this phase wires them into the real user flow.
**Delivers:** `SonosOutputSession`, `PlayerService+Output.swift` extension, complete `OutputDevicePicker` with working output toggle, `AudioOutputRouter` fully wired. Real user flow: pick Sonos → music comes out of the speaker → pause/play/skip works.
**Pitfalls to avoid:** Seek against live URL (handle seek in WebView, not via Sonos `Seek` action); use `Stop` for pause (discards Sonos buffer quickly); `PlayerService.volume` → SOAP volume mapping.
**Research flag:** Standard integration work. No research pass needed.

#### Phase 5: UPnP Eventing and State Sync
**Rationale:** Functionally optional for v1 but required for the integration to feel like a real controller rather than a fire-and-forget bridge.
**Delivers:** `SonosEventSubscriber`, `EventListener` (second route on shared `NWListener`), `LastChangeParser`. Volume changed on Sonos app reflects in Kaset within 500ms. Pause from Sonos app reflects in Kaset.
**Pitfalls to avoid:** GENA NOTIFY not delivered (bind callback URL to LAN IP not loopback; verify `network.server` entitlement; auto-renew subscriptions at 75% of timeout). Subscriptions expire at 1800s; renewal must be built in from day one.
**Research flag:** GENA `LastChange` double-encoded XML is genuinely tricky. Half-day reading the UPnP Device Architecture spec section on eventing and the SoCo events module as a reference implementation for parsing patterns.

#### Phase 6: Polish and Diagnostics
**Rationale:** Hardening pass before considering the milestone complete.
**Delivers:** Robust error UX (Sonos offline mid-playback, port collision, network change), last-used-zone persistence, Mac-sleep/wake reconnect logic, diagnostics overlay (last SOAP error, firmware version, relay URL), AppleScript `set output to "Living Room"`, NL command extension, `IOPMAssertionCreateWithName` keep-awake helper, DIDL-Lite adversarial title unit tests.
**Pitfalls to avoid:** DIDL-Lite XML double-escaping (use `XMLDocument`; add unit test with `Tom & Jerry's "Best" — café` title); firewall prompt UX; firmware drift (diagnostics view enables remote debugging).
**Research flag:** Standard polish. No research pass needed.

### Phase Ordering Rationale

- **Spike first** because all four technical bets are unvalidated; any one could kill the milestone.
- **Foundation refactor before audio** because the tap conflict is the highest-risk code change and must be validated in isolation with the EQ as the only consumer.
- **Discovery before audio** because it is independently testable, validates the entitlement story, and confirms the device is reachable before audio complexity enters.
- **End-to-end glue after all parts proven** because the integration phase's only job is wiring; it should not introduce new technical unknowns.
- **Eventing after end-to-end** because it is a quality improvement, not a blocker; deferring it means a working product exists before this phase lands.

### Research Flags

Needs focused technical investigation during planning or early build:

- **Phase 0 (Spike):** ADTS header construction for AAC-in-ADTS if AAC is chosen — reference Apple Forums thread 67106 and `kAudioFormatMPEG4AAC` ADTS wrapping documentation.
- **Phase 0 (Spike):** `NWConnectionGroup` multicast unicast-response edge case (Apple Forums thread 657849) — if SSDP replies do not arrive, prototype BSD socket fallback in the CLI before committing to `NWConnectionGroup` for Phase 2.
- **Phase 5 (Eventing):** GENA `LastChange` double-encoded XML — the SoCo Python events module is the most readable reference implementation for parsing patterns.

Standard patterns (no research pass needed):

- **Phase 1 (Tap refactor):** Fan-out pub-sub on a Core Audio render thread is well-understood; `EqualizerAudioEngine` is the in-tree reference.
- **Phase 2 (Discovery + Control):** SOAP/UPnP surface is fully specified in svrooij's Sonos API docs and the UPnP AVTransport spec.
- **Phase 4 (End-to-end):** Standard Swift service wiring using existing `@MainActor @Observable` patterns already in the codebase.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Every framework is Apple-native and already imported. Process tap reuse proven in-tree. Only encoder format acceptance by S1 is unconfirmed — spike required. |
| Features | HIGH | UPnP/SOAP protocol surface cross-referenced across svrooij docs, SoCo, and Home Assistant implementations. Anti-features list is based on documented failure modes, not speculation. |
| Architecture | MEDIUM-HIGH | Capture half proven by existing EQ code. UPnP half is well-documented protocol but unproven in this specific Swift 6 / sandboxed-macOS-26 context. `WebKitAudioTapCoordinator` fan-out is architecturally sound but has no in-tree prior art yet. |
| Pitfalls | MEDIUM-HIGH | HIGH confidence on Sonos protocol pitfalls (HTTP framing, chunked encoding, MIME type, latency floor) — multiple independent bridge projects confirm the same failure modes. MEDIUM on DRM capture path specifically because Apple has never publicly documented the exact policy boundary for EME audio in WKWebView process taps. |

**Overall confidence:** MEDIUM-HIGH

### Highest-Confidence Claims (treat as load-bearing)

- The existing `ProcessTapHelper` approach is correct and must not be replaced with ScreenCaptureKit.
- Sonos S1 requires `x-rincon-mp3radio://` URI scheme and HTTP/1.0 with no chunked encoding for live streams — confirmed by swyh-rs, AirConnect, and the Sonos community forum thread on chunked encoding.
- A second independent Core Audio tap on the same WebKit PIDs is unsafe; `WebKitAudioTapCoordinator` refactor is mandatory.
- `com.apple.developer.networking.multicast` has a 1–2 week Apple approval window and must be requested at spike start.
- Sonos S1 firmware's ~2-second input pre-buffer is not configurable; the <2s latency target is aspirational and the spike must measure reality.

### Lowest-Confidence Claims (treat as hypotheses requiring spike validation)

- **AAC-in-ADTS is accepted by Sonos S1 over `x-rincon-mp3radio://`** — plausible because AAC is in Sonos's supported format list, but no prior-art bridge project has been found that uses AAC instead of MP3. Must be the first thing tested in the Pitfall 3 falsification test.
- **`NWConnectionGroup` SSDP works reliably inside a sandboxed macOS 26 app** — there are known unicast-response issues (Apple Forums thread 657849) and multicast entitlement edge cases. BSD socket fallback must be prototyped in parallel.
- **End-to-end latency can be kept below 2.5 seconds** — AirConnect's 8–10s is the honest prior-art baseline; the 2s target assumes a tighter encoder buffer and `Stop`-as-pause strategy that has not been measured in Kaset's specific pipeline.

### Gaps to Address

- **Encoder format decision:** Must be resolved in the spike. If AAC is accepted by S1, proceed with `AVAudioConverter`. If rejected, surface the LAME / WAV / scope-reduction choice to the user before scoping the audio pipeline phase.
- **`NWConnectionGroup` vs BSD sockets for SSDP:** Prototype both in the spike CLI; commit to one before Phase 2 begins.
- **EQ-on-Sonos handling:** Deferred to Phase 6. Two acceptable answers: (a) EQ is system-output-only, disable when Sonos active; (b) apply EQ DSP to the Sonos encoder pipeline. Decision at Phase 6 planning.
- **Latency floor:** If spike measurement exceeds 3 seconds even with `Stop`-as-pause, acknowledge in Phase 4 user-facing copy rather than continuing to chase a hard target.

---

## Sources

### Primary (HIGH confidence — Apple official)

- [Capturing system audio with Core Audio taps (Apple)](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps) — tap creation API contract
- [`com.apple.developer.networking.multicast` entitlement (Apple)](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast) — entitlement request flow
- [`NWConnectionGroup` / `NWMulticastGroup` (Apple)](https://developer.apple.com/documentation/network/nwmulticastgroup) — only supported multicast API on macOS
- [`AVAudioConverter` (Apple)](https://developer.apple.com/documentation/avfaudio/avaudioconverter) — PCM → AAC conversion
- [Is it possible to get only audio from ScreenCaptureKit? (Apple Forums, thread 718279)](https://developer.apple.com/forums/thread/718279) — Apple-confirmed: SCK audio is app-level, not XPC-subprocess-level
- [`com.apple.security.network.server` entitlement (Apple)](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.server)

### Primary (HIGH confidence — in-tree)

- `Sources/Kaset/Services/Audio/ProcessTapHelper.swift` — existing process tap implementation proven in production
- `Sources/Kaset/Services/Audio/EqualizerAudioEngine.swift` — reference for HAL I/O proc patterns and tap ownership
- `.planning/codebase/ARCHITECTURE.md` — service-based MVC patterns and `@MainActor @Observable` conventions

### Secondary (MEDIUM confidence — cross-referenced community)

- [svrooij Sonos API docs](https://sonos.svrooij.io/) — best-organised Sonos UPnP reference; third-party but widely cross-referenced
- [AirConnect (philippe44)](https://github.com/philippe44/AirConnect) — closest prior-art architecture; documents HTTP/1.0 pattern and 8–10s latency reality
- [swyh-rs (dheijl)](https://github.com/dheijl/swyh-rs) — Rust bridge; documents silence-injection trick, FLAC fragility, WAV vs MP3 tradeoffs
- [Sonos community: chunked encoding and MP3](https://en.community.sonos.com/advanced-setups-229000/chunked-encoding-transfer-and-mp3-a-technical-question-6763502) — community confirmation that chunked encoding breaks S1 streaming
- [SoCo Python library](https://github.com/SoCo/SoCo) — DIDL-Lite escaping helpers and GENA parsing patterns
- [insidegui/AudioCap](https://github.com/insidegui/AudioCap) — macOS 14.4+ Core Audio tap reference implementation in Swift
- [Apple Forums: NWConnectionGroup unicast-response issue (thread 657849)](https://developer.apple.com/forums/thread/657849) — known multicast/unicast mismatch in Network framework

### Tertiary (MEDIUM-LOW — validate in spike)

- [Sonos community: custom radio URL broken on S1 app](https://en.community.sonos.com/controllers-and-music-services-229131/custom-radio-url-completely-broken-sonos-s1-app-legacy-system-6927934) — at least one report of `x-rincon-mp3radio://` regression on recent S1 firmware; validate on user's actual hardware
- [AirConnect issue #458 — post-firmware-update breakage](https://github.com/philippe44/AirConnect/issues/458) — illustrates firmware-drift risk
- [Apple Forums: ADTS header construction (thread 67106)](https://developer.apple.com/forums/thread/67106) — manual ADTS framing reference; needed only if AAC is confirmed as the encoder

---

*Research completed: 2026-04-27*
*Ready for roadmap: yes — pending spike go/no-go*
