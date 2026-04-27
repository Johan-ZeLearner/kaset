# Phase 1: Spike - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-27
**Phase:** 1-spike
**Areas discussed:** Spike harness shape, Multicast entitlement plan, Encoder probe order + acceptance, Second-tap test methodology

---

## Spike harness shape

### Q1: How should the spike code be organized inside `Sources/APIExplorer/main.swift`?

| Option | Description | Selected |
|--------|-------------|----------|
| Per-bet subcommands | `api-explorer sonos discover` / `play <ip>` / `tap-coexist` / `measure-latency` — each bet runs in isolation; matches existing `auth/list/browse` pattern | ✓ |
| One mega-command | `api-explorer sonos-spike` runs all four bets in sequence and prints a combined report | |
| Top-level commands | `api-explorer sonos-discover` / `sonos-tap-test` / etc. Flat namespace | |
| You decide | Pick whatever fits existing CLI patterns best | |

**User's choice:** Per-bet subcommands
**Notes:** Claude added a discretion item — a thin `sonos spike-all` runner that drives subcommands in order for the final report.

---

## Multicast entitlement plan

### Q1: While waiting 1–2 weeks for Apple, how should the spike test SSDP discovery (SPIKE-04)?

| Option | Description | Selected |
|--------|-------------|----------|
| Run api-explorer non-sandboxed first | CLI is not subject to the App Sandbox; validate SSDP code path in week 1 without entitlement; re-test inside the .app once approved | ✓ |
| Wait for entitlement | File day 1, then block SPIKE-04 until Apple approves. Spike sits idle for 1–2 weeks | |
| Both in parallel | Non-sandboxed + a sandboxed harness behind a feature flag, side-by-side once entitlement lands | |

**User's choice:** Run api-explorer non-sandboxed first

### Q2: Who/how files the entitlement request day 1?

| Option | Description | Selected |
|--------|-------------|----------|
| User files manually | User opens Apple Developer Contact form, fills it in, pastes link to spike report. Plan-phase generates a checklist + template request text | |
| Plan-phase generates a draft user sends | Planner produces a ready-to-paste request body (use case, target devices, why no alternative). User sends it from their Apple ID | ✓ |
| Skip the request | Limit production to manual-IP entry only (no SSDP). Drops DISC-01. Not recommended | |

**User's choice:** Plan-phase generates a draft user sends

---

## Encoder probe order + acceptance

### Q1: Order to test encoder formats against Sonos S1 in SPIKE-03?

| Option | Description | Selected |
|--------|-------------|----------|
| WAV first, then AAC | Raw LPCM WAV is widest-compat (~1.4 Mbps Wi-Fi). If WAV fails, architecture is wrong — fail fast. If WAV works, try AAC for bandwidth | ✓ |
| AAC first, then WAV | Test preferred production path first; fall back if rejected | |
| Both in parallel | Spike both formats simultaneously; ship report comparing latency / dropouts / artifacts | |

**User's choice:** WAV first, then AAC

### Q2: What proves "Sonos S1 accepted this stream"?

| Option | Description | Selected |
|--------|-------------|----------|
| Audible + 30s clean | Audio audible at speaker + plays 30s without dropouts + Sonos stays in PLAYING state | ✓ |
| Audible + 5min clean | Stricter: 5 minutes uninterrupted. Catches buffer-underrun bugs that 30s misses | |
| Audible + Sonos diagnostics clean | 30s audible + cross-check Sonos `GetTransportInfo` for no underruns/errors | |

**User's choice:** Audible + 30s clean

### Q3: If AAC-in-ADTS is rejected by S1 and WAV works (likely outcome), what does the spike report recommend for v1?

| Option | Description | Selected |
|--------|-------------|----------|
| Ship v1 with WAV | 1.4 Mbps acceptable on home LAN; lossy YT Music source means lossless transport overkill; defer LAME | ✓ |
| Ship v1 with WAV, request LAME approval | Ship WAV, in parallel ask user for explicit LAME (LGPL) vendor approval for v1.x bandwidth optimization | |
| Re-scope spike to test more formats | Try Ogg Vorbis, Opus, FLAC at various bitrates. Adds 2–3 days; only worth it if bandwidth is a real concern | |

**User's choice:** Ship v1 with WAV

---

## Second-tap test methodology

### Q1: How does the spike prove EQ + Sonos can both consume the WebKit process tap?

| Option | Description | Selected |
|--------|-------------|----------|
| Both signals + frame counter | Two consumers register on existing tap; one feeds EQ, one writes raw PCM to file. Compare frame counts + audible A/B + sample-perfect file | ✓ |
| Audible A/B only | Run EQ at known settings on known-loud track, then add Sonos consumer. If output sounds the same, it works. Subjective | |
| Frame counter only | Verify both consumers receive same frame counts over 60s. Objective but misses non-sample-level audible artifacts | |

**User's choice:** Both signals + frame counter

### Q2: If SPIKE-02 fails (taps conflict), what's the acceptable fallback before re-scoping the milestone?

| Option | Description | Selected |
|--------|-------------|----------|
| Mutex: EQ off when Sonos active | When user picks Sonos zone, `EqualizerService` disables itself; re-enables when output returns to "This Mac". Milestone proceeds with FOUND-* adjusted | ✓ |
| Coordinator refactor required (no fallback) | If two consumers can't coexist via coordinator, architecture breaks — milestone re-scopes. Hardline | |
| Disable EQ entirely for v1 | Sacrifice EQ on Sonos output path; users re-enable manually if they understand conflict. Worse UX than mutex | |

**User's choice:** Mutex: EQ off when Sonos active

---

## Claude's Discretion

- Exact `api-explorer` arg-parsing convention (matches existing `main.swift` patterns; planner infers from file)
- 1,400-byte UDP packet shape for SSDP M-SEARCH (UPnP standard, not user-decided)
- Exact `NWListener` configuration for the test HTTP server (port choice, TLS off, bind address — `0.0.0.0:<dynamic>`)
- Exact SOAP envelope strings for `SetAVTransportURI` / `Play` / `GetTransportInfo` (UPnP/AVTransport standard, citable from research)
- Latency-measurement subcommand: stopwatch input vs auto-correlate tone burst (auto-correlate likely cleaner — Claude picks)
- WAV stream wrapping: header vs raw LPCM (S1 generally needs WAV header — Claude picks)
- Thin `sonos spike-all` runner added on top of per-bet subcommands

## Deferred Ideas

- LAME encoder vendoring (LGPL) — deferred from v1 entirely; re-open only if WAV bandwidth becomes a real-world user complaint after v1 ships
- Sandboxed-app SSDP testing — pending Apple approval; final validation happens during Phase 3 (DISC-01) once entitlement lands
- GENA event subscriptions (test feasibility, validate `LastChange` parsing) — explicitly v1.x; not in spike scope (EVENT-01..05 in REQUIREMENTS.md)
