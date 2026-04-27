# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-27)

**Core value:** A first-class native macOS YouTube Music experience that also reaches the user's actual home audio gear — including Sonos systems that don't speak AirPlay.
**Current focus:** Phase 1 — Spike (validate four technical bets before any production code)

## Current Position

Phase: 1 of 5 (Spike)
Plan: 0 of TBD in current phase
Status: Ready to plan
Last activity: 2026-04-27 — Roadmap created from 30 v1 requirements + research synthesis

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: —
- Trend: —

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Spike before scoping the build phase (PROJECT.md) — four unvalidated technical bets; cheaper to fail in spike than mid-build
- Target Sonos S1 / UPnP first — user's actual gear; no third-party UPnP library
- Mac-stays-awake acceptable for v1 — local relay is the only architecturally feasible path without Sonos partnership
- Foundation refactor (WebKitAudioTapCoordinator) before AUDIO phase — mandatory; second independent tap on same WebKit PIDs is undefined HAL behavior

### Pending Todos

None yet.

### Blockers/Concerns

- **Calendar-blocked:** SPIKE-01 (multicast entitlement) has 1–2 week Apple SLA. Must be filed day 1 of Phase 1 — SPIKE-04 testing in the sandboxed app cannot complete until granted.
- **Encoder fork unresolved until SPIKE-03:** AAC-in-ADTS is the recommended attempt; if Sonos S1 rejects it, fork escalates to user (vendor LAME w/ approval, raw WAV, or scope-reduce). Phase 4 cannot scope until decided.
- **Latency target aspirational:** <2s pause-to-silence is honest stretch goal; AirConnect baseline is 8–10s. SPIKE-05 measures reality; Phase 5 UX copy depends on the number.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| EVENT (v1.x) | UPnP GENA event subscriptions for bidirectional state sync | Deferred to v1.x | 2026-04-27 (initial roadmap) |
| POLISH (v1.x) | Album art, smart re-bond, AppleScript/NL extensions, diagnostics overlay | Deferred to v1.x | 2026-04-27 (initial roadmap) |
| GROUP (v1.x) | Multi-zone group coordinator routing | Deferred to v1.x | 2026-04-27 (initial roadmap) |
| EQ-ON-SONOS (v2) | Decide whether EQ DSP applies to Sonos stream | Deferred to v2 | 2026-04-27 (initial roadmap) |
| GAPLESS (v2) | Cross-track gapless playback over Sonos | Deferred to v2 | 2026-04-27 (initial roadmap) |
| S2-MODERN (v2) | Sonos S2 modern Local Control API | Deferred to v2 | 2026-04-27 (initial roadmap) |

## Session Continuity

Last session: 2026-04-27
Stopped at: Roadmap created (5 phases, 30/30 requirements mapped). Awaiting `/gsd-plan-phase 1` to begin spike planning.
Resume file: None
