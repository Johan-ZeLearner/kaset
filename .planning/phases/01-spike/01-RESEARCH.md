# Phase 1: Spike — Research

**Researched:** 2026-04-27
**Domain:** Time-boxed validation harness for four binary technical bets against Sonos S1 hardware. Implemented as throwaway code under `Sources/APIExplorer/main.swift`. No production code lands.
**Confidence:** HIGH on Sonos SOAP envelopes, SSDP packet shape, the existing tap/aggregate device code path, and report structure. MEDIUM on the multicast entitlement request body (form questions known indirectly; exact wording requires Apple Developer login). MEDIUM on the SPIKE-05 latency methodology (auto-correlate is feasible but adds spike scope; manual stopwatch is the safe baseline). LOW only on whether the user's specific S1 firmware accepts AAC over `x-rincon-mp3radio://` — that is the explicit point of SPIKE-03.

## Summary

The spike's job is not to design — that's been done by the project-level researchers. The spike's job is to **falsify or confirm four hypotheses on the user's actual S1 hardware**, file the multicast entitlement on day 1, and emit a structured go/no-go report that locks Phase 2+ scope.

This document supplies the planning-grade specifics the planner needs that are NOT in the project-level research: (1) a ready-to-paste multicast entitlement request body, (2) verified SOAP envelope strings for every Sonos action the spike issues, (3) the exact SSDP M-SEARCH packet shape with `\r\n` line endings, (4) a recommended dual-consumer test design that does not modify `ProcessTapHelper`, (5) the minimal `NWListener` + WAV-serving configuration, (6) a latency-measurement methodology with both an auto-correlate path and a stopwatch fallback, and (7) the exact `REPORT.md` template per CONTEXT.md D-18/D-19.

**Primary recommendation:** Plan four sequential `api-explorer sonos <subcmd>` plans plus a day-1 entitlement-filing plan and a final report plan. Do NOT attempt SPIKE-02's dual-consumer test by creating a second `CATapDescription` — the research explicitly flags that as undefined HAL behavior. Use a code-level fan-out at `EqualizerAudioEngine.performRender` instead (see Section 4 below). Use WAV-with-header for SPIKE-03's first attempt. Use the manual-stopwatch methodology for SPIKE-05 unless the planner has bandwidth for the auto-correlate add-on.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Spike code lives in `Sources/APIExplorer/main.swift` using **per-bet subcommands** under the existing `api-explorer` CLI: `sonos discover`, `sonos play <ip>`, `sonos tap-coexist`, `sonos measure-latency`. Pattern matches existing `auth` / `list` / `browse` subcommands. Each bet runs in isolation so failures can be iterated on individually.
- **D-02:** Add a thin `sonos spike-all` runner that invokes the four subcommands in order and aggregates output for the final report. Claude discretion call — keep it simple.
- **D-03:** All spike code is throwaway. No new Swift files under `Sources/Kaset/Services/Sonos/` are created in this phase. Spike learnings flow into Phase 2+ via `.planning/phases/01-spike/REPORT.md`.
- **D-04:** `com.apple.developer.networking.multicast` entitlement request is **filed day 1** of the spike phase. The plan-phase agent must produce a ready-to-paste request body explaining: (a) Kaset's SSDP use case for Sonos discovery, (b) target devices (Sonos S1 generation), (c) why no alternative exists (S1 hardware does not support modern Cloud Control API). The user files it manually from their Apple Developer account.
- **D-05:** While waiting 1–2 weeks for Apple approval, SPIKE-04 runs **non-sandboxed** via `swift run api-explorer sonos discover`. CLI binaries are not subject to the App Sandbox, so multicast send/receive works without the entitlement. This validates the SSDP code path and confirms the user's S1 is discoverable in week 1.
- **D-06:** Once Apple approves the entitlement, re-run the same SSDP code inside the actual `Kaset.app` bundle to prove the sandboxed production path works. Both runs are captured in the spike report.
- **D-07:** Add `com.apple.security.network.server` to `Kaset.entitlements` in Phase 4 (HTTP relay). It is NOT Apple-gated — no waiting required.
- **D-08:** Probe order is **WAV first, then AAC-in-ADTS**. WAV is the widest-compatibility format (raw LPCM, ~1.4 Mbps over Wi-Fi). If WAV fails on Sonos S1, the entire architecture is wrong — fail fast. If WAV works, attempt AAC-in-ADTS for bandwidth optimization.
- **D-09:** Acceptance bar for "Sonos S1 accepted this stream" = **all three of**: (a) audio is audible at the speaker, (b) plays uninterrupted for ≥30 seconds with no audible dropouts, (c) Sonos `GetTransportInfo` reports `PLAYING` state for the duration.
- **D-10:** Likely v1 outcome (per research): WAV works, AAC rejected. **Spike report recommends shipping v1 with WAV.** 1.4 Mbps is acceptable on a typical home LAN; YouTube Music source is already lossy so lossless transport is overkill. **LAME (LGPL) vendoring is deferred** — not pursued in v1, even as a follow-up. Re-open only if real-world WAV bandwidth becomes a user-reported problem.
- **D-11:** Both WAV and AAC test results are recorded in the spike report regardless of outcome — even if WAV passes first, AAC is still tested for the data point.
- **D-12:** Test design = **dual-consumer signals + frame counter**. The spike registers two consumers on the existing `ProcessTapHelper`-owned tap: (a) the production `EqualizerAudioEngine` consumer (current behavior), (b) a new test consumer that writes raw PCM to a `.wav` file. Spike validates: (i) frame counts match between the two consumers over a 60-second test, (ii) EQ-processed audible output is indistinguishable from baseline (A/B with EQ at known-loud settings on a known-loud track), (iii) PCM written to file is sample-perfect to the WebView source.
- **D-13:** **Acceptable fallback if SPIKE-02 fails:** mutex — `EqualizerService` disables itself when a Sonos zone is the active output. Milestone proceeds with FOUND-* requirements adjusted to support this mode.
- **D-14:** **Hard re-scope** only if BOTH true coexistence AND the mutex workaround fail.
- **D-15:** Spike runs against the user's actual S1 hardware on the user's actual home Wi-Fi.
- **D-16:** Test track for tap-coexist + audible A/B: passed as a CLI arg.
- **D-17:** Test stream for SPIKE-03 (encoder probe): a short pre-recorded WAV/AAC file served from the spike's HTTP listener — NOT live-encoded WebView audio. Live encoding is a Phase 4 concern.
- **D-18:** `.planning/phases/01-spike/REPORT.md` is structured per-bet with: (a) what was tested, (b) how it was measured, (c) raw observations / numbers, (d) **binary go / go-with-workaround / no-go verdict**, (e) recommended action for Phase 2+.
- **D-19:** Report ends with a **milestone-level decision**: "PROCEED" / "PROCEED WITH SCOPE CHANGE" / "RE-SCOPE MILESTONE".

### Claude's Discretion

- The exact `api-explorer` arg-parsing convention (matches existing `main.swift` patterns).
- The 1,400-byte UDP packet shape for SSDP M-SEARCH (UPnP standard).
- The exact `NWListener` configuration for the test HTTP server (port choice, TLS off, bind address — standard `0.0.0.0:<dynamic>`).
- The exact SOAP envelope strings for `SetAVTransportURI` / `Play` / `GetTransportInfo` (UPnP/AVTransport standard, citable from svrooij Sonos API docs).
- Whether the latency-measurement subcommand uses a stopwatch input mode or auto-correlates a tone burst.
- Whether the WAV stream wraps a header or uses raw LPCM (S1 generally needs WAV header).

### Deferred Ideas (OUT OF SCOPE)

- **LAME encoder vendoring (LGPL):** Deferred from v1 entirely per D-10.
- **Sandboxed-app SSDP testing:** Cannot complete until Apple approves the multicast entitlement (D-05/D-06). Spike report flags this as "pending Apple approval"; final validation happens during Phase 3 (DISC-01).
- **Latency-measurement methodology details** (stopwatch UI vs auto-correlate tone burst): Claude discretion call (D-19).
- **GENA event subscriptions:** Explicitly v1.x; not in this spike's scope.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SPIKE-01 | File `com.apple.developer.networking.multicast` entitlement request with Apple on day 1 | Section 1 — ready-to-paste request body draft; entitlement request URL; team-vs-app scoping notes |
| SPIKE-02 | Validate that a second consumer of the existing WebKit Core Audio process tap coexists with `EqualizerService` without HAL conflict or audible artifact | Section 4 — recommended fan-out approach (modify `EqualizerAudioEngine.performRender` in spike branch only); A/B methodology |
| SPIKE-03 | Validate that Sonos S1 accepts our HTTP audio stream end-to-end (encoder fork: WAV first, AAC second) | Sections 2 + 5 — SOAP envelopes for `SetAVTransportURI` + `Play` + `GetTransportInfo`; minimal `NWListener` config; WAV header construction; URI scheme `x-rincon-mp3radio://`; HTTP/1.0 framing |
| SPIKE-04 | Validate that Swift-native SSDP discovery (`NWConnectionGroup`) finds the user's S1 hardware | Section 3 — exact M-SEARCH packet bytes; `NWConnectionGroup` setup shape; documented unicast-response edge case + BSD socket fallback |
| SPIKE-05 | Measure end-to-end pause-to-silence latency (5 trials, median reported) | Section 6 — manual stopwatch methodology (recommended); optional auto-correlate add-on with feasibility honest-assessment |
| SPIKE-06 | Spike report — per-bet go/no-go + recommended encoder format + measured latency | Section 7 — exact `REPORT.md` template per D-18/D-19 with per-bet sections and milestone-decision template |

</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Multicast entitlement request | Apple Developer Portal (out-of-band) | — | Apple-controlled approval workflow; user-filed manually from web form; not a code task |
| `api-explorer sonos discover` (SSDP M-SEARCH) | CLI process (non-sandboxed) | LAN UDP multicast | CLI is not bound by App Sandbox per CONTEXT.md D-05; multicast just works without entitlement |
| `api-explorer sonos play` (SOAP + HTTP serve) | CLI process (non-sandboxed) | LAN HTTP server + LAN UDP control | CLI process binds an `NWListener`, sends SOAP over `URLSession`; both are non-sandboxed |
| `api-explorer sonos tap-coexist` | CLI process (non-sandboxed) | Core Audio HAL | Tap creation requires `NSAudioCaptureUsageDescription` in Info.plist; CLI inherits the user's TCC grants for the host terminal but the tap itself is HAL-level so this needs verification (see Section 4 Open Question OQ-1) |
| `api-explorer sonos measure-latency` | CLI process (non-sandboxed) + manual user input (stopwatch) | LAN HTTP server | Spike harness toggles SOAP `Pause` and prompts user for keypress on silence |
| Spike report writing | File system (Markdown) | git commit | Standard write/commit; no runtime tier |

**Nothing in this phase ships in the `Kaset.app` bundle.** Production tiers (`Sources/Kaset/Services/Sonos/...`) are explicitly deferred to Phase 2+ per D-03.

## Standard Stack

### Core (already in scope per project research; no new SPM deps)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation | macOS 26 | `URLSession`, `XMLParser`, `Data`, file I/O for spike state and the WAV file | [VERIFIED: codebase grep — already imported in `main.swift`] |
| Network | macOS 26 | `NWListener` (HTTP serve for SPIKE-03), `NWConnectionGroup`+`NWMulticastGroup` (SSDP for SPIKE-04), `NWConnection` (per-client TCP from `NWListener`) | [VERIFIED: research/STACK.md] Apple-blessed, no new dep |
| CoreAudio | 14.2+ (already required by `ProcessTapHelper`) | Existing tap; SPIKE-02 reads frames from existing path | [VERIFIED: in-tree code at `Sources/Kaset/Services/Audio/ProcessTapHelper.swift`] |
| AudioToolbox | 10.11+ | `AudioFileWriteBytes` for the SPIKE-02 PCM-to-WAV writer (or hand-roll the 44-byte WAV header) | [VERIFIED: macOS-native; available in CLI without entitlement] |
| Darwin | macOS 26 | BSD socket fallback if `NWConnectionGroup` unicast-response bug bites SPIKE-04 | [VERIFIED: `Sources/Kaset/Services/Audio/ProcessTapHelper.swift` already imports it for `proc_pidinfo`] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `AVFoundation` (`AVAudioConverter`) | macOS 10.11+ | Encode raw LPCM to AAC-in-ADTS for SPIKE-03 second attempt | Only after WAV passes SPIKE-03 acceptance bar (D-08); skip entirely if WAV fails |
| `tcpdump` (CLI tool) | system | Out-of-band verification that M-SEARCH packets actually leave the Mac in SPIKE-04 | If `discover` returns nothing — discriminates between "code didn't send" vs. "Sonos didn't reply" |
| `curl -v` | system | Out-of-band verification that the spike's `NWListener` accepts connections from another LAN device | After SPIKE-03 first plays — confirms HTTP/1.0 + Connection: close framing is wire-correct |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `NWConnectionGroup` for SSDP | BSD `socket(AF_INET, SOCK_DGRAM, ...)` + `setsockopt(IP_ADD_MEMBERSHIP)` | If FB8461681 (NWConnectionGroup unicast-response bug) bites the spike, fall back. The research [VERIFIED: research/PITFALLS.md Pitfall 6 + Apple Forums thread 657849] documents this is unresolved as of recent macOS. Have the BSD fallback **ready in the same `sonos discover` subcommand** behind a `--bsd` flag so the spike can prove which path the user's macOS 26 needs. |
| Hand-rolled WAV header | `AVAudioFile`/`ExtAudioFile` write APIs | Hand-rolled is 44 bytes of `.write` — for a fixed Float32 stereo 48 kHz spike it's trivial and avoids a framework round-trip. Use AVFoundation only if encoding to AAC. |
| `AVAudioConverter` for AAC | LAME (LGPL vendored) | LAME is **explicitly deferred** per D-10. AVFoundation is the only path the spike attempts for compressed audio. |

**Installation:** None. Every framework above is already in macOS 26 / already imported by `Kaset` or `APIExplorer`. The spike adds zero `Package.swift` entries.

**Version verification:** Skipped — no third-party packages.

## Architecture Patterns

### Spike Harness Diagram

```
  ┌────────────────────────────────────────────────────────────────────┐
  │  swift run api-explorer sonos <subcommand>                         │
  │  (CLI, non-sandboxed, runs in user's terminal session)             │
  └──────────────────────────────┬─────────────────────────────────────┘
                                 │
       ┌───────────────┬─────────┼─────────┬──────────────┬───────────┐
       ▼               ▼         ▼         ▼              ▼           ▼
   discover         play    tap-coexist  measure-     spike-all     help
   (SPIKE-04)    (SPIKE-03)   (SPIKE-02)  latency     (D-02:        (existing
                                          (SPIKE-05)   sequential   pattern)
                                                       runner)

   ┌─────────────┐  ┌─────────┐  ┌────────────────┐  ┌──────────────┐
   │ NWConnGroup │  │NWListen │  │ ProcessTap +   │  │ NWListener + │
   │ → 239.255.. │  │ + URLSes│  │ EQAudioEngine  │  │ URLSession   │
   │   .250:1900 │  │ → SOAP  │  │ + raw PCM file │  │ → Pause SOAP │
   │ M-SEARCH    │  │ to S1   │  │ writer (added  │  │ + stopwatch  │
   │             │  │ :1400   │  │ to performRen- │  │ user prompt  │
   │ ┌─ Wireshark│  │         │  │ der as a       │  │              │
   │ │  out-of-  │  │ Stages: │  │ second arm)    │  │              │
   │ │  band     │  │ 1. WAV  │  │                │  │              │
   │ └  verify   │  │ 2. AAC  │  │                │  │              │
   └─────┬───────┘  └────┬────┘  └────────┬───────┘  └──────┬───────┘
         │               │                │                 │
         ▼               ▼                ▼                 ▼
   Sonos S1 sends    Sonos S1 fetches   Existing audio    User's hands
   HTTP-over-UDP     /test.wav, plays   continues; PCM    measure pause
   200 OK with       audibly for ≥30s,  written to file   delay; Claude
   LOCATION:         GetTransportInfo   sample-perfect    aggregates 5
   http://<ip>:1400  reports PLAYING    to source         trials, reports
                                                          median
```

### Recommended Project Structure

The spike adds exactly **one file's worth of new code** — and that file is the existing `Sources/APIExplorer/main.swift`. Per CONTEXT.md D-03, **no new files in `Sources/Kaset/Services/Sonos/`**.

```
Sources/APIExplorer/
└── main.swift                         # Existing 1,458 lines + spike additions

# New top-level functions added (mirroring existing `exploreBrowse`/`exploreAction` pattern):
#   - func runSonosDiscover(args: [String]) async
#   - func runSonosPlay(ip: String, format: SonosTestFormat, args: [String]) async
#   - func runSonosTapCoexist(track: String, durationSeconds: Int) async
#   - func runSonosMeasureLatency(ip: String, trials: Int) async
#   - func runSonosSpikeAll(args: [String]) async
#
# New helper functions (kept inline; throwaway):
#   - func sendSSDPMSearch(timeout: TimeInterval) async throws -> [DiscoveredSonosDevice]
#   - func sendSOAP(host: String, action: SonosAction, body: [String: String]) async throws -> SOAPResponse
#   - func serveStaticAudioFile(path: URL, port: UInt16) async throws -> URL  // returns x-rincon-mp3radio:// URL
#   - func writeWAVHeader(to: URL, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16, dataSize: UInt32) throws
#
# Test fixture files (committed to git for reproducibility):
.planning/phases/01-spike/fixtures/
├── test-stream.wav                    # Pre-recorded stereo WAV (~30s, ~5 MB)
└── test-stream.aac                    # Same content, AAC-in-ADTS (~30s, ~750 KB)
```

The `case "sonos":` is added to the existing `switch command` in `runMain()` at the bottom of `main.swift`, with a sub-switch on the subcommand string (D-01 pattern: `sonos discover` / `sonos play` / etc.).

### Pattern 1: Per-bet subcommand isolation

**What:** Each SPIKE-02..05 lives in its own subcommand. Each subcommand exits with status `0` (go), `1` (no-go), or `2` (go-with-workaround). The `spike-all` runner shells through them in order and aggregates exit codes plus stdout into the report.

**When to use:** Every spike phase. Per CONTEXT.md D-01, this is the locked harness shape.

**Example structure (mirrors existing `exploreBrowse`/`exploreAction` patterns in `main.swift:494` and `main.swift:576`):**

```swift
// Source: pattern lifted from existing main.swift exploreBrowse signature
// File: Sources/APIExplorer/main.swift (added near end, before runMain)

func runSonosDiscover(timeoutSeconds: Int = 5, useBSDFallback: Bool = false) async {
    print("🔍 SPIKE-04 — SSDP discovery on 239.255.255.250:1900")
    print("   Transport: \(useBSDFallback ? "BSD socket fallback" : "NWConnectionGroup")")
    print("   Timeout: \(timeoutSeconds)s")
    print()
    do {
        let devices = try await sendSSDPMSearch(
            timeout: TimeInterval(timeoutSeconds),
            useBSD: useBSDFallback
        )
        if devices.isEmpty {
            print("❌ NO-GO: zero devices responded")
            exit(1)
        }
        print("✅ GO: discovered \(devices.count) Sonos device(s):")
        for device in devices {
            print("   • \(device.roomName) — \(device.ip):1400 (UDN \(device.udn))")
        }
        exit(0)
    } catch {
        print("❌ NO-GO: \(error.localizedDescription)")
        exit(1)
    }
}
```

### Pattern 2: Throwaway-but-shaped-like-production

**What:** Throwaway code can still mirror production shape — `SonosAction` enum, `SOAPResponse` struct, `DiscoveredSonosDevice` struct. The spike defines them inline in `main.swift` with no protocols and no DI. They get re-extracted during Phase 3 if/when the spike passes.

**When to use:** When the planner is templating spike code that will be referenced (not copy-pasted) by Phase 3 production work. Helps Phase 3 read the spike report in code form without inheriting throwaway design choices.

### Anti-Patterns to Avoid

- **Creating a second `CATapDescription` for SPIKE-02.** [VERIFIED: research/PITFALLS.md Pitfall 2 + research/ARCHITECTURE.md Anti-Pattern 2] Two taps with `mutedWhenTapped` semantics on the same WebKit PIDs are undefined. The spike must add a fan-out **inside the existing tap path** (Section 4 below), not create a second tap. This is the single most important architectural rule for SPIKE-02.
- **Modifying `Sources/Kaset/Services/Audio/ProcessTapHelper.swift` itself.** Per CONTEXT.md ("Spike code → `ProcessTapHelper` (READ-ONLY)"). The fan-out goes into `EqualizerAudioEngine.performRender` in a spike-only branch, NOT into `ProcessTapHelper`.
- **Using `print()` for spike output.** [VERIFIED: CLAUDE.md] Use `DiagnosticsLogger.equalizer` for tap-coexist diagnostics emitted from the audio thread (already used by `ProcessTapHelper`). For top-level spike CLI output the existing `main.swift` precedent uses `print()` directly — this is a CLI exception that already exists in the codebase, not a violation. [VERIFIED: codebase grep — `main.swift:75`, `main.swift:84`, etc. all use `print` for user-facing CLI output.]
- **Building a `SonosError` enum or `SonosDevice` model in `Sources/Kaset/`.** [VERIFIED: CONTEXT.md "Specifics" section] These are explicitly Phase 3, not the spike.
- **`DispatchQueue.main.async` to bridge the audio thread.** [VERIFIED: CLAUDE.md] CLI context has no `@MainActor`, but Swift Concurrency policy still applies — use `Task { ... }` from the audio thread or write to a `Mutex<...>` (Swift 6) buffer that the CLI reads.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SOAP envelope construction | XML string interpolation with manual escaping | `XMLDocument` / `XMLElement` from Foundation | [VERIFIED: research/PITFALLS.md Pitfall 8] Hand-rolled string interpolation is the #1 source of `SetAVTransportURI` failures (DIDL-Lite double-escaping, unescaped `&` in track titles). XMLDocument handles escaping correctly. **In the spike, this matters less — the test WAV file's URL has no special chars — but the planner should still use XMLDocument so the pattern is correct when ported to Phase 3.** |
| WAV header byte construction | Manually packing little-endian UInt32s into a `Data` buffer with bit shifts | `AVAudioFile(forWriting:settings:)` from AVFoundation OR a tiny inline helper that writes the 44 well-known bytes | If using AVFoundation: zero risk. If hand-rolling: there are exactly 44 well-known bytes; reference any "minimal WAV header" gist. The spike's `test-stream.wav` is **pre-recorded once** and committed as a fixture — no runtime header generation needed. Only the SPIKE-02 PCM-to-file writer needs runtime header construction. |
| HTTP server framing for the audio stream | Bare `Darwin.socket` + `accept` + `send` loop | `NWListener` with TCP parameters and a per-connection `NWConnection.send` | [VERIFIED: research/STACK.md] Apple-blessed, integrates with strict concurrency, and the same listener will be reused (in spirit) by Phase 4. The CLI doesn't need `com.apple.security.network.server` because it's not sandboxed. |
| Multicast UDP send/receive | `NWConnection` with multicast remote (won't work — `NWConnection` is unicast-only) | `NWConnectionGroup(with: NWMulticastGroup, using: .udp)` | [VERIFIED: research/STACK.md + Apple docs] NWConnection does not support multicast. NWConnectionGroup is the **only** Apple-blessed multicast API. Have BSD socket fallback ready (Section 3 OQ-2). |
| TCP unique URL token (per-stream cache-busting) | UUID library or random string generator | `UUID().uuidString` | Foundation built-in. Spike URL is `http://<ip>:<port>/spike-<uuid>.wav`. |
| SSDP packet timing / retry logic | Custom timer / retry loop | Send M-SEARCH 3 times spaced 1s apart (UDP packet loss is real on Wi-Fi), collect responses for `MX + 2s = 5s` total | Standard SSDP discipline; the spike does this inline, not via a library. |

**Key insight:** The spike's "don't hand-roll" list is short because the spike is short. The planner should resist the urge to build the production abstractions early. Every line of spike code that gets clever is a line that has to be discarded.

## Common Pitfalls

### Pitfall 1: Spike runs the SOAP call but the SOAP envelope is malformed

**What goes wrong:** Sonos returns HTTP 200 with a SOAP fault body containing `<errorCode>402</errorCode>` (Invalid Args), `<errorCode>714</errorCode>` (Illegal MIME-Type), or `<errorCode>718</errorCode>` (Invalid InstanceID). The spike sees HTTP 200 and reports success when the action was actually rejected.

**Why it happens:** UPnP encodes errors at the SOAP body level, not the HTTP status. Common failure modes: missing `xmlns:u` namespace declaration on the action element, `InstanceID` value omitted (must be `0`, not empty), `SOAPACTION` header missing the literal quotes around the value.

**How to avoid:** Always parse the response body and check for `<s:Fault>` before declaring success. The spike's `sendSOAP()` helper must throw if the body contains a fault, regardless of HTTP status. [VERIFIED: research/PITFALLS.md Integration Gotchas table — "SOAP over HTTP / Forgetting SOAPACTION header / Sonos returns 405 or 412 without the right SOAPACTION header (note the literal quotes around the value)"]

**Warning signs:** SOAP response 200 OK but Sonos audibly does nothing. `GetTransportInfo` reports STOPPED instead of PLAYING. The body contains `<s:Fault>`.

### Pitfall 2: Spike uses `http://` URI scheme — Sonos S1 fetches and immediately disconnects

**What goes wrong:** `SetAVTransportURI` returns 200 OK. Sonos opens a TCP connection to the spike's HTTP server. After a few hundred bytes, Sonos closes the connection. Audio plays for ~10 seconds at most, then stops.

**Why it happens:** [VERIFIED: research/STACK.md + research/PITFALLS.md Pitfall 4] Sonos S1 firmware routes `http://...` URLs through a track-oriented code path that requires `Content-Length` and treats the response as a finite file. For live/radio-style streams, the URI must use `x-rincon-mp3radio://`, which switches Sonos into Shoutcast mode (open-ended stream, no chunked encoding).

**How to avoid:** The spike's `runSonosPlay` builds the URL as `x-rincon-mp3radio://<mac-ip>:<port>/spike-<uuid>.wav` even though the underlying `NWListener` is plain HTTP. The scheme replacement happens client-side (in the SOAP body) — the listener sees normal HTTP GET requests.

**Warning signs:** Sonos plays for ~10s then stops; HTTP server logs show client closing connection mid-stream; transport state cycles `STOPPED → TRANSITIONING → STOPPED`.

### Pitfall 3: Spike's `NWListener` uses HTTP/1.1 + chunked encoding by default

**What goes wrong:** Same symptom as Pitfall 2 — Sonos plays for a few seconds then stops. But the URI scheme is correct. The actual problem is that the spike's response framing uses `Transfer-Encoding: chunked` because that's the obvious choice for an unknown-length live stream.

**Why it happens:** [VERIFIED: research/PITFALLS.md Pitfall 4 + Sonos community thread] Sonos S1 does not handle `Transfer-Encoding: chunked` correctly for streaming audio. The Shoutcast/Icecast convention — and the only path AirConnect, swyh-rs, and SWYH have made work — is HTTP/1.0 + `Connection: close` + no `Content-Length` + no `Transfer-Encoding`.

**How to avoid:** The spike's `NWListener` connection handler hand-writes the HTTP response status line as `HTTP/1.0 200 OK\r\n`, sets exactly these headers — `Content-Type: audio/wav` (or `audio/aac` for AAC), `Connection: close`, `Cache-Control: no-cache` — and then writes the WAV body bytes. Do NOT use any high-level HTTP server abstraction that adds `Transfer-Encoding` or `Content-Length` automatically.

**Warning signs:** Same as Pitfall 2 — easy to confuse the two failure modes. Use `curl -v http://<ip>:<port>/spike-...wav` from another machine to inspect the actual headers the spike is sending.

### Pitfall 4: SPIKE-02 test consumer creates a second `CATapDescription` instead of fanning out

**What goes wrong:** Spike creates `let testTap = CATapDescription(stereoMixdownOfProcesses: webKitPIDs)`. Either (a) `AudioHardwareCreateProcessTap` returns an OSStatus error, (b) the EQ goes silent because the second tap's `mutedWhenTapped` "wins", (c) the test consumer gets silence, or (d) intermittent sample-rate artifacts depending on which tap was created first.

**Why it happens:** [VERIFIED: research/PITFALLS.md Pitfall 2 + research/ARCHITECTURE.md Conflict 1] Apple's docs do not specify behavior for two taps with `mutedWhenTapped` semantics on the same process. Empirical reports indicate level attenuation, ordering issues, or silent failures. **This is the entire reason FOUND-01 (`WebKitAudioTapCoordinator`) exists in Phase 2.**

**How to avoid:** The SPIKE-02 dual-consumer test does NOT create a second tap. It taps the **existing** `EqualizerAudioEngine.performRender` HAL I/O proc — adding a "side write" of `inputBuffers` to a `Mutex<Data>` ring that the CLI thread drains and writes to a `.wav` file. Section 4 below has the concrete plan.

**Warning signs:** Any new call to `CATapDescription(...)` or `AudioHardwareCreateProcessTap(...)` outside `ProcessTapHelper.swift` is a planning red flag — the planner must reject any task that proposes this.

### Pitfall 5: The CLI binary is sandboxed because `swift run` was invoked from a sandboxed terminal

**What goes wrong:** `swift run api-explorer sonos discover` returns zero devices, even though the user can see Sonos in the official Sonos app on the same Mac. SSDP packets aren't leaving.

**Why it happens:** Some terminal apps (e.g., the macOS Terminal.app under specific configurations, or certain App Store terminal apps) can run their child processes inside a sandbox container. The CLI then needs the multicast entitlement.

**How to avoid:** Spike documentation tells the user to invoke from a known non-sandboxed terminal (Terminal.app, iTerm2 — both unsandboxed by default). If `discover` returns nothing, the spike's `--bsd` fallback (BSD socket multicast) is the diagnostic — if BSD also fails, the issue is sandbox or firewall, not the code.

**Warning signs:** `tcpdump -i any port 1900` shows no outgoing M-SEARCH packets when `swift run api-explorer sonos discover` is invoked.

### Pitfall 6: Latency measurement times the SOAP call instead of the audible silence

**What goes wrong:** The spike measures `t_silence - t_pause_request_sent` = 100ms and reports "great, latency is 100ms!" But the user pressed pause and *heard* music for another 2 seconds.

**Why it happens:** [VERIFIED: research/PITFALLS.md Pitfall 9] Sonos S1 has a ~2-second input pre-buffer that is not user-configurable. The SOAP call returns quickly, but the speaker keeps playing the buffered audio. Pause-to-silence latency is dominated by the Sonos-side buffer, not the round-trip.

**How to avoid:** The spike's measurement is **end-to-end**: from "user-clicked-pause-in-Kaset" (here: keyboard press in the CLI) to "audible silence at the speaker" (here: user presses spacebar when they hear silence). Section 6 below has the methodology.

**Warning signs:** Reported latency < 500ms — that's only the SOAP RTT, not what the user hears.

## Multicast Entitlement Request — Ready-to-Paste Body (SPIKE-01)

Apple's request URL: **https://developer.apple.com/contact/request/networking-multicast** (requires Apple Developer login).

Approval typical SLA: **3–5 business days** [CITED: Apple Developer Forums thread 663271 — "It usually takes 3 to 5 workdays before you receive Apple's email about their approval"]. Earlier project research said 1–2 weeks; the planner should treat this as 3–10 business days and assume worst case.

**Form scope:** The entitlement is granted **per-team, not per-app** [CITED: Apple Developer Forums thread 679089 + 663271]. Once approved for the team that owns the Kaset bundle ID, every app from that team can use it.

**Known form fields** (the form requires login so exact wording is from forum-confirmed reports): App identifier (Kaset's bundle ID `com.sertacozercan.Kaset`), App Store URL, Use case description (free text).

### Ready-to-paste use case description

> **App:** Kaset (`com.sertacozercan.Kaset`) — a native macOS YouTube Music client.
>
> **Use case:** Kaset uses SSDP (Simple Service Discovery Protocol, RFC-equivalent) over IPv4 UDP multicast to `239.255.255.250:1900` to discover Sonos S1-generation speakers (Play:1, Play:3, Play:5 Gen 1, Connect, Connect:Amp) on the user's local network. Once a Sonos device is discovered, Kaset acts as a UPnP/SOAP control point and HTTP audio source, allowing the user to route Kaset's playback to their Sonos speakers — a capability the Sonos system itself does not provide for YouTube Music on this hardware generation.
>
> **Why no alternative exists:** Sonos S1-generation hardware does not support the modern Sonos Cloud Control API. Sonos Music Service / SMAPI partnership is reserved for licensed music partners and is not available to indie macOS developers. Bonjour/mDNS is not used by Sonos S1 for service advertisement — UPnP/SSDP is the only discovery protocol the hardware exposes. Manual IP entry is provided as a fallback for users with multicast-restricted networks (VLANs, hostile Wi-Fi), but the primary discovery flow requires SSDP.
>
> **Multicast group + port:** `239.255.255.250:1900` (UPnP standard).
> **Direction:** Send M-SEARCH multicast; receive unicast HTTP/1.1 200 OK responses from devices.
> **Frequency:** Once at app launch and on a periodic refresh (default every 60 seconds, with passive listen for `ssdp:alive` NOTIFY broadcasts in between).
> **Scope:** Local network only. No multicast traffic leaves the user's LAN.
>
> **App Store status:** [User to fill — App Store URL if listed; otherwise note "Distributed outside the App Store via direct download with Sparkle auto-update" — see Apple Developer Forums thread 679128 for the no-App-Store-URL workaround.]

[ASSUMED — exact form questions and required field labels because Apple's form is behind login. The above is structured to satisfy the publicly documented requirements; user should adapt to actual field labels at submission time.]

**Risks if wrong:** Apple may ask follow-up questions or reject. Approval delays push SPIKE-04's sandboxed re-test (D-06) into Phase 3 timing. Mitigation per D-05: spike CLI runs without sandbox, so the SSDP code path is validated in week 1 regardless of Apple's response.

## Section 2 — Sonos S1 SOAP Envelope Reference (SPIKE-03 + Phase 3 prep)

All SOAP requests share this envelope structure [VERIFIED: svrooij Sonos API docs — https://sonos.svrooij.io/services/av-transport]:

```xml
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
            s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <!-- {ActionElement} -->
  </s:Body>
</s:Envelope>
```

**Required HTTP request headers for every SOAP POST:**

| Header | Value | Notes |
|--------|-------|-------|
| `Content-Type` | `text/xml; charset="utf-8"` | Lowercase `utf-8`; some Sonos firmware quirks reject other quoting styles |
| `SOAPACTION` | (per-action; see below — INCLUDING the literal double quotes) | [VERIFIED: research/PITFALLS.md] Without the literal quotes, Sonos returns 405/412 |
| `Connection` | `close` | Match Sonos's expected pattern; minor but consistent across reference impls |

### AVTransport actions (control endpoint: `http://<ip>:1400/MediaRenderer/AVTransport/Control`)

#### `SetAVTransportURI`

**SOAPACTION:** `"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"`

```xml
<u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
  <InstanceID>0</InstanceID>
  <CurrentURI>x-rincon-mp3radio://192.168.1.42:8088/spike-{uuid}.wav</CurrentURI>
  <CurrentURIMetaData>{didl-lite-escaped-xml-or-empty}</CurrentURIMetaData>
</u:SetAVTransportURI>
```

**For the spike, `CurrentURIMetaData` MAY be empty** (`<CurrentURIMetaData></CurrentURIMetaData>`). The track will appear as "Untitled" on the Sonos but playback works. DIDL-Lite is a Phase 5 (OUT-03) concern.

#### `Play`

**SOAPACTION:** `"urn:schemas-upnp-org:service:AVTransport:1#Play"`

```xml
<u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
  <InstanceID>0</InstanceID>
  <Speed>1</Speed>
</u:Play>
```

#### `Pause`

**SOAPACTION:** `"urn:schemas-upnp-org:service:AVTransport:1#Pause"`

```xml
<u:Pause xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
  <InstanceID>0</InstanceID>
</u:Pause>
```

#### `Stop`

**SOAPACTION:** `"urn:schemas-upnp-org:service:AVTransport:1#Stop"`

```xml
<u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
  <InstanceID>0</InstanceID>
</u:Stop>
```

#### `GetTransportInfo`

**SOAPACTION:** `"urn:schemas-upnp-org:service:AVTransport:1#GetTransportInfo"`

```xml
<u:GetTransportInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
  <InstanceID>0</InstanceID>
</u:GetTransportInfo>
```

**Response body shape** (extract from SOAP envelope):
```xml
<u:GetTransportInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
  <CurrentTransportState>PLAYING</CurrentTransportState>
  <CurrentTransportStatus>OK</CurrentTransportStatus>
  <CurrentSpeed>1</CurrentSpeed>
</u:GetTransportInfoResponse>
```

**`CurrentTransportState` values:** `STOPPED`, `PLAYING`, `PAUSED_PLAYBACK`, `TRANSITIONING`. Per CONTEXT.md D-09, the SPIKE-03 acceptance bar requires `CurrentTransportState` to remain `PLAYING` for ≥30s.

### RenderingControl actions (control endpoint: `http://<ip>:1400/MediaRenderer/RenderingControl/Control`)

#### `SetVolume`

**SOAPACTION:** `"urn:schemas-upnp-org:service:RenderingControl:1#SetVolume"`

```xml
<u:SetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
  <InstanceID>0</InstanceID>
  <Channel>Master</Channel>
  <DesiredVolume>50</DesiredVolume>
</u:SetVolume>
```

`DesiredVolume`: 0–100. `Channel`: `Master` (most common), or `LF` / `RF` for stereo-pair fine control.

#### `SetMute`

**SOAPACTION:** `"urn:schemas-upnp-org:service:RenderingControl:1#SetMute"`

```xml
<u:SetMute xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
  <InstanceID>0</InstanceID>
  <Channel>Master</Channel>
  <DesiredMute>1</DesiredMute>
</u:SetMute>
```

`DesiredMute`: `1` for muted, `0` for unmuted.

[VERIFIED: All envelopes above cross-checked against svrooij Sonos API docs — https://sonos.svrooij.io/services/av-transport and https://sonos.svrooij.io/services/rendering-control]

**Notes for the planner:**
- `InstanceID` is **always `0`** for Sonos. Don't expose it as a parameter in spike subcommands.
- `Speed` for `Play` is **always `1`**. Sonos technically allows fractions but no production Sonos client uses anything else.
- The `xmlns:u` namespace declaration on the action element is **mandatory**. Without it, Sonos returns 401 (Action Failed) or 402 (Invalid Args).
- The spike does NOT need to issue `Stop` or `Pause` for SPIKE-03 — only `SetAVTransportURI` + `Play` + `GetTransportInfo` (poll for PLAYING state). `Pause` is only needed for SPIKE-05 latency.

## Section 3 — SSDP M-SEARCH Packet (SPIKE-04)

### Exact UDP packet body bytes

Send to multicast group `239.255.255.250:1900`. Body bytes (each `\r\n` is literal CR+LF):

```
M-SEARCH * HTTP/1.1\r\n
HOST: 239.255.255.250:1900\r\n
MAN: "ssdp:discover"\r\n
MX: 3\r\n
ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n
\r\n
```

**Field meanings** [VERIFIED: research/STACK.md + williamboles.com/discovering-whats-out-there-with-ssdp/ + UPnP Device Architecture spec]:

| Field | Value | Notes |
|-------|-------|-------|
| Request line | `M-SEARCH * HTTP/1.1` | Literal — `*` not a path |
| `HOST` | `239.255.255.250:1900` | Always this value (the multicast group itself) |
| `MAN` | `"ssdp:discover"` | INCLUDING the literal quotes |
| `MX` | `3` | Max wait seconds. UPnP spec: 1–5. Devices reply with random delay 0..MX seconds to spread load |
| `ST` | `urn:schemas-upnp-org:device:ZonePlayer:1` | **Sonos-specific** root device type. Alternative: `ssdp:all` for all UPnP devices, then filter by manufacturer |
| trailing blank line | `\r\n\r\n` | Two CRLFs total at the end (one to terminate `ST`, one for the blank line) |

**Repetition discipline:** Send the M-SEARCH packet **3 times spaced 1 second apart** (UDP packet loss on Wi-Fi is real), then collect responses for `MX + 2` = 5 seconds total. Total subcommand duration ≈ 7 seconds.

### Expected response shape

Sonos devices respond with **HTTP/1.1 200 OK** as a unicast UDP packet to the M-SEARCH sender's source port:

```
HTTP/1.1 200 OK\r\n
CACHE-CONTROL: max-age=1800\r\n
EXT:\r\n
LOCATION: http://192.168.1.42:1400/xml/device_description.xml\r\n
SERVER: Linux UPnP/1.0 Sonos/56.0-76060 (ZP100)\r\n
ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n
USN: uuid:RINCON_000E58XXXXXXX::urn:schemas-upnp-org:device:ZonePlayer:1\r\n
X-RINCON-BOOTSEQ: 12\r\n
X-RINCON-HOUSEHOLD: Sonos_xxxxxxxxxxxxxxxxxxxxxxx\r\n
X-RINCON-WIFIMODE: 0\r\n
\r\n
```

**Spike extracts:**
- `LOCATION` — the URL of `device_description.xml`. The spike GETs this URL with `URLSession` and extracts `<roomName>` from the XML for the `--verbose` output.
- IP and port — parsed from the `LOCATION` URL. The IP becomes the `<ip>` argument to subsequent `sonos play` / `sonos measure-latency` calls.
- `USN` — uniquely identifies the device. Spike de-duplicates by USN if the same device responds to multiple M-SEARCH iterations.

### `NWConnectionGroup` setup shape

```swift
// Source: research/STACK.md + Apple docs
// File: Sources/APIExplorer/main.swift (added inline; throwaway)

import Network

func sendSSDPMSearchViaNWConnectionGroup(timeout: TimeInterval) async throws -> [DiscoveredSonosDevice] {
    let multicast = try NWMulticastGroup(
        for: [.hostPort(host: "239.255.255.250", port: 1900)]
    )
    let group = NWConnectionGroup(with: multicast, using: .udp)

    let mSearch = """
    M-SEARCH * HTTP/1.1\r\n\
    HOST: 239.255.255.250:1900\r\n\
    MAN: "ssdp:discover"\r\n\
    MX: 3\r\n\
    ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\
    \r\n
    """.data(using: .utf8)!

    var devices: [String: DiscoveredSonosDevice] = [:]  // dedup by USN

    // Note: Use Mutex<[String: DiscoveredSonosDevice]> in Swift 6 strict concurrency
    // OR an actor wrapping the dict. The plan should pick one.

    group.setReceiveHandler(maximumMessageSize: 65_535, rejectOversizedMessages: true) {
        message, content, _ in
        guard let content else { return }
        if let device = parseSSDPResponse(content) {
            devices[device.usn] = device
        }
    }

    group.start(queue: .global())
    group.send(content: mSearch) { _ in }
    try? await Task.sleep(for: .seconds(1))
    group.send(content: mSearch) { _ in }
    try? await Task.sleep(for: .seconds(1))
    group.send(content: mSearch) { _ in }
    try? await Task.sleep(for: .seconds(timeout))
    group.cancel()

    return Array(devices.values)
}
```

### Documented edge case + BSD socket fallback

[VERIFIED: Apple Developer Forums thread 657849 (FB8461681)] There is a documented bug where `NWConnectionGroup` may not deliver unicast HTTP/1.1 200 OK responses (though it correctly delivers multicast NOTIFY messages). Reports indicate this persisted across multiple iOS 14 betas through GM. As of macOS 26 (April 2026) the bug status is **unconfirmed** — Apple has not posted a fix announcement and no follow-up forum post confirms resolution. **The spike must have the BSD socket fallback ready.** This is the entire reason CONTEXT.md "Claude's Discretion" allows for `NWConnectionGroup` vs BSD socket as a spike output.

**BSD fallback shape:**

```swift
// Source: standard BSD socket multicast pattern; pattern present in research/STACK.md
// File: Sources/APIExplorer/main.swift (added behind --bsd flag)

import Darwin

func sendSSDPMSearchViaBSDSocket(timeout: TimeInterval) async throws -> [DiscoveredSonosDevice] {
    let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    defer { close(sock) }

    // Allow multicast send + receive
    var ttl: Int32 = 4
    setsockopt(sock, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<Int32>.size))

    var loop: UInt8 = 1
    setsockopt(sock, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, socklen_t(MemoryLayout<UInt8>.size))

    // Bind to ephemeral port for replies
    var bindAddr = sockaddr_in()
    bindAddr.sin_family = sa_family_t(AF_INET)
    bindAddr.sin_port = 0  // ephemeral
    bindAddr.sin_addr.s_addr = INADDR_ANY.bigEndian
    let bindResult = withUnsafePointer(to: &bindAddr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            bind(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else { throw POSIXError(.EADDRINUSE) }

    // Send M-SEARCH
    var dest = sockaddr_in()
    dest.sin_family = sa_family_t(AF_INET)
    dest.sin_port = UInt16(1900).bigEndian
    inet_pton(AF_INET, "239.255.255.250", &dest.sin_addr)

    let msearch = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\nST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n"
    let bytes = Array(msearch.utf8)

    for _ in 0..<3 {
        bytes.withUnsafeBufferPointer { buf in
            withUnsafePointer(to: &dest) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    _ = sendto(sock, buf.baseAddress, buf.count, 0, sa,
                               socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        try? await Task.sleep(for: .seconds(1))
    }

    // Receive loop with select() or non-blocking + sleep until timeout
    // ... (planner: standard recvfrom loop, dedup by USN, return devices)
    return []  // shape only
}
```

The planner should not implement both fully — only the `NWConnectionGroup` path. The BSD path is a contingency that gets implemented (in the same plan) only IF the NWConnectionGroup path returns zero devices despite `tcpdump` showing M-SEARCH packets leaving the Mac.

## Section 4 — SPIKE-02 Dual-Consumer Test Design

### Recommended approach: in-place fan-out at `EqualizerAudioEngine.performRender`

[VERIFIED: by reading `Sources/Kaset/Services/Audio/EqualizerAudioEngine.swift:247-348`] The existing render function already has access to `inputBuffers` (raw tap PCM, pre-EQ) and `outputBuffers` (post-EQ). The spike adds a **side-effect-only** write of `inputBuffers` to a `Mutex<[Float]>`-backed ring that a CLI thread drains and writes to a `.wav` file.

**Critical constraints:**
- The fan-out write must happen **inside the existing `performRender`** — no second `CATapDescription`, no second `AudioDeviceCreateIOProcID`. This proves the production fan-out architecture (Phase 2's `WebKitAudioTapCoordinator`) is viable without committing to the refactor in spike scope.
- The fan-out is added behind a build-time flag or `#if SPIKE_TAP_COEXIST` block. Production code path is unchanged when the flag is off. The spike branch is never merged.
- The audio thread MUST NOT allocate, lock blocking-ly, or call into Swift Concurrency. Use a lock-free SPSC ring or a Swift 6 `Mutex<...>` (which is lock-free for short writes).

### Concrete test plan

```swift
// Source: spike modification to existing EqualizerAudioEngine.performRender
// Spike branch only — never merged

// Add to EqualizerAudioEngine:
//   nonisolated(unsafe) static var spikeFanoutBuffer: SPSCRingBuffer<Float>?
//   (initialized by api-explorer sonos tap-coexist before EqualizerService.start())

// Add inside performRender, BEFORE the existing dst.update(from: src...) loop:
if let ringRef = Self.spikeFanoutBuffer {
    // Snapshot input PCM into the ring. Drop on overflow (no blocking).
    for channelIndex in 0..<channelCount {
        if let src = mutableInput[channelIndex].mData?
            .bindMemory(to: Float.self, capacity: frames)
        {
            ringRef.tryWrite(src, count: frames, channel: channelIndex)
        }
    }
    Self.spikeFrameCounter.wrappingIncrement(by: UInt64(frames), ordering: .relaxed)
}

// CLI side:
//   1. Allocates SPSCRingBuffer
//   2. Sets EqualizerAudioEngine.spikeFanoutBuffer = ring
//   3. Calls EqualizerService.shared.activate()  (existing API, starts the engine)
//   4. Tells PlayerService to play <test track>  (D-16 — passed as CLI arg)
//   5. Spawns a Task that drains the ring into a 16-bit PCM WAV file for 60 seconds
//   6. Reports:
//       - Frame count from EqualizerAudioEngine.spikeFrameCounter
//       - Frame count actually written to the WAV file
//       - File size + duration check
//       - Asks user: "Listen to the system audio with EQ on. Was anything different from baseline?"
//   7. User answers Y/N; spike records observation
```

**Test phases (the spike runs all three in sequence):**

| Phase | Duration | What it proves |
|-------|----------|----------------|
| Baseline (no fan-out) | 30s | EQ-on audible behavior on the user's known-loud track. User notes "this is normal" |
| Fan-out enabled (this is the test) | 60s | Frame counts match (fan-out frame count == EQ engine processed frame count); audible behavior unchanged from baseline; raw PCM file is sample-perfect (open in QuickTime, compare to WebView source visually + audibly) |
| Cleanup | — | Disable fan-out; confirm EQ behavior returns to baseline; no zombie state |

### Why NOT the alternatives

| Alternative | Why rejected |
|-------------|--------------|
| (a) Combine publisher fan-out at `EqualizerAudioEngine` level | `Combine` on the audio thread is forbidden (allocation + locking). Same lock-free ring buffer problem with extra Combine overhead. |
| (b) Parallel `ProcessTap` on the same WebKit PIDs | [VERIFIED: research/PITFALLS.md Pitfall 2] **Undefined HAL behavior.** This is the entire reason Phase 2 (FOUND-01) exists — the spike must not validate Phase 2 by doing exactly what FOUND-01 forbids. |
| (c) Render block on the AVAudioEngine output chain | `EqualizerAudioEngine` does NOT use `AVAudioEngine` — it uses a raw HAL I/O proc on a private aggregate device (see `EqualizerAudioEngine.swift:155-181`). There is no AVAudioEngine output chain to install a render block on. |

**Open Question for SPIKE-02:**

- **OQ-1:** Does the CLI process inherit the user's TCC grant for "Screen & System Audio Recording"? If the user has granted the production `Kaset.app` bundle the permission but not granted it to the terminal/`swift run` process, the tap creation will fail at `CGPreflightScreenCaptureAccess()` (see `ProcessTapHelper.swift:134`). The spike's CLI may need to be run with `tccutil` pre-grants or the user may need to manually approve the terminal app for system audio recording. **Plan-phase agent should include a "preflight" step in the SPIKE-02 plan that calls `CGPreflightScreenCaptureAccess()` and prompts the user with explicit instructions if it returns false.**

## Section 5 — SPIKE-03 HTTP Relay Test Server

### Minimal `NWListener` configuration

```swift
// Source: research/STACK.md + research/PITFALLS.md (HTTP/1.0 + Connection: close + no Content-Length + no chunked)
// File: Sources/APIExplorer/main.swift (added inline; throwaway)

import Network

func serveStaticAudioFile(
    path: URL,
    contentType: String,  // "audio/wav" or "audio/aac"
    macIP: String         // pre-detected LAN IP (see below)
) async throws -> (port: UInt16, sonosURL: URL) {
    let port: NWEndpoint.Port = .any  // Bind to ephemeral; read back from listener
    let listener = try NWListener(using: .tcp, on: port)
    let actualPort = try await waitForListenerStart(listener)

    let fileBytes = try Data(contentsOf: path)
    let uuid = UUID().uuidString
    let pathSuffix = contentType == "audio/wav" ? "wav" : "aac"

    listener.newConnectionHandler = { connection in
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
            // We don't actually parse the HTTP request — just wait for it to arrive,
            // then write a hand-built HTTP/1.0 response.
            let response = """
            HTTP/1.0 200 OK\r\n\
            Content-Type: \(contentType)\r\n\
            Connection: close\r\n\
            Cache-Control: no-cache\r\n\
            \r\n
            """.data(using: .utf8)! + fileBytes

            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    // Build the URL Sonos receives — note the x-rincon-mp3radio:// scheme
    let sonosURL = URL(string: "x-rincon-mp3radio://\(macIP):\(actualPort)/spike-\(uuid).\(pathSuffix)")!

    return (actualPort, sonosURL)
}

// Helper: detect the Mac's LAN IP. Must be the IP on the same subnet as Sonos.
// Use `getifaddrs()` to enumerate non-loopback IPv4 addresses; pick the one
// matching the network the user's Sonos is on (heuristic: 192.168.x.x or 10.x.x.x).
// Plan should make this a CLI arg fallback: --mac-ip <ip> if auto-detection picks wrong.
func detectMacLANIP() -> String? {
    // Standard getifaddrs() iteration; planner: this is well-documented.
    // Filter to IPv4, non-loopback, on en0/en1 interface (Wi-Fi/Ethernet).
    return nil  // shape only
}
```

### Critical wire-format requirements

| Requirement | Why |
|-------------|-----|
| Status line: `HTTP/1.0 200 OK` (NOT `HTTP/1.1`) | [VERIFIED: research/PITFALLS.md Pitfall 4] Sonos S1 expects radio-style HTTP/1.0; HTTP/1.1 may trigger chunked encoding by some server stacks |
| `Connection: close` header | Tells Sonos the stream ends when the TCP connection ends — no need for `Content-Length` |
| **NO** `Content-Length` header | For the SPIKE-03 static file we COULD include it (it's a finite file), but the Phase 4 production server WILL NOT have a known length, so we omit it now to validate the production framing |
| **NO** `Transfer-Encoding: chunked` header | [VERIFIED: research/PITFALLS.md Pitfall 4 + Sonos community thread 6763502] Sonos S1 does not handle chunked correctly for streams; this is the most common bridge-breaks-Sonos cause |
| `Content-Type: audio/wav` for WAV | Sonos's URL-suffix-based codec detection treats `.wav` as PCM in WAV container |
| `Content-Type: audio/aac` for AAC-in-ADTS | [VERIFIED: research/PITFALLS.md Pitfall 3] One of the documented-supported MIME types for S1; alternative `audio/mp4` for AAC-in-MP4-container (NOT applicable here — we're using ADTS framing) |
| URL handed to Sonos: `x-rincon-mp3radio://<ip>:<port>/spike-<uuid>.{wav,aac}` | [VERIFIED: research/STACK.md + Sonos community thread 6763502] **Despite the `mp3radio` name, this scheme works for any radio-style stream**, not just MP3. Sonos sees the scheme and switches to Shoutcast/long-buffer mode. The actual TCP request arriving at our `NWListener` is plain `GET /spike-<uuid>.wav HTTP/1.1`. |
| URL suffix matches `Content-Type` | [VERIFIED: research/PITFALLS.md Pitfall 3] Mismatch (e.g., `.wav` URL with `audio/aac` Content-Type) is a fast UPnP error 714 |

### Test-content file specs

Per CONTEXT.md D-17, **pre-recorded WAV/AAC files** (NOT live-encoded):

| File | Spec | Where to store |
|------|------|----------------|
| `test-stream.wav` | Stereo, 16-bit PCM, 44.1 kHz or 48 kHz, ~30s, ~5 MB | `.planning/phases/01-spike/fixtures/test-stream.wav` (committed to git for reproducibility) |
| `test-stream.aac` | Stereo, AAC-LC in ADTS framing, 192 kbps, 44.1 kHz, ~30s, ~750 KB | `.planning/phases/01-spike/fixtures/test-stream.aac` (committed) |

**How to generate the fixtures (one-time, before SPIKE-03 runs):**

```bash
# Pull a known-loud, dynamic-range-rich 30s sample from any source.
# Recommendation: a known-good music sample (royalty-free) so the user can
# share the spike repo without licensing concerns.

# WAV (stereo, 16-bit, 44.1kHz):
ffmpeg -i source.mp3 -t 30 -acodec pcm_s16le -ar 44100 -ac 2 \
    .planning/phases/01-spike/fixtures/test-stream.wav

# AAC-in-ADTS (192kbps stereo):
ffmpeg -i source.mp3 -t 30 -c:a aac -b:a 192k -ar 44100 -ac 2 -f adts \
    .planning/phases/01-spike/fixtures/test-stream.aac
```

`ffmpeg` is not a project dep — used only at fixture-generation time. The fixtures are checked into git so the spike is reproducible without ffmpeg installed.

### Acceptance bar (per CONTEXT.md D-09)

The `runSonosPlay` subcommand returns `exit 0` only if all three are true:

1. **Audible at speaker** — user-confirmed via interactive prompt: "Did you hear audio? [y/n]"
2. **≥30s uninterrupted** — spike polls `GetTransportInfo` every 5s for 30+s; all polls report `CurrentTransportState=PLAYING`
3. **Sonos confirms PLAYING** — same as above

If any of the three fails, `exit 1` (no-go). If audible but Sonos disconnects mid-stream (state goes STOPPED), `exit 2` (go-with-workaround) and the spike report flags the partial-success failure mode.

## Section 6 — SPIKE-05 Latency Methodology

### Recommended: manual stopwatch with 5 trials, median reported

This is the **safe, low-spike-scope path** and matches CONTEXT.md ROADMAP success criterion 4 ("Pause-to-silence latency measured against the user's actual Sonos hardware with a stopwatch (5 trials, median reported)").

```swift
// Source: planner-defined spike harness
// File: Sources/APIExplorer/main.swift

func runSonosMeasureLatency(ip: String, trials: Int = 5) async {
    print("⏱  SPIKE-05 — Pause-to-silence latency, \(trials) trials")
    print("   Target: <2s (aspirational); AirConnect baseline: 8–10s")
    print()

    // Pre-flight: confirm the static-file relay from runSonosPlay is still going,
    // OR start a fresh one. Trials below assume audible audio is currently playing.
    print("Pre-flight: ensure a Sonos zone at \(ip) is currently playing via the spike.")
    print("Press Enter when audio is audibly playing on the Sonos...")
    _ = readLine()

    var latenciesMs: [Int] = []
    for trial in 1...trials {
        print("\nTrial \(trial)/\(trials):")
        print("  Press Enter to send Pause SOAP. Then press Enter AGAIN the moment")
        print("  the Sonos goes silent. (You're stopwatching from your finger to your ear.)")

        _ = readLine()
        let pauseSent = Date()
        do {
            try await sendSOAP(host: ip, action: .pause, body: ["InstanceID": "0"])
        } catch {
            print("  ⚠️  SOAP failed: \(error). Skipping trial.")
            continue
        }
        print("  Pause SOAP sent at \(pauseSent.formatted(date: .omitted, time: .standard)).")

        _ = readLine()
        let silenceHeard = Date()
        let latencyMs = Int(silenceHeard.timeIntervalSince(pauseSent) * 1000)
        latenciesMs.append(latencyMs)
        print("  ⏱  Trial \(trial): \(latencyMs)ms")

        // Resume for next trial
        try? await sendSOAP(host: ip, action: .play, body: ["InstanceID": "0", "Speed": "1"])
        try? await Task.sleep(for: .seconds(2))  // let buffer refill
    }

    // Report
    let sorted = latenciesMs.sorted()
    let median = sorted[sorted.count / 2]
    print("\n📊 Results:")
    print("   Trials: \(latenciesMs)")
    print("   Median: \(median)ms")
    print("   Min: \(sorted.first ?? 0)ms  Max: \(sorted.last ?? 0)ms")

    if median <= 2000 { print("   ✅ GO: median ≤ 2.0s")  ; exit(0) }
    if median <= 2500 { print("   ⚠️  GO-WITH-WORKAROUND: median ≤ 2.5s — recommend Pause→Stop substitution (see report)") ; exit(2) }
    print("   ❌ NO-GO: median > 2.5s — pause UX likely unacceptable")
    exit(1)
}
```

### Optional: auto-correlate via tone burst (deferred to plan-phase discretion)

CONTEXT.md "Claude's Discretion" allows this. Honest assessment:

- **What it would do:** Inject a known short tone burst (e.g., 1 kHz sine, 50ms) into the audio stream every 500ms. Capture the Mac's microphone via `AVAudioEngine`. Cross-correlate captured audio against the known tone to find when each burst hits the speaker. Pause stops emitting the tone; the time to the LAST detected tone burst measures pause-to-silence.
- **Why it's cleaner:** Removes user-reaction-time variance (~150ms human reaction time, plus another ~50ms for finger-to-Enter).
- **Why it's NOT recommended for the spike:**
  1. Requires the Mac's microphone to be near the Sonos speaker — adds physical-setup friction. Quiet room. No background noise.
  2. Microphone-input permission UX. The CLI doesn't have a `NSMicrophoneUsageDescription` available the same way the app does.
  3. Doubles the spike scope: cross-correlation, FFT, peak detection logic that all need to be debugged. Spike scope creep risk.
  4. The user's reaction-time variance is largely consistent across trials, so the **median of 5 trials** already largely cancels it out.
- **When to revisit:** If the median latency from the manual method is in the 2.0–2.5s borderline range and the user wants ±100ms precision before deciding go-with-workaround vs. go.

**Recommendation for the planner:** Plan the manual stopwatch path. The auto-correlate path can be a Phase 1.x plan if the spike's manual measurement is ambiguous.

## Section 7 — Spike Report Template (SPIKE-06, per D-18/D-19)

The plan-phase agent generates a `runSpikeReport` task that writes the following file structure. Skeleton with placeholders:

```markdown
# Spike Report: Phase 1 — Sonos S1 Audio Integration

**Spike completed:** <YYYY-MM-DD>
**Test hardware:** <model strings — e.g., Sonos Play:1 (gen 1) at 192.168.x.x; Sonos Connect at 192.168.x.y>
**Test network:** <description — e.g., Home Wi-Fi, single subnet, no VLANs, 5GHz Wi-Fi for Mac>
**Multicast entitlement status:** <REQUESTED YYYY-MM-DD | APPROVED YYYY-MM-DD | PENDING — sandboxed re-test deferred to Phase 3>

---

## SPIKE-02: Second consumer of WebKit Core Audio process tap

**Hypothesis:** A second consumer of the existing `EqualizerService`-owned tap can read PCM frames in parallel with EQ rendering, with no HAL conflict and no audible artifact.

**What was tested:**
- Spike branch added a side-effect-only fan-out write inside `EqualizerAudioEngine.performRender` to a lock-free SPSC ring drained by a CLI thread to a `.wav` file.
- Test track: <user-supplied — e.g., "Daft Punk — Around the World, full mix">
- Duration: 60s baseline + 60s with fan-out enabled + 30s teardown verification

**How it was measured:**
1. Frame count from `EqualizerAudioEngine.spikeFrameCounter` vs frame count actually written to the WAV file
2. User A/B comparison: EQ-on audible behavior with and without the fan-out arm enabled
3. Sample-correctness check: opened the captured `.wav` in QuickTime; visually compared waveform to expected WebView source

**Raw observations:**
- EQ engine processed: <N1> frames in 60s
- Fan-out wrote: <N2> frames in 60s
- Frame match: <yes/no — and discrepancy if any>
- A/B audible difference: <none / subtle / clear>
- WAV file plays back correctly in QuickTime: <yes/no>
- Any audible artifacts (clicks, dropouts, sample-rate weirdness): <none / list>

**Verdict:** <GO / GO-WITH-WORKAROUND / NO-GO>

**Recommended action for Phase 2:**
<If GO: "Proceed with FOUND-01 (`WebKitAudioTapCoordinator`) as designed in research/ARCHITECTURE.md. The fan-out pattern is HAL-safe.">
<If GO-WITH-WORKAROUND: "Proceed with FOUND-01 but adjust FOUND-03 to support exclusive-consumer semantics. EqualizerService gains a 'mute when Sonos active' mode per CONTEXT.md D-13.">
<If NO-GO: "Re-scope milestone — second consumer not viable. Sonos audio path becomes mutex-with-EQ (D-13). Update FOUND-* requirements.">

---

## SPIKE-03: Sonos S1 accepts our HTTP audio stream

**Hypothesis:** Sonos S1 accepts a static audio file served via HTTP/1.0 + `Connection: close` + no `Content-Length` over the `x-rincon-mp3radio://` URI scheme. WAV first; AAC-in-ADTS second.

**What was tested:**
- Stage A — WAV: `.planning/phases/01-spike/fixtures/test-stream.wav` (stereo, 16-bit, 44.1kHz, 30s) served from `NWListener`; URL `x-rincon-mp3radio://<mac-ip>:<port>/spike-<uuid>.wav`
- Stage B — AAC: `.planning/phases/01-spike/fixtures/test-stream.aac` (AAC-LC ADTS, 192kbps, 30s); same listener pattern; URL ends `.aac`; `Content-Type: audio/aac`

**How it was measured:**
- `SetAVTransportURI` with the spike URL, then `Play`, then `GetTransportInfo` polled every 5s for ≥30s
- Acceptance bar (D-09): audible AND ≥30s uninterrupted AND Sonos `CurrentTransportState=PLAYING` for the duration

**Raw observations — WAV:**
- SOAP `SetAVTransportURI` HTTP status: <code>
- SOAP `Play` HTTP status + body fault check: <code / no fault>
- Audible at speaker: <yes/no>
- Duration uninterrupted: <Ns / underran at <T>>
- `GetTransportInfo` polling: <PLAYING for full duration / cycled to STOPPED at <T>>
- Sonos firmware version (from `GetZoneInfo` or device description): <version>

**Raw observations — AAC:**
- (same fields)

**Verdicts:**
- WAV: <GO / GO-WITH-WORKAROUND / NO-GO>
- AAC: <GO / GO-WITH-WORKAROUND / NO-GO>

**Recommended encoder format for v1:**
<If WAV=GO and AAC=NO-GO: "Ship v1 with WAV (per CONTEXT.md D-10). LAME deferred per D-10. Acknowledge ~1.4 Mbps over LAN as acceptable.">
<If WAV=GO and AAC=GO: "Ship v1 with WAV. Reconsider AAC for v1.x if real-world bandwidth becomes a complaint.">
<If WAV=NO-GO: "Re-scope — the entire architecture assumes WAV works. Possible recovery: investigate why WAV failed (sample rate mismatch, container header, etc.) before declaring NO-GO at the milestone level.">

---

## SPIKE-04: Swift-native SSDP discovery via `NWConnectionGroup`

**Hypothesis:** `NWConnectionGroup` + `NWMulticastGroup` correctly sends SSDP M-SEARCH and receives unicast HTTP/1.1 200 OK responses from Sonos S1 devices on the user's LAN.

**What was tested:**
- `swift run api-explorer sonos discover` from a non-sandboxed CLI (per CONTEXT.md D-05; multicast entitlement irrelevant in this context)
- M-SEARCH with `ST: urn:schemas-upnp-org:device:ZonePlayer:1`, MX=3, sent 3x at 1s intervals
- Cross-checked against `tcpdump -i any port 1900` to verify packets actually leave the Mac
- Cross-checked against the official Sonos S1 app on the same Mac: same devices visible?

**How it was measured:**
- Number of devices discovered (de-duplicated by USN)
- Round-trip time from M-SEARCH send to first response
- Each device's parsed room name from `device_description.xml` GET

**Raw observations:**
- `NWConnectionGroup` path:
  - Devices found: <N> (<list with room names + IPs>)
  - First-response RTT: <Tms>
  - Tcpdump confirmed M-SEARCH leaving: <yes/no>
  - Tcpdump confirmed responses arriving: <yes/no>
  - Responses delivered to NWConnectionGroup receive handler: <yes/no/partial>
- BSD socket fallback (only if NWConnectionGroup failed):
  - Same fields as above

**Sandboxed re-test (D-06):**
- Multicast entitlement status: <APPROVED YYYY-MM-DD | PENDING>
- If approved: re-tested inside `Kaset.app` bundle: <results>
- If pending: deferred to Phase 3 DISC-01

**Verdict:** <GO / GO-WITH-WORKAROUND / NO-GO>

**Recommended SSDP transport for Phase 3:**
<If NWConnectionGroup=GO: "Use `NWConnectionGroup` per research/STACK.md. Manual-IP fallback per DISC-03 covers VLAN/hostile-Wi-Fi cases.">
<If BSD-only=GO: "Use BSD socket multicast for SSDP. The FB8461681 NWConnectionGroup unicast bug appears to still bite macOS 26. Document the workaround in DISC-01 implementation.">
<If NO-GO: "Re-scope DISC-01 to manual-IP-entry-only for v1. SSDP discovery deferred to v1.x.">

---

## SPIKE-05: End-to-end pause-to-silence latency

**Hypothesis:** Pause-to-silence latency on the user's Sonos S1 hardware on the user's home network is ≤2.5s with the spike's basic `Pause` SOAP path (i.e., before any `Pause→Stop` optimization).

**What was tested:**
- Static stream from SPIKE-03 actively playing on the user's Sonos
- 5 trials of: keyboard-press (timestamp T0) → SOAP `Pause` sent → user listens for silence → keyboard-press (timestamp T1) → latency = T1 - T0
- After each trial, SOAP `Play` resumes for next trial

**How it was measured:**
- Manual stopwatch via `readLine()` Enter key on both ends
- Includes user reaction time variance (~150ms typical) on the silence-detection side

**Raw observations:**
- Trial 1: <Tms>
- Trial 2: <Tms>
- Trial 3: <Tms>
- Trial 4: <Tms>
- Trial 5: <Tms>
- Median: <Tms>
- Min/Max: <Tms / Tms>

**Comparison to baselines:**
- Spike target: ≤2000ms
- AirConnect documented: 8000–10000ms
- Sonos input pre-buffer (documented): ~2000ms minimum

**Verdict:** <GO (≤2000ms) / GO-WITH-WORKAROUND (≤2500ms; Pause→Stop substitution recommended) / NO-GO (>2500ms)>

**Recommended pause strategy for Phase 5:**
<If ≤2000ms: "Use SOAP `Pause` for user-initiated pause; SOAP `Play` for resume.">
<If 2000–2500ms: "Use SOAP `Stop` instead of `Pause` for user-initiated pause (drains Sonos buffer faster). On resume, `SetAVTransportURI`+`Play`. Adds ~500ms to resume but cuts pause-to-silence in half. Document the tradeoff in PlayerService UX.">
<If >2500ms: "Acknowledge the latency floor in user-facing copy. Pause UX may need a 'will pause shortly' indicator on the picker.">

---

## Milestone-Level Decision (D-19)

**Decision:** <PROCEED / PROCEED WITH SCOPE CHANGE / RE-SCOPE MILESTONE>

<If PROCEED: "All four bets pass. Roadmap advances to Phase 2 (Foundation Refactor) as planned.">

<If PROCEED WITH SCOPE CHANGE: "List the changes:
- FOUND-XX: changed from <X> to <Y> because <which spike result>
- AUDIO-XX: changed from <X> to <Y> because <which spike result>
- ...
The roadmap revision happens via `/gsd-revise-roadmap` in a follow-up command.">

<If RE-SCOPE MILESTONE: "List the failed bet(s) and why no workaround exists:
- SPIKE-XX failed: <description>; no acceptable workaround per research and CONTEXT.md D-XX
- Recommendation: <descope to manual-IP-only / drop Sonos S1 / pivot to S2-only / etc.>
This re-scoping is invoked via `/gsd-revise-milestone` in a follow-up command.">
```

## Code Examples

### Verified pattern: SOAP POST helper

```swift
// Source: planner-defined; envelope structure verified against svrooij Sonos API docs
// File: Sources/APIExplorer/main.swift

func sendSOAP(
    host: String,
    service: SonosService,  // .avTransport or .renderingControl
    action: String,
    bodyXML: String         // The <u:Action ...>...</u:Action> element only
) async throws -> Data {
    let endpoint = service == .avTransport
        ? "MediaRenderer/AVTransport/Control"
        : "MediaRenderer/RenderingControl/Control"
    let serviceURN = service == .avTransport
        ? "urn:schemas-upnp-org:service:AVTransport:1"
        : "urn:schemas-upnp-org:service:RenderingControl:1"

    guard let url = URL(string: "http://\(host):1400/\(endpoint)") else {
        throw NSError(domain: "Sonos", code: -1)
    }

    let envelope = """
    <?xml version="1.0" encoding="utf-8"?>
    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
      <s:Body>
    \(bodyXML)
      </s:Body>
    </s:Envelope>
    """

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 3.0  // SOAP should fail loud, not stall
    request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
    request.setValue("\"\(serviceURN)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
    request.setValue("close", forHTTPHeaderField: "Connection")
    request.httpBody = envelope.data(using: .utf8)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let http = response as? HTTPURLResponse else {
        throw NSError(domain: "Sonos", code: -2)
    }

    // Check for SOAP fault even on HTTP 200
    if let bodyString = String(data: data, encoding: .utf8),
       bodyString.contains("<s:Fault>") || bodyString.contains("<errorCode>") {
        throw NSError(
            domain: "Sonos",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "SOAP fault: \(bodyString.prefix(500))"]
        )
    }

    guard http.statusCode == 200 else {
        throw NSError(domain: "Sonos", code: http.statusCode)
    }

    return data
}

enum SonosService { case avTransport, renderingControl }
```

### Verified pattern: SetAVTransportURI invocation

```swift
let uri = "x-rincon-mp3radio://192.168.1.42:8088/spike-\(UUID().uuidString).wav"
let body = """
<u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
  <InstanceID>0</InstanceID>
  <CurrentURI>\(uri)</CurrentURI>
  <CurrentURIMetaData></CurrentURIMetaData>
</u:SetAVTransportURI>
"""
_ = try await sendSOAP(host: "192.168.1.42", service: .avTransport, action: "SetAVTransportURI", bodyXML: body)

let playBody = """
<u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
  <InstanceID>0</InstanceID>
  <Speed>1</Speed>
</u:Play>
"""
_ = try await sendSOAP(host: "192.168.1.42", service: .avTransport, action: "Play", bodyXML: playBody)
```

### Verified pattern: GetTransportInfo response parse

```swift
// Quick-and-dirty regex extract for the spike. NOT for production — Phase 3 uses XMLParser.
func extractTransportState(from data: Data) -> String? {
    guard let s = String(data: data, encoding: .utf8) else { return nil }
    let pattern = #"<CurrentTransportState>([^<]+)</CurrentTransportState>"#
    if let regex = try? NSRegularExpression(pattern: pattern),
       let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
       let range = Range(match.range(at: 1), in: s) {
        return String(s[range])
    }
    return nil
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `print()` for SSDP discovery via raw `Darwin.socket` | `NWConnectionGroup` + `NWMulticastGroup` (Apple-blessed) | macOS 14.0 introduced `NWConnectionGroup`; FB8461681 unresolved as of macOS 26 | Spike validates which path the user's macOS 26 actually needs. Plan keeps BSD fallback ready. |
| `http://` URI scheme for Sonos URLs | `x-rincon-mp3radio://` URI scheme | Sonos firmware 6.4.2 (~2018) [VERIFIED: research/STACK.md + SoCo PR 443] | The spike MUST use `x-rincon-mp3radio://` from day one — no fallback to `http://`. |
| HTTP/1.1 + `Transfer-Encoding: chunked` for live audio | HTTP/1.0 + `Connection: close` + no `Content-Length` | AirConnect / SWYH / swyh-rs converged on this years ago | Spike `NWListener` is hand-built to bypass any HTTP library that would default to chunked. |
| ScreenCaptureKit for audio capture | Core Audio Process Tap (`CATapDescription`, macOS 14.2+) | The user's existing `ProcessTapHelper` already proves this | The spike does not consider SCK — explicitly rejected per `.planning/research/PITFALLS.md` Pitfall 1. |

**Deprecated/outdated:**
- AirSonos (Node.js) — archived June 2023; do not reference for *current* Sonos behavior, only for the historical bridge architecture pattern.
- Polling `GetTransportInfo` for state changes — superseded by GENA event subscriptions (deferred to v1.x per REQUIREMENTS.md EVENT-*).

## Project Constraints (from CLAUDE.md)

These directives override any default behavior. The planner MUST honor them in every spike task.

| Directive | Source | Enforcement in spike |
|-----------|--------|----------------------|
| Senior Swift Engineer; Swift 6.0+ / macOS 26+ / SwiftUI | CLAUDE.md "Role" | All spike code is Swift 6 with strict concurrency. CLI is non-`@MainActor` but uses `async/await`. |
| **NEVER leak secrets, cookies, API keys, or tokens** | CLAUDE.md Critical Rules | The spike's `sonos discover` output may include device USNs and IPs — these are LAN-scoped, not secrets, but the spike report must NOT include the user's exact LAN IP if the report is committed publicly. The planner should add a "redact LAN IPs before sharing" note in the SPIKE-04 plan. |
| **ALWAYS confirm before running UI tests** | CLAUDE.md Critical Rules | Not applicable — the spike runs no UI tests. The spike DOES run audible audio tests, which the planner should treat with similar care: each audio-emitting subcommand prompts the user before starting playback so they can adjust Sonos volume first. |
| **No third-party Swift packages** | CLAUDE.md Critical Rules | Spike adds zero `Package.swift` dependencies. All frameworks (Foundation, Network, CoreAudio, AudioToolbox, AVFoundation) are macOS-native. **LAME explicitly deferred per CONTEXT.md D-10.** |
| **Prefer API over WebView** | CLAUDE.md Critical Rules | Not applicable — Sonos has no Kaset-accessible API; UPnP/SOAP IS the Sonos API. |
| **Improve API Explorer, Don't Write One-Off Scripts** | CLAUDE.md Critical Rules | This is the core principle of CONTEXT.md D-01. The planner MUST extend `Sources/APIExplorer/main.swift` — no new throwaway script files. |
| **Document Architectural Decisions** | CLAUDE.md Critical Rules | Spike does not produce ADRs (research is in `.planning/research/`, decisions are in CONTEXT.md). Phase 2 (FOUND-01) produces the first Sonos-related ADR. |
| **Preserve Standard macOS Shortcuts** | CLAUDE.md Critical Rules | Not applicable — spike has no UI. |
| **Build:** `swift build` | CLAUDE.md Build & Code Quality | Every spike plan ends with a `swift build` verification step. |
| **Unit tests:** `swift test --skip KasetUITests` | CLAUDE.md Build & Code Quality | The spike adds no tests (throwaway code). The planner does NOT need to add to test suites for spike work. |
| **Lint:** `swiftlint --strict && swiftformat .` | CLAUDE.md Build & Code Quality | Each plan ends with `swiftformat .` for the spike's `main.swift` additions. SwiftFormat `--self insert` is enforced — see Section "Critical SwiftFormat Detail" below. |
| **No `print()`** in production code | CLAUDE.md Coding Rules | Exception: `Sources/APIExplorer/main.swift` uses `print()` for CLI output — this precedent is established (see existing `main.swift:75`, `:84`, etc.). Production-bundle code (`Sources/Kaset/...`) still uses `DiagnosticsLogger`. |
| **No `.background(.ultraThinMaterial)`** | CLAUDE.md Coding Rules | Not applicable — no UI. |
| **No `DispatchQueue`** | CLAUDE.md Coding Rules | Spike code uses `async/await` and `Task`. The audio thread (in the SPIKE-02 fan-out) writes to a `Mutex<>` or lock-free SPSC ring; no `DispatchQueue.main.async`. **Exception:** `NWListener.start(queue:)` accepts a `DispatchQueue` as part of the framework boundary — this is allowed per the research/STACK.md note. |
| **No force unwraps (`!`)** | CLAUDE.md Coding Rules | Spike must use `guard let` / `if let` / typed `throws`. The example code in this document uses `URL(...)!` for brevity — the planner should plan to replace these with proper unwrapping. |
| **`@Observable` classes marked `@MainActor`** | CLAUDE.md Coding Rules | Not applicable — spike adds no `@Observable` classes. |
| **Swift Testing for new unit tests** | CLAUDE.md Coding Rules | Not applicable — spike adds no tests. |
| **Throw `YTMusicError.authExpired` on HTTP 401/403** | CLAUDE.md Coding Rules | Not applicable — Sonos doesn't use YouTube auth; SonosError is a Phase 3 concern. |
| **Use `.task` instead of `.onAppear { Task {} }`** | CLAUDE.md Coding Rules | Not applicable — no SwiftUI views. |

### Critical SwiftFormat Detail (CLAUDE.md callout)

> ⚠️ **SwiftFormat `--self insert` rule:** In static methods, call other static methods with `Self.methodName()`. In instance methods, use `self.property` explicitly.

The spike code in `main.swift` is at file-scope (top-level functions, not methods). `--self insert` does not apply. **But:** if the spike adds any `struct` or `enum` with methods, that struct's methods must use `self.` and `Self.` per the rule. The planner should always run `swiftformat .` as the last step of every plan.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Apple's multicast entitlement form fields are roughly: bundle ID, App Store URL, free-text use case description | Section 1 (multicast entitlement request) | LOW — the user adapts to actual form labels at submission time. The pre-written body is the value, not the field-name guess. |
| A2 | The CLI process inherits the user's "Screen & System Audio Recording" TCC grant when invoked from Terminal.app | Section 4 (SPIKE-02) — OQ-1 | MEDIUM — if false, SPIKE-02 needs an extra preflight step asking the user to grant the terminal app the permission. The spike already does `CGPreflightScreenCaptureAccess()` and reports the result, so this is detectable. |
| A3 | Sonos S1 firmware as of April 2026 still requires `x-rincon-mp3radio://` for live streams (i.e., the scheme has not been deprecated) | Section 5 (SPIKE-03) — Pitfall 2 | LOW — the scheme has been stable since firmware 6.4.2 (~2018) and S1 firmware is in maintenance mode. |
| A4 | `NWConnectionGroup` unicast-response bug FB8461681 may still bite macOS 26 | Section 3 (SPIKE-04) — BSD fallback rationale | LOW — the BSD fallback exists precisely because this is uncertain. Worst case: spend ~30 min implementing fallback that turns out unnecessary. |
| A5 | The user's Sonos S1 system is on the same LAN subnet as the Mac (no VLAN) | All Sonos sections | MEDIUM — if false, SSDP fails (Pitfall 5 in research/PITFALLS.md). The spike report must capture network topology. The user has confirmed this is "real home Wi-Fi" per CONTEXT.md D-15, but VLAN-on-Wi-Fi is uncommon enough to assume away for now. |
| A6 | Sonos S1 accepts `Content-Type: audio/wav` (rather than `audio/x-wav` or `audio/wave`) | Section 5 (SPIKE-03 wire format) | LOW — `audio/wav` is the IANA-registered media type. If the spike fails with `audio/wav`, swap to `audio/x-wav` as the second probe before declaring NO-GO. |
| A7 | `ffmpeg` is acceptable to use for fixture generation (one-time, not a runtime dep) | Section 5 (test content fixtures) | LOW — fixture generation is a developer task; ffmpeg is industry-standard. The fixtures are committed to git, not generated at spike runtime. |
| A8 | The user's terminal/`swift run` invocation is not sandboxed | Section 3 (D-05 + Pitfall 5) | LOW — Terminal.app and iTerm2 are unsandboxed by default. Apple Store terminal apps may be sandboxed, but the user is presumed to use a standard developer tool. |

## Open Questions

1. **OQ-1: Does the CLI process inherit the user's TCC grant for "Screen & System Audio Recording"?**
   - What we know: Tap creation requires the grant (`ProcessTapHelper.swift:134`). The user has presumably granted `Kaset.app` this permission.
   - What's unclear: Whether `swift run api-explorer` (a separate binary) inherits the grant. macOS TCC is per-binary, not per-team.
   - Recommendation: SPIKE-02 plan starts with a `CGPreflightScreenCaptureAccess()` preflight step. If false, instruct the user to either (a) grant the terminal app the permission via System Settings → Privacy & Security → Screen & System Audio Recording, or (b) re-bundle the spike as a notarized Helper app. Option (a) is faster and acceptable for spike scope.

2. **OQ-2: BSD socket multicast — do we need IPv6 multicast (`ff02::c`) as well as IPv4 (`239.255.255.250`)?**
   - What we know: Sonos S1 historically advertises on IPv4. IPv6 SSDP is supported by some UPnP devices but no Sonos-specific evidence.
   - What's unclear: Whether the user's network is IPv6-routed and whether Sonos S1 firmware sends IPv6 NOTIFY broadcasts.
   - Recommendation: SPIKE-04 implements IPv4 only. If discovery returns nothing, the BSD fallback is the next try, not IPv6. IPv6 SSDP is a Phase 3 (DISC-04 livestream) concern.

3. **OQ-3: What is the user's "test track" for SPIKE-02 (per CONTEXT.md D-16)?**
   - What we know: D-16 explicitly says "passed as a CLI arg" and Plan-phase suggests defaults but doesn't lock one in.
   - What's unclear: Default suggestion.
   - Recommendation: SPIKE-02 plan includes a default of "any high-dynamic-range track currently in the user's YouTube Music history". The plan asks the user to provide the videoId at runtime. Suggested defaults in the plan: any well-mastered modern pop track at moderate-to-loud volume (e.g., a Daft Punk or Taylor Swift track the user already plays often).

4. **OQ-4: How does the spike trigger PlayerService to play a specific track for SPIKE-02?**
   - What we know: SPIKE-02 needs the WebView to be playing audio for the tap to have anything to capture. PlayerService is `@MainActor @Observable` and the CLI doesn't have access to it directly.
   - What's unclear: Whether the spike (a) reuses the existing AppleScript scripting interface (`Sources/Kaset/Services/Scripting/ScriptCommands.swift`) to remote-control the Kaset app from the CLI, or (b) requires the user to manually start playback in Kaset before running the spike subcommand.
   - Recommendation: Option (b) — manual user-driven playback. The spike subcommand prompts: "Open Kaset, start playing your test track, then press Enter." Avoids cross-process coupling that would scope-creep the spike.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Swift toolchain (`swift run`) | All spike subcommands | Required (assumed present per `Package.swift`) | Swift 6.0+ | None — blocker if missing |
| macOS 26+ | All audio capture (SPIKE-02) | Required (assumed; Kaset already targets this) | 26.0+ | None |
| Sonos S1 hardware on LAN | SPIKE-03, SPIKE-04, SPIKE-05 | Per CONTEXT.md D-15: present, real home Wi-Fi | n/a | None — blocker for the entire phase |
| Apple Developer team | SPIKE-01 entitlement filing | Required (assumed; Kaset is signed/notarized for Sparkle) | n/a | None — but SPIKE-01 only requires the user to file the form, not block the spike |
| `tcpdump` | SPIKE-04 out-of-band verification | macOS-built-in (`/usr/sbin/tcpdump`) | system | Wireshark GUI as alternative |
| `curl` | SPIKE-03 out-of-band header verification | macOS-built-in (`/usr/bin/curl`) | system | None needed |
| `ffmpeg` | SPIKE-03 fixture generation (one-time, not runtime) | NOT bundled with macOS; user installs via Homebrew | any recent | Fixtures are committed to git, so once generated by ANY developer, no rerun needed |
| Multicast entitlement | SPIKE-04 sandboxed re-test only (D-06) | Pending Apple approval | n/a | D-05 fallback: run unsandboxed CLI in week 1 |
| `com.apple.security.network.server` | None in spike (Phase 4 only) | Not yet added to `Kaset.entitlements` | n/a | Not a blocker — CLI is not sandboxed |

**Missing dependencies with no fallback:**
- Sonos S1 hardware on LAN — but per CONTEXT.md D-15, this is confirmed present. Not actually missing.

**Missing dependencies with fallback:**
- Multicast entitlement (Apple-pending) — fallback per D-05: run CLI unsandboxed in week 1; re-test sandboxed in Phase 3 once approved.
- `ffmpeg` for fixture generation — not blocking the spike if fixtures are pre-generated. Planner should pre-generate fixtures and commit them as part of the SPIKE-03 plan.

## Validation Architecture

> Skipped per `.planning/config.json` `workflow.nyquist_validation: false`.

## Sources

### Primary (HIGH confidence)

- **In-tree code (HIGH):**
  - `Sources/Kaset/Services/Audio/ProcessTapHelper.swift` — verified existing tap implementation; SPIKE-02 reads from this without modification
  - `Sources/Kaset/Services/Audio/EqualizerAudioEngine.swift` — verified existing render path; SPIKE-02 fan-out hooks into `performRender` (line 247)
  - `Sources/APIExplorer/main.swift` — verified existing CLI subcommand pattern; spike adds `case "sonos":` to `runMain()` switch (line 1396)
  - `Kaset.entitlements` — verified current entitlement set (sandbox + audio-input + network.client + jit + files only; no multicast, no network.server)
  - `Info.plist` — verified `NSAudioCaptureUsageDescription` + `NSScreenCaptureUsageDescription` already declared

- **CONTEXT.md and project research (HIGH):**
  - `.planning/phases/01-spike/01-CONTEXT.md` — locked decisions D-01 through D-19
  - `.planning/research/SUMMARY.md` — executive synthesis; load-bearing facts for the spike
  - `.planning/research/STACK.md` — Sonos S1 wire format, encoder fork, multicast entitlement specifics
  - `.planning/research/PITFALLS.md` — 12 pitfalls; SPIKE-02..05 each falsify or validate one
  - `.planning/research/ARCHITECTURE.md` — 9-component design + dependency-driven build order
  - `CLAUDE.md` — coding rules (no `print`/`DispatchQueue`/force-unwrap, no third-party deps)

- **Sonos protocol references (HIGH — cross-checked):**
  - https://sonos.svrooij.io/services/av-transport — SetAVTransportURI / Play / Pause / Stop / GetTransportInfo SOAP envelopes [VERIFIED via WebFetch]
  - https://sonos.svrooij.io/services/rendering-control — SetVolume / SetMute / GetVolume SOAP envelopes [VERIFIED via WebFetch]

- **Apple official (HIGH):**
  - https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps — process tap API
  - https://developer.apple.com/documentation/network/nwmulticastgroup — multicast group API
  - https://developer.apple.com/contact/request/networking-multicast — entitlement request URL (confirmed reachable; form behind login)
  - https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast — entitlement docs

### Secondary (MEDIUM confidence)

- https://developer.apple.com/forums/thread/663271 — Apple multicast entitlement approval timeline ("3 to 5 workdays") [VERIFIED via WebSearch]
- https://developer.apple.com/forums/thread/679089 — multicast entitlement form requirements (App Store URL field) [VERIFIED via WebFetch]
- https://developer.apple.com/forums/thread/657849 — `NWConnectionGroup` unicast-response bug FB8461681 [VERIFIED via WebFetch — bug status unresolved as of forum thread]
- https://en.community.sonos.com/advanced-setups-229000/chunked-encoding-transfer-and-mp3-a-technical-question-6763502 — Sonos community confirmation on chunked encoding + `x-rincon-mp3radio://` [VERIFIED via WebFetch]
- https://williamboles.com/discovering-whats-out-there-with-ssdp/ — SSDP M-SEARCH packet shape with literal `\r\n` bytes [VERIFIED via WebFetch]

### Tertiary (LOW confidence — flagged for spike validation)

- The `audio/wav` vs `audio/x-wav` Content-Type preference (A6) — spike will validate by attempting `audio/wav` first
- Sonos S1 firmware April 2026 acceptance of `x-rincon-mp3radio://` (A3) — spike validates this as part of SPIKE-03 acceptance bar
- `NWConnectionGroup` unicast-response bug status on macOS 26 (A4) — spike validates this in SPIKE-04 with `--bsd` fallback ready

## Metadata

**Confidence breakdown:**
- Multicast entitlement request body: MEDIUM — exact form fields not verifiable without login; body content is well-supported by forum reports
- Sonos SOAP envelopes: HIGH — verified via WebFetch against svrooij docs which are the canonical third-party reference
- SSDP M-SEARCH packet format: HIGH — verified via WebFetch against multiple independent sources
- SPIKE-02 fan-out approach: HIGH — directly verified against existing `EqualizerAudioEngine.swift` source
- HTTP/1.0 + `x-rincon-mp3radio://` framing: HIGH — verified across PITFALLS.md, STACK.md, and Sonos community sources
- Latency methodology: HIGH for manual stopwatch (matches ROADMAP success criterion 4); MEDIUM for auto-correlate add-on (feasibility honest-assessed but not implemented)
- Spike report template: HIGH — directly templated from CONTEXT.md D-18/D-19

**Research date:** 2026-04-27
**Valid until:** 2026-05-27 (30 days for stable Sonos protocol surface; spike should run within this window before assumed-stable references drift)
