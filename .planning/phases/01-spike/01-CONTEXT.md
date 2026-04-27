# Phase 1: Spike - Context

**Gathered:** 2026-04-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Validate four binary technical bets against the user's actual Sonos S1 hardware via throwaway code in `Sources/APIExplorer/main.swift`, file the multicast entitlement with Apple on day 1 (1–2 week SLA blocker), and produce a structured go/no-go report at `.planning/phases/01-spike/REPORT.md` that either greenlights Phase 2+ or re-scopes the milestone. No production code under `Sources/Kaset/Services/Sonos/` ships in this phase.

The four bets:
1. **SPIKE-02** — A second consumer of the existing WebKit Core Audio process tap can coexist with `EqualizerService` without HAL conflict or audible artifact
2. **SPIKE-03** — Sonos S1 accepts our HTTP audio stream end-to-end (resolves the encoder-format fork)
3. **SPIKE-04** — Swift-native SSDP discovery (`NWConnectionGroup`) finds the user's S1 hardware
4. **SPIKE-05** — End-to-end pause-to-silence latency is measurable and reportable on the user's actual network

</domain>

<decisions>
## Implementation Decisions

### Spike Harness Shape

- **D-01:** Spike code lives in `Sources/APIExplorer/main.swift` (per ROADMAP) using **per-bet subcommands** under the existing `api-explorer` CLI: `sonos discover`, `sonos play <ip>`, `sonos tap-coexist`, `sonos measure-latency`. Pattern matches existing `auth` / `list` / `browse` subcommands. Each bet runs in isolation so failures can be iterated on individually.
- **D-02:** Add a thin `sonos spike-all` runner that invokes the four subcommands in order and aggregates output for the final report. Claude discretion call — keep it simple.
- **D-03:** All spike code is throwaway. No new Swift files under `Sources/Kaset/Services/Sonos/` are created in this phase. Spike learnings flow into Phase 2+ via `.planning/phases/01-spike/REPORT.md`.

### Multicast Entitlement Plan

- **D-04:** `com.apple.developer.networking.multicast` entitlement request is **filed day 1** of the spike phase. The plan-phase agent must produce a ready-to-paste request body explaining: (a) Kaset's SSDP use case for Sonos discovery, (b) target devices (Sonos S1 generation), (c) why no alternative exists (S1 hardware does not support modern Cloud Control API). The user files it manually from their Apple Developer account.
- **D-05:** While waiting 1–2 weeks for Apple approval, SPIKE-04 runs **non-sandboxed** via `swift run api-explorer sonos discover`. CLI binaries are not subject to the App Sandbox, so multicast send/receive works without the entitlement. This validates the SSDP code path and confirms the user's S1 is discoverable in week 1.
- **D-06:** Once Apple approves the entitlement, re-run the same SSDP code inside the actual `Kaset.app` bundle to prove the sandboxed production path works. Both runs are captured in the spike report.
- **D-07:** Add `com.apple.security.network.server` to `Kaset.entitlements` in Phase 4 (HTTP relay). It is NOT Apple-gated — no waiting required.

### Encoder Probe Order + Acceptance

- **D-08:** Probe order is **WAV first, then AAC-in-ADTS**. WAV is the widest-compatibility format (raw LPCM, ~1.4 Mbps over Wi-Fi). If WAV fails on Sonos S1, the entire architecture is wrong — fail fast. If WAV works, attempt AAC-in-ADTS for bandwidth optimization.
- **D-09:** Acceptance bar for "Sonos S1 accepted this stream" = **all three of**: (a) audio is audible at the speaker, (b) plays uninterrupted for ≥30 seconds with no audible dropouts, (c) Sonos `GetTransportInfo` reports `PLAYING` state for the duration.
- **D-10:** Likely v1 outcome (per research): WAV works, AAC rejected. **Spike report recommends shipping v1 with WAV.** 1.4 Mbps is acceptable on a typical home LAN; YouTube Music source is already lossy so lossless transport is overkill. **LAME (LGPL) vendoring is deferred** — not pursued in v1, even as a follow-up. Re-open only if real-world WAV bandwidth becomes a user-reported problem.
- **D-11:** Both WAV and AAC test results are recorded in the spike report regardless of outcome — even if WAV passes first, AAC is still tested for the data point.

### Second-Tap (SPIKE-02) Test Methodology

- **D-12:** Test design = **dual-consumer signals + frame counter**. The spike registers two consumers on the existing `ProcessTapHelper`-owned tap: (a) the production `EqualizerAudioEngine` consumer (current behavior), (b) a new test consumer that writes raw PCM to a `.wav` file. Spike validates: (i) frame counts match between the two consumers over a 60-second test, (ii) EQ-processed audible output is indistinguishable from baseline (A/B with EQ at known-loud settings on a known-loud track), (iii) PCM written to file is sample-perfect to the WebView source.
- **D-13:** **Acceptable fallback if SPIKE-02 fails (taps conflict at HAL level):** mutex — `EqualizerService` disables itself when a Sonos zone is the active output, re-enables when output returns to "This Mac". Milestone proceeds with FOUND-* requirements adjusted to support this mode (the coordinator still extracts but provides exclusive-consumer semantics rather than fan-out). UI must document the EQ-off-on-Sonos behavior on the picker.
- **D-14:** **Hard re-scope** only if BOTH true coexistence AND the mutex workaround fail (e.g., adding any second tap kills audio entirely, even with EQ disabled). Spike report must explicitly distinguish these failure modes.

### Test Content + Conditions

- **D-15:** Spike runs against the user's actual S1 hardware on the user's actual home Wi-Fi — not a simulator, not a mock Sonos endpoint. Reproducibility for downstream phases requires real-world conditions.
- **D-16:** Test track for tap-coexist + audible A/B: a known-loud, dynamic-range-rich YouTube Music track the user can pick at spike-runtime (passed as a CLI arg). Plan-phase suggests defaults but doesn't lock one in.
- **D-17:** Test stream for SPIKE-03 (encoder probe): a short pre-recorded WAV/AAC file served from the spike's HTTP listener — NOT live-encoded WebView audio. Live encoding is a Phase 4 concern; the spike isolates the encoder + Sonos-acceptance variable from the capture-pipeline variable.

### Spike Report Structure

- **D-18:** `.planning/phases/01-spike/REPORT.md` is structured per-bet with: (a) what was tested, (b) how it was measured, (c) raw observations / numbers, (d) **binary go / go-with-workaround / no-go verdict**, (e) recommended action for Phase 2+.
- **D-19:** Report ends with a **milestone-level decision**: "PROCEED" (all bets pass or pass-with-workaround), "PROCEED WITH SCOPE CHANGE" (some bets force FOUND-*, AUDIO-*, or DISC-* requirements to adjust — list the changes), or "RE-SCOPE MILESTONE" (≥1 bet has no workaround). The roadmap revision happens in a follow-up command, not inside the spike phase.

### Claude's Discretion

- The exact `api-explorer` arg-parsing convention (matches existing `main.swift` patterns). Plan-phase agent infers from the file.
- The 1,400-byte UDP packet shape for SSDP M-SEARCH (UPnP standard, not user-decided).
- The exact NWListener configuration for the test HTTP server (port choice, TLS off, bind address — standard `0.0.0.0:<dynamic>`).
- The exact SOAP envelope strings for `SetAVTransportURI` / `Play` / `GetTransportInfo` (UPnP/AVTransport standard, citable from svrooij Sonos API docs).
- Whether the latency-measurement subcommand uses a stopwatch input mode or auto-correlates a tone burst (auto-correlate is cleaner — Claude picks).
- Whether the WAV stream wraps a header or uses raw LPCM (S1 generally needs WAV header — Claude picks).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project context
- `.planning/PROJECT.md` — Project context, core value, Out of Scope (anti-features locked)
- `.planning/REQUIREMENTS.md` — All 30 v1 requirements, including SPIKE-01..06 with full descriptions
- `.planning/ROADMAP.md` — Phase 1 goal, 5 success criteria, dependency chain

### Research outputs (REQUIRED — these inform every spike decision)
- `.planning/research/SUMMARY.md` — Executive synthesis; load-bearing facts vs hypotheses
- `.planning/research/STACK.md` — Sonos S1 wire format (HTTP/1.0, no chunked, x-rincon-mp3radio://), encoder fork details, multicast entitlement specifics, alternatives considered
- `.planning/research/PITFALLS.md` — 12 pitfalls with severity + phase mapping; the spike's job is to falsify or validate the HIGH-severity ones
- `.planning/research/ARCHITECTURE.md` — 9-component design + dependency-driven build order (informs what the spike does NOT have to validate)
- `.planning/research/FEATURES.md` — Anti-features already absorbed into REQUIREMENTS Out of Scope; competitor matrix (AirConnect 8–10s latency baseline)

### Codebase maps
- `.planning/codebase/ARCHITECTURE.md` — Service-based MVC, @Observable @MainActor singletons, existing audio path
- `.planning/codebase/STACK.md` — Swift 6 / SwiftUI / macOS 26+ / SPM; current entitlements
- `.planning/codebase/STRUCTURE.md` — Directory conventions for any new code (none in this phase, but referenced for spike harness placement)
- `.planning/codebase/CONVENTIONS.md` — DiagnosticsLogger usage, no print/DispatchQueue/force-unwrap rules

### Project rules (non-negotiable)
- `CLAUDE.md` — Senior Swift Engineer role, no third-party deps without approval, API > WebView, improve api-explorer not one-off scripts, build/lint commands

### Existing code the spike must respect
- `Sources/APIExplorer/main.swift` (1,458 lines) — Where spike subcommands extend
- `Sources/Kaset/Services/Audio/ProcessTapHelper.swift` (600 lines) — The existing tap; spike's tap-coexist test attaches a second consumer to this
- `Sources/Kaset/Services/Audio/EqualizerAudioEngine.swift` (529 lines) — Current sole consumer of the tap; A/B baseline for SPIKE-02
- `Sources/Kaset/Services/Audio/EqualizerService.swift` (431 lines) — Service wrapper; integration target for the mutex workaround if SPIKE-02 fails
- `Kaset.entitlements` — Current entitlement set; spike report documents what additions are needed for production (multicast + network.server)

### External (Sonos S1 protocol — for SOAP envelope construction)
- Sonos AVTransport service docs (svrooij) — `SetAVTransportURI`, `Play`, `Pause`, `Stop`, `GetTransportInfo` envelopes; cited in `.planning/research/STACK.md`
- Sonos community thread on `x-rincon-mp3radio://` URI scheme requirement for live streams on S1; cited in `.planning/research/STACK.md`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`Sources/APIExplorer/main.swift`** (1,458 lines): Existing CLI with `auth` / `list` / `browse` subcommand pattern. Spike extends this with `sonos discover` / `sonos play` / `sonos tap-coexist` / `sonos measure-latency` / `sonos spike-all`. Reuse arg parsing, output formatting, and `DiagnosticsLogger` patterns from existing subcommands.
- **`Sources/Kaset/Services/Audio/ProcessTapHelper.swift`**: Existing Core Audio process tap on `com.apple.WebKit.WebContent` / `com.apple.WebKit.GPU`. The spike's SPIKE-02 test attaches a second consumer to this — does NOT create a separate tap. Critical: the spike must not modify `ProcessTapHelper` itself; it injects a fan-out at the test layer.
- **`DiagnosticsLogger`** (`Sources/Kaset/Utilities/`): All spike output uses this, never `print()`. Add a `sonos` subsystem at spike scope (formalized into the production logger in Phase 3).
- **`AVAudioConverter`** (AVFoundation): Native PCM → AAC encoder for SPIKE-03 AAC test. No third-party deps needed.
- **`NWConnectionGroup` + `NWMulticastGroup`** (Network framework): SSDP M-SEARCH transport for SPIKE-04 (per research STACK.md).
- **`NWListener`** (Network framework): HTTP server for SPIKE-03 stream serving (per research STACK.md).
- **`URLSession` + `XMLParser`** (Foundation): SOAP POST + device-description parsing for SPIKE-04 zone-name extraction.

### Established Patterns

- **Strict Concurrency / Swift 6** — All spike code uses `async`/`await`; no `DispatchQueue`; no force unwraps. The spike runs in a CLI context (no `@MainActor` constraints), but uses Swift Concurrency throughout.
- **Protocol-driven services** — Production code follows protocols for testability (e.g., `YTMusicClientProtocol`). Spike code is throwaway and does NOT introduce protocols — keep it concrete and short.
- **Typed errors** — Production code uses typed `YTMusicError` enums. Spike code may use simpler error handling (loose throws + descriptive messages); typed `SonosError` is a Phase 3 concern.
- **`api-explorer` invocation** — `swift run api-explorer <subcommand> [args]`. Build target: `Sources/APIExplorer/main.swift`. Spike subcommands run via this entry point only.

### Integration Points

- **Spike code → `ProcessTapHelper`** (READ-ONLY): SPIKE-02 attaches a second consumer to the existing tap; does not modify the helper. The fan-out lives in spike code only.
- **Spike code → `EqualizerService`** (READ-ONLY): SPIKE-02 A/B test compares EQ output before/after the second consumer is attached; does not modify the service.
- **Spike report → Phase 2 planning**: `.planning/phases/01-spike/REPORT.md` is the input to `/gsd-plan-phase 2`. Per-bet outcomes determine whether FOUND-* requirements need adjustment (e.g., D-13 mutex fallback changes FOUND-03 semantics).

</code_context>

<specifics>
## Specific Ideas

- **Test gear is the user's own Sonos S1 system** (Play:1 / Play:3 / Play:5 Gen 1 / Connect / Connect:Amp generation, on the user's home Wi-Fi). Not a simulator. Not a mock. The spike report's latency numbers and "Sonos accepts WAV" verdicts are specific to this hardware — they are the v1 reference.
- **Comparison baseline** = AirConnect / AirSonos historical behavior (8–10s latency reported per research). Anything substantially better is a win; anything worse needs investigation before milestone proceeds.
- **Phase 1 produces no Sonos-related production code.** Even the "obvious" abstractions (e.g., `SonosDevice` model, `SonosError` enum) belong to Phase 3, not the spike.

</specifics>

<deferred>
## Deferred Ideas

- **LAME encoder vendoring (LGPL)**: Deferred from v1 entirely per D-10. Re-open only if WAV bandwidth becomes a real-world user complaint after v1 ships.
- **Sandboxed-app SSDP testing**: Cannot complete until Apple approves the multicast entitlement (D-05/D-06). Spike report flags this as "pending Apple approval"; final validation happens during Phase 3 (DISC-01) once the entitlement lands.
- **Latency-measurement methodology details** (stopwatch UI vs auto-correlate tone burst): Claude discretion call (D-19); plan-phase agent picks based on what's cleanest in the existing `api-explorer` patterns.
- **GENA event subscriptions** (test feasibility, validate `LastChange` parsing): Explicitly v1.x; not in this spike's scope. EVENT-01..05 in REQUIREMENTS.md.

</deferred>

---

*Phase: 1-Spike*
*Context gathered: 2026-04-27*
