---
phase: 01-spike
plan: 02
subsystem: sonos-discovery
tags: [sonos, ssdp, upnp, multicast, network-framework, bsd-sockets, swift-concurrency, spike-04]

# Dependency graph
requires:
  - phase: 01-spike-01
    provides: SonosService / SonosSpikeError types, sonos dispatcher, detectMacLANIP() helper, runSonosDiscover() placeholder
  - phase: discuss-01
    provides: D-05 (non-sandboxed CLI runs SSDP while waiting for Apple multicast entitlement), D-15 (real S1 hardware on real home Wi-Fi)
  - phase: research-01
    provides: Section 3 (exact M-SEARCH packet bytes, NWConnectionGroup setup shape, BSD fallback shape, FB8461681 contingency), Pitfall 5 (sandboxed terminal)
provides:
  - Working `swift run api-explorer sonos discover [--timeout N] [--bsd] [--verbose]` subcommand with both transports
  - Three-way exit code contract (0 GO / 1 NO-GO / 2 GO-WITH-WORKAROUND) for SPIKE-04 binary verdict
  - Reusable parseSSDPResponse() / fetchRoomName() / DiscoveryCollector actor — Phase 3 (DISC-01) can copy-paste these as starting points for production
  - Auto-fallback heuristic that exercises both transports automatically (no manual rerun needed if NWConnectionGroup happens to fail on user's macOS 26)
affects: [01-06 (sonos spike-all + REPORT.md will quote the user's verified verdict)]

# Tech tracking
tech-stack:
  added:
    - "NWConnectionGroup + NWMulticastGroup (Apple-blessed multicast send/receive for SSDP M-SEARCH)"
    - "BSD socket multicast (Darwin socket/setsockopt/sendto/recvfrom — fallback path for FB8461681)"
    - "XMLParser + private SonosRoomNameParser delegate (room-name extraction from device_description.xml)"
    - "URLSession with 256 KB body cap and 3s timeout (T-02-03 mitigation)"
  patterns:
    - "Actor-wrapped dedup dictionary (DiscoveryCollector) for Swift 6 strict concurrency in NWConnectionGroup receive callback"
    - "Two-transport spike with auto-fallback: try Apple-preferred path first, fall back to BSD on zero-result, surface a third exit code (2) so the eventual production code (DISC-01) knows which to ship"
    - "First-match XML parse abort: SonosRoomNameParser calls parser.abortParsing() once it captures the first <roomName> — saves ~10 KB of wasted XMLParser work"
    - "Defensive SSDP parser: case-insensitive header lookup, ZonePlayer-only ST filter, URLComponents IP/port extraction, no force unwraps on attacker-controlled bytes (T-02-02)"

key-files:
  created: []
  modified:
    - "Sources/APIExplorer/main.swift (+412 lines / -4 lines: replaced runSonosDiscover placeholder with full SSDP M-SEARCH implementation; added DiscoveredSonosDevice struct, DiscoveryCollector actor, parseSSDPResponse, fetchRoomName, SonosRoomNameParser, sendSSDPMSearchViaNWConnectionGroup, sendSSDPMSearchViaBSDSocket)"

key-decisions:
  - "Implemented BOTH transports (NWConnectionGroup + BSD) in this plan rather than the research note's 'only NWConnectionGroup, BSD only if it fails' guidance. Rationale: the auto-fallback heuristic in runSonosDiscover requires both bodies to exist at runtime so a single user run produces a definitive verdict (GO / GO-WITH-WORKAROUND / NO-GO) without forcing a manual rerun. Plan task body explicitly authorized full BSD implementation via step (6); research-md note was only about not-implementing-everything-without-cause."
  - "Used Swift 6 actor (DiscoveryCollector) instead of Mutex<...> for the dedup dict. Both are valid per RESEARCH.md note 'Use Mutex<...> in Swift 6 strict concurrency OR an actor wrapping the dict' — actor is simpler for this case (read-mostly, no per-element atomic semantics needed) and matches the project's broader async/await pattern (CLAUDE.md: 'Swift Concurrency only')."
  - "XMLParser delegate aborts on first roomName match. Sonos device descriptions have one <roomName> at the root device level plus subordinate-device entries on multi-room amps; spec is 'first match wins' for the spike's purposes. parser.abortParsing() saves the rest of the XML walk."
  - "ZonePlayer ST filter is belt-and-braces. The M-SEARCH explicitly targets `urn:schemas-upnp-org:device:ZonePlayer:1` so theoretically only Sonos zones would reply — but on shared LANs other UPnP devices sometimes respond with a different ST despite the targeted M-SEARCH (e.g., printers using ssdp:all-style fan-out). Filtering at parse time is cheap and prevents accidentally treating a printer as a Sonos."
  - "Auto-fallback exits with code 2 (GO-WITH-WORKAROUND) when BSD finds devices that NWConnectionGroup missed. This is the spike's deliverable to Phase 3: the verdict literally tells DISC-01 which transport to ship."

requirements-completed: []

# Metrics
duration: 4min
completed: 2026-04-28
---

# Phase 1 Plan 02: SSDP Discovery for Sonos S1 Summary

**SPIKE-04 implementation: full `swift run api-explorer sonos discover` with both NWConnectionGroup + BSD multicast transports, USN-dedup, room-name lookup, and a three-way exit code contract — code is verified to build/lint/run-end-to-end-without-crash on both paths; live verification against the user's actual S1 is DEFERRED because the worktree's network is the iPhone Personal Hotspot subnet (172.20.10.0/28), not the user's home Wi-Fi where the S1 lives.**

## Performance

- **Duration:** ~4 min (parallel-executor wallclock)
- **Started:** 2026-04-28T20:27:17Z
- **Completed:** 2026-04-28T20:31:54Z
- **Tasks:** 1 of 2 fully executed (Task 2 deferred — see "Checkpoint State" below)
- **Files modified:** 1 (Sources/APIExplorer/main.swift)
- **Lines added:** 412 / removed: 4

## Accomplishments

- **Full SSDP M-SEARCH implementation landed.** Replaced the placeholder body of `runSonosDiscover(args:)` with a complete two-transport implementation per RESEARCH.md Section 3: the exact M-SEARCH packet bytes, three-iteration repetition discipline (1s apart), maximumMessageSize 65535 receive cap (T-02-02), URN-targeted ST filter, USN dedup via a Swift 6 actor.
- **Both transports exist and run cleanly.** `NWConnectionGroup + NWMulticastGroup` is the default; `--bsd` switches to a Darwin BSD socket fallback (`socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)` with `IP_MULTICAST_TTL` / `IP_MULTICAST_LOOP` setsockopt + non-blocking `recvfrom` poll loop). Both paths execute end-to-end without throwing or crashing on the test machine.
- **Auto-fallback heuristic implemented.** When the default NWConnectionGroup transport returns 0 devices, `runSonosDiscover` automatically tries the BSD fallback before declaring NO-GO — and exits 2 (GO-WITH-WORKAROUND) if BSD then finds zones. This means a single user run produces a definitive Phase-3-input verdict; the user does not have to know about FB8461681 or rerun manually.
- **Room-name lookup wired up.** Each discovered device has its `device_description.xml` GET-fetched in parallel via `withTaskGroup`, with a 3s timeout, 256 KB cap (T-02-03), and a custom `SonosRoomNameParser` `XMLParserDelegate` that captures the first `<roomName>` element and aborts the rest of the parse for efficiency.
- **All quality gates green.** `swift build` clean (no warnings), `swiftlint --strict Sources/APIExplorer/main.swift` clean (0 violations), `swiftformat --lint` clean (0/1 files require formatting). No new force unwraps in the diff.

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement SSDP M-SEARCH via NWConnectionGroup with BSD fallback in runSonosDiscover** — `87594d0` (feat)
2. **Task 2: User confirms `sonos discover` finds their actual Sonos S1 zones** — DEFERRED (no commit; checkpoint:human-verify — see "Checkpoint State" below)

## Files Created/Modified

- `Sources/APIExplorer/main.swift` (+412/-4 lines):
  - Added `struct DiscoveredSonosDevice` (USN, IP, port, location, server, roomName) — throwaway spike type
  - Added `actor DiscoveryCollector` for Swift 6 strict-concurrency-safe dedup dict
  - Added `func parseSSDPResponse(_:)` — case-insensitive header parser with ZonePlayer ST filter and URLComponents IP/port extraction
  - Added `private final class SonosRoomNameParser: NSObject, XMLParserDelegate` for first-match `<roomName>` extraction
  - Added `func fetchRoomName(for:) async -> String?` — never-throws-past-this-boundary URLSession GET + XMLParser
  - Added `func sendSSDPMSearchViaNWConnectionGroup(timeout:) async throws -> [DiscoveredSonosDevice]` — Apple-blessed multicast path
  - Added `func sendSSDPMSearchViaBSDSocket(timeout:) async throws -> [DiscoveredSonosDevice]` — FB8461681 fallback path with non-blocking recvfrom poll loop
  - Replaced placeholder `runSonosDiscover(args:)` body with arg parsing (`--timeout`, `--bsd`, `--verbose`/`-v`), transport selection, auto-fallback heuristic, parallel room-name fetch via `withTaskGroup`, verdict printing, and three-way exit (0/1/2)

## Decisions Made

- **Implemented BOTH transports fully in this plan** (rather than the research-md note's 'only implement NWConnectionGroup, add BSD only if it fails'). The plan task body explicitly authorized step (6) "Implement BSD socket fallback ... with the receive loop fully implemented." The auto-fallback heuristic in `runSonosDiscover` requires both bodies present so a single user run produces a definitive Phase-3-input verdict. Implementing BSD eagerly trades ~80 lines of code for not having to ask the user to rerun under different conditions to disambiguate FB8461681.
- **Swift 6 actor over Mutex<...> for dedup.** Both are valid per RESEARCH.md; actor is simpler (no per-element atomic semantics needed; the receive callback only inserts and the snapshot is read once at the end), matches the project's broader async/await pattern, and produces cleaner Swift 6 strict-concurrency-clean code.
- **First-match XML abort for room name.** Sonos device descriptions have one root-level `<roomName>` plus subordinate entries; the spike only needs the first. `parser.abortParsing()` after the first match saves the rest of the parser walk.
- **ZonePlayer ST filter at parse time.** M-SEARCH already targets ZonePlayer, so theoretically only Sonos zones reply — but the ST check costs nothing and forecloses any accidental "treat the printer as a Sonos" failure mode.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking → Format Policy] SwiftFormat normalized `65_535` to `65535`**
- **Found during:** Task 1 (pre-build `swiftformat .` pass)
- **Issue:** The plan's task body and `<verify>` block hard-code the literal `maximumMessageSize: 65_535` (with the underscore separator). Project's `.swiftformat` config has `--decimalgrouping 3,6` which normalizes 4-digit decimal literals to remove the underscore — the formatter rewrote `65_535` → `65535` automatically.
- **Fix:** None applied to the source — the value is exactly equivalent (65,535 bytes max UDP message), the threat-model T-02-02 mitigation is visibly present, and CLAUDE.md mandates `swiftformat .` before completion. The plan's automated `grep 'maximumMessageSize: 65_535'` regex check would fail, but the equivalent `grep 'maximumMessageSize: 65535'` passes. Project formatting policy takes precedence over plan-text literals.
- **Files modified:** `Sources/APIExplorer/main.swift`
- **Verification:** Build clean, lint clean, format clean. Threat-model T-02-02 (UDP packet size cap) intent is fully preserved.
- **Committed in:** `87594d0` (Task 1 commit)

**2. [Rule 1 - Code-flow Improvement] Used `try await Task.sleep` (not `try?`) per plan correction**
- **Found during:** Task 1 (writing the NWConnectionGroup function)
- **Issue:** RESEARCH.md Section 3's reference snippet uses `try? await Task.sleep(...)`. The plan body's step (3) explicitly overrides this: **"Use `try` (not `try?`) for `Task.sleep` and surface cancellation cleanly."** The `try?`-swallow pattern hides Task cancellation, which would mask a user pressing ctrl-C during a 7s discovery wait.
- **Fix:** Both `sendSSDPMSearchViaNWConnectionGroup` and `sendSSDPMSearchViaBSDSocket` use `try await Task.sleep(...)` and propagate cancellation up to `runSonosDiscover`'s catch block, which prints `❌ NO-GO: <CancellationError>` and exits 1.
- **Files modified:** `Sources/APIExplorer/main.swift`
- **Verification:** Code reviewed; build clean.
- **Committed in:** `87594d0`

**Total deviations:** 2 (1 format-policy normalization, 1 explicit cancellation-handling improvement per plan's own correction note).
**Impact on plan:** None on functionality; the `65_535` literal-match acceptance check requires reading the source as `65535` instead but the threat-model intent is preserved.

## Issues Encountered

- **Worktree branch was based on the wrong commit.** Same root cause as Wave 1 plan 01: this worktree's HEAD was created at `1c6db27` instead of `193a289` (the wave-2 startup base). The `<worktree_branch_check>` block detected and corrected via `git reset --hard 193a289`. No data lost.

- **Test environment is iPhone Personal Hotspot, not home Wi-Fi.** `ifconfig en0` shows `inet 172.20.10.4 netmask 0xfffffff0` — that is Apple's Personal Hotspot subnet (`172.20.10.0/28`), not the user's home Wi-Fi where the Sonos S1 lives. Multicast UDP packets sent from a phone-tethered Mac do not reach Sonos hardware on a separate physical home network. Both transports therefore returned 0 devices on this run; this is **expected and correct** given the network topology, not a code bug. The user's prompt-context said "Sonos S1 is powered on and reachable on the same Wi-Fi/LAN as this Mac" — that statement is true for the user's normal environment but not for this worktree-execution moment, where the Mac happens to be tethered. Live verification therefore must happen post-merge from the user's home Wi-Fi.

- **Cannot run `tcpdump` for the M-SEARCH packets-leaving-Mac diagnostic.** `sudo tcpdump` requires interactive password entry; not feasible from a non-interactive parallel-executor agent. The user-facing diagnostic in the NO-GO error message ("try `sudo tcpdump -i any port 1900` while re-running this command") is preserved verbatim for the user's home-Wi-Fi run.

## Checkpoint State

### Task 2: User confirms `sonos discover` finds their actual Sonos S1 zones — DEFERRED

**Type:** `checkpoint:human-verify` (gate=blocking in plan; deferred in parallel-executor mode because (a) the worktree's network is iPhone Personal Hotspot, not the user's home Wi-Fi where the S1 lives, and (b) running unsandboxed `swift run api-explorer sonos discover` against real S1 hardware is by definition a user-only step — Claude cannot teleport the Mac to the right network).

**Why deferred:** The Mac's `en0` interface during this run was `172.20.10.4/28` (Personal Hotspot), which is a separate physical subnet from the user's home Wi-Fi. Multicast traffic does not bridge across this boundary. The ad-hoc live runs against the worktree's hotspot network correctly returned 0 devices on both transports — this proves the code paths execute end-to-end without crashing, but does NOT validate "real S1 is discoverable" since no S1 was on the network. Live verification must happen post-merge once the user is on their home Wi-Fi.

**What is ready for the user:**

1. Make sure your Sonos S1 system is powered on AND your Mac is on the SAME home Wi-Fi network (not a phone hotspot).
   - Sanity check: `ifconfig en0 | grep 'inet '` — IP should be in `192.168.x.x`, `10.x.x.x`, or non-`172.20.10.x` `172.16-31.x.x` ranges, NOT `172.20.10.x`.
2. From a non-sandboxed terminal (Terminal.app or iTerm2 — both unsandboxed by default per CONTEXT.md D-05), from the repo root:
   ```bash
   swift run api-explorer sonos discover --verbose
   ```
3. Expected outcome (one of three):
   - **GO (exit 0):** "✅ GO: discovered N Sonos device(s):" followed by your zones with room names + IPs. NWConnectionGroup works directly on macOS 26 — record this for SPIKE-06 REPORT.md.
   - **GO-WITH-WORKAROUND (exit 2):** "⚠️ NWConnectionGroup returned 0 devices — auto-trying BSD socket fallback..." then "⚠️ BSD socket found N device(s)". Phase 3 DISC-01 should ship the BSD path. Note this for REPORT.md.
   - **NO-GO (exit 1):** "❌ NO-GO: zero devices responded from either transport". Run `sudo tcpdump -i any port 1900` in another terminal then re-run discover to confirm whether M-SEARCH packets even leave the Mac. If they don't leave, Pitfall 5 (sandboxed terminal) applies. If they leave but no responses come back, you're on a multicast-blocked network (VLAN/managed Wi-Fi).

**Resume signal options (paste into the SPIKE-06 REPORT.md `SPIKE-04` section):**

- `GO: NWConnectionGroup found <N> zones: <comma-separated room names>` — ideal outcome; Phase 3 DISC-01 ships NWConnectionGroup.
- `GO: BSD-only found <N> zones: <comma-separated room names>` — auto-fallback fired; Phase 3 DISC-01 ships BSD socket transport (FB8461681 still bites macOS 26).
- `NO-GO: <brief description — tcpdump showed/did not show packets, network setup, etc.>` — opens a debug loop; spike RE-SCOPE candidate per CONTEXT.md D-19.

**Impact of deferral on Phase 1:** None on plans 03-06 (each runs independently against the same hardware). Deferral DOES block the SPIKE-04 verdict in the eventual SPIKE-06 REPORT.md, which is the explicit dependency: the user's run produces the verdict the report quotes.

## User Setup Required

Yes — run the live discover command from the user's home Wi-Fi (not a phone hotspot). See "Checkpoint State / Task 2" above. Approximate runtime: 7 seconds.

## Next Phase Readiness

**Ready for plans 03, 04, 05** — none of them depends on plan 02's runtime verdict; they each consume the user's S1 IP (via `<ip>` arg) and run their own bets. Plan 03 will need the IP from the discover output, but the user can also pass an IP they already know from the official Sonos app.

**Ready for plan 06 (REPORT.md)** *with caveat* — plan 06 needs to quote the verdict from this plan's checkpoint. Either:
- The user runs `sonos discover` post-merge and replies with their verdict before plan 06 runs, OR
- Plan 06 runs with a placeholder verdict and the user fills it in when REPORT.md is finalized.

**Concerns / blockers carried into Phase 1's downstream waves:**
- The live SPIKE-04 verdict is pending the user's home-Wi-Fi run (see Checkpoint State above).
- Multicast entitlement (from Wave 1 plan 01 Task 2) still queued — does not block Phase 1 spike work, but DOES block the Phase 3 sandboxed re-test (D-06).

## Self-Check: PASSED

Verified the following claims before finalizing:

- [x] `Sources/APIExplorer/main.swift` contains `^func sendSSDPMSearchViaNWConnectionGroup` (verified via Grep).
- [x] `Sources/APIExplorer/main.swift` contains `^func sendSSDPMSearchViaBSDSocket` (verified via Grep).
- [x] `Sources/APIExplorer/main.swift` contains `^func parseSSDPResponse` (verified via Grep).
- [x] `Sources/APIExplorer/main.swift` contains `^func fetchRoomName` (verified via Grep).
- [x] `Sources/APIExplorer/main.swift` contains `actor DiscoveryCollector` (verified via Grep).
- [x] `Sources/APIExplorer/main.swift` contains `struct DiscoveredSonosDevice` (verified via Grep).
- [x] Source contains literal `urn:schemas-upnp-org:device:ZonePlayer:1` (verified via Grep, 2 occurrences — one each in NWConnectionGroup and BSD M-SEARCH bodies).
- [x] Source contains literal `NWMulticastGroup` (verified via Grep, 2 occurrences — one in doc comment, one in code).
- [x] Source contains literal `IP_MULTICAST_TTL` (verified via Grep, 1 occurrence — BSD setsockopt call).
- [x] Source contains `maximumMessageSize: 65535` (NOTE: project SwiftFormat normalized `65_535` → `65535`; semantically identical, threat model T-02-02 preserved — see Deviation 1 above).
- [x] Placeholder string `"placeholder; see PLAN 02"` no longer appears in non-comment code (verified via Grep).
- [x] No new force unwraps in the diff (`git diff | grep -E '^\+.*[!]\.|^\+.*[!]\)'` returned empty).
- [x] `swift build` exits 0 with no warnings.
- [x] `swiftlint --strict Sources/APIExplorer/main.swift` exits 0 (0 violations).
- [x] `swiftformat --lint Sources/APIExplorer/main.swift` reports 0/1 files require formatting.
- [x] `swift run api-explorer sonos discover --timeout 7 --verbose` runs end-to-end without crashing (exits 1 NO-GO on hotspot network as expected — this validates the code path; the live S1-discoverable verdict is the deferred Task 2 checkpoint).
- [x] `swift run api-explorer sonos discover --bsd --timeout 4` runs the BSD path end-to-end without crashing (also exits 1 NO-GO on hotspot network, as expected).
- [x] Commit `87594d0` exists in `git log` (Task 1).
- [x] No PII (LAN IPs, USNs, room names) committed in this SUMMARY — only the hotspot IP `172.20.10.4` appears, which is a public-knowledge Apple Personal Hotspot subnet constant, not a user-specific identifier.

---
*Phase: 01-spike*
*Completed: 2026-04-28*
