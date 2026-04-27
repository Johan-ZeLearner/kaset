# Kaset

## What This Is

Kaset is a native macOS YouTube Music client (Swift 6 / SwiftUI, macOS 26+) that uses a hidden `WKWebView` for DRM-protected audio playback and `YTMusicClient` for all data fetching. Today it relies on macOS-level audio output, so external speakers only work when the user's gear supports AirPlay.

## Core Value

A first-class native macOS YouTube Music experience that **also reaches the user's actual home audio gear** — including Sonos systems that don't speak AirPlay.

## Requirements

### Validated

<!-- Inferred from existing code; treated as locked unless explicitly revisited. -->

- ✓ Browse YouTube Music (Home, Search, Library, Explore, podcasts) — existing
- ✓ DRM-protected playback via hidden `WKWebView` + `PlayerService` — existing
- ✓ Cookie + Keychain authentication via `WebKitManager` — existing
- ✓ Queue management, repeat/shuffle, transport controls — existing
- ✓ System-wide EQ via Core Audio process tap (`EqualizerService`) — existing
- ✓ AppleScript scripting interface (`.sdef`) — existing
- ✓ Sparkle auto-updates — existing
- ✓ FoundationModels integration (NL commands, lyrics analysis, queue/playlist refinement) — existing
- ✓ macOS audio output → AirPlay (works for AirPlay-capable speakers; **does not work for user's Sonos S1**) — existing

### Active

<!-- Current milestone: Sonos integration. Spike-first. -->

- [ ] **Discover** Sonos devices on the local network (S1 generation, UPnP/SSDP)
- [ ] **Stream** Kaset audio to Sonos speakers without requiring AirPlay
- [ ] **Control** transport from Kaset (play / pause / volume / skip) for the Sonos output
- [ ] **Validate technical feasibility via a spike** before locking scope or committing to a build phase

### Out of Scope

- **Sonos Music Service / SMAPI partnership** — requires Sonos partnership + YouTube Music licensing, neither of which an indie macOS client can deliver
- **Modern Sonos S2 Control API integration** — user's test gear is S1 only; defer until/unless newer hardware enters the picture
- **"Mac can sleep / Kaset can quit while Sonos keeps playing"** — aspirational, but the only realistic v1 path (local audio relay) requires the Mac to stay awake. Re-open if spike surfaces a workable cloud/partner path.
- **Cloud/server-side audio relay** — ongoing infra cost, ToS exposure, latency penalty, and operational burden inappropriate for a single-user macOS app
- **Third-party Swift packages for Sonos/UPnP** — repo policy is no new deps without approval; build native Swift UPnP/SOAP if needed

## Context

**Brownfield project.** Kaset is mature: ~24K LOC, ~49 SwiftUI views, established patterns (service-based MVC, `@Observable @MainActor` services, protocol-driven DI). See `.planning/codebase/` for the full map.

**Why this milestone now.** The user's home audio is a Sonos S1 setup (Play:1 / Play:3 / Play:5 Gen 1 / Connect / Connect:Amp generation). These devices don't support AirPlay, and they're frozen on S1 firmware which means no modern Sonos Control API. Spotify gets the seamless "pick a speaker, audio comes out of the Sonos" UX because Spotify is a registered Sonos music partner with a licensed SMAPI service — a path that isn't open to an indie YouTube Music client.

**The realistic v1 architecture** (subject to spike validation): Kaset becomes a local HTTP audio server. It captures the WebView's audio output in real time, exposes it as an HTTP stream on the LAN, then issues UPnP/SOAP commands to the Sonos device to play that stream URL. This is the same pattern third-party bridges like AirSonos historically used. It requires the Mac to stay awake.

**The four genuinely uncertain technical bets** the spike must validate:
1. Real-time audio capture from a hidden `WKWebView` playing DRM-protected content — most likely via `ScreenCaptureKit` audio tap on macOS 26+, but unproven in this configuration
2. Encoding/serving that capture as an HTTP stream Sonos S1 will accept (codec, headers, chunked encoding)
3. Driving Sonos S1 via Swift-native UPnP/SOAP discovery + control with no third-party dependencies
4. End-to-end latency low enough that play/pause/skip/scrub feel responsive (target: <2s)

If any of those four fail in a way that can't be designed around, the milestone re-scopes. If all four pass, the milestone becomes a real build phase.

## Constraints

- **Tech stack**: Swift 6.0+ / SwiftUI / macOS 26+ — locked by `Package.swift` and `CLAUDE.md`
- **Dependencies**: No new third-party Swift packages without explicit approval — per `CLAUDE.md`
- **Coding rules**: No `print()` (use `DiagnosticsLogger`), no `DispatchQueue` (Swift Concurrency only), no force unwraps, no `.background(.ultraThinMaterial)` (use `.glassEffect()`), `@MainActor` on `@Observable` classes — per `CLAUDE.md`
- **Test hardware**: Sonos S1 only — narrows protocol surface to legacy UPnP/SOAP
- **Audio source**: DRM-protected WebView audio — rules out direct stream URL handoff (the trick Spotify uses)
- **Privacy / entitlements**: Audio + screen capture usage descriptions already declared in `Info.plist`; tap-based capture may require additional sandbox concessions
- **API parity**: API > WebView always (per `CLAUDE.md`); but for *audio*, WebView is the only path Kaset has

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Spike before scoping the build phase | Four independent technical unknowns (WebView audio capture, Sonos HTTP stream acceptance, Swift-native UPnP/SOAP, latency). Cheaper to discover a blocker in a 1–3 day spike than mid-build. | — Pending (spike) |
| Target Sonos S1 / UPnP first | User's actual gear. Modern Control API would only matter once they upgrade. | — Pending (spike) |
| Mac-stays-awake acceptable for v1 | User confirmed aspirational, not hard requirement. Local relay is the only path that doesn't require Sonos partnership. | — Pending (spike) |
| No third-party UPnP library | Repo policy + small surface area we actually need (SSDP discovery, a handful of SOAP actions). | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-27 after initialization*
