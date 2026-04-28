---
phase: 01-spike
plan: 01
subsystem: infra
tags: [sonos, upnp, ssdp, soap, swift-cli, multicast-entitlement, ffmpeg, fixtures]

# Dependency graph
requires:
  - phase: discuss-01
    provides: D-01 (per-bet subcommands), D-03 (no Services/Sonos files; throwaway only), D-04 (entitlement filed day 1), D-15 (real S1 hardware), D-17 (pre-recorded fixtures)
  - phase: research-01
    provides: Section 1 (multicast entitlement body template), Section 5 (HTTP relay test server, fixture specs), Section 2 (SOAP envelope reference), "Verified pattern: SOAP POST helper" code block
provides:
  - Ready-to-paste multicast entitlement body for the Apple Developer portal
  - 30s stereo PCM WAV + AAC-LC ADTS test fixtures (committed; reproducible from synthetic ffmpeg signals)
  - `swift run api-explorer sonos <discover|play|tap-coexist|measure-latency|spike-all>` dispatcher
  - Shared `sendSonosSOAP()` helper (literal-quoted SOAPACTION + body-level fault detection)
  - Shared `detectMacLANIP()` helper (getifaddrs() + RFC-1918 heuristic)
  - `SonosService` / `SonosSpikeError` throwaway types for plans 02–06
affects: [01-02 (sonos discover), 01-03 (sonos play), 01-04 (sonos tap-coexist), 01-05 (sonos measure-latency), 01-06 (sonos spike-all + REPORT.md)]

# Tech tracking
tech-stack:
  added:
    - "Network framework (NWConnectionGroup, NWListener — imported, used by plans 02/03/05)"
    - "Darwin (getifaddrs, getnameinfo for LAN IP detection)"
    - "ffmpeg (one-time fixture generation; not a runtime dep)"
    - "swiftlint 0.63.2 (project tooling, installed via brew)"
    - "swiftformat 0.61.1 (project tooling, installed via brew)"
  patterns:
    - "Per-bet CLI subcommand isolation: case \"sonos\" → switch on filteredArgs[1] → top-level runSonos<Bet> async func"
    - "Throwaway-but-shaped-like-production types: SonosService enum + SonosSpikeError enum mirror the production shape Phase 3 will introduce"
    - "Synthetic-signal fixtures for committed test assets: ffmpeg sine + pink noise (public-domain, deterministic, license-clean) instead of CC0 web samples"

key-files:
  created:
    - ".planning/phases/01-spike/fixtures/MULTICAST-ENTITLEMENT-REQUEST.md"
    - ".planning/phases/01-spike/fixtures/test-stream.wav"
    - ".planning/phases/01-spike/fixtures/test-stream.aac"
    - ".planning/phases/01-spike/fixtures/README.md"
    - ".planning/phases/01-spike/fixtures/.gitkeep"
  modified:
    - "Sources/APIExplorer/main.swift (+206 lines: Network/Darwin imports, Sonos types, SOAP helper, LAN-IP detector, 5 placeholder subcommands, dispatcher case)"

key-decisions:
  - "Synthetic ffmpeg signals (sine + pink noise) for fixtures instead of a CC0 music sample — reproducibility, license clarity, smallest possible chain-of-rights ambiguity for committed git assets"
  - "Task 2 (multicast entitlement submission) recorded as DEFERRED in this worktree — submission requires Apple Developer portal login and cannot be performed by a parallel executor; user must submit post-merge and update SPIKE-06 REPORT.md"
  - "Fixed deprecated String(cString: [CChar]) → String(decoding: [UInt8], as: UTF8.self) in detectMacLANIP() to silence a macOS 26 SDK warning (Rule 1 auto-fix)"

patterns-established:
  - "Per-bet subcommand: each spike bet gets a dedicated runSonosX top-level async func, dispatched via filteredArgs[1] switch — keeps the five bets independent so plans 02–06 can each iterate in isolation"
  - "Fixture-as-synthesized-signal: committed audio test content generated deterministically from ffmpeg's lavfi sources rather than sourced externally, eliminating licensing ambiguity for repo-checked-in assets"

requirements-completed: [SPIKE-01]

# Metrics
duration: 12min
completed: 2026-04-28
---

# Phase 1 Plan 01: Spike Bootstrap Summary

**Day-1 spike unblock: ready-to-paste multicast entitlement body, synthetic-signal WAV+AAC fixtures, and `api-explorer sonos` dispatcher with five placeholder subcommands + shared SOAP/LAN-IP helpers for plans 02–06.**

## Performance

- **Duration:** ~12 min (parallel-executor wallclock)
- **Started:** 2026-04-28T19:48:00Z
- **Completed:** 2026-04-28T20:01:07Z
- **Tasks:** 2 of 3 fully executed (Task 2 deferred — see below)
- **Files modified:** 6 (5 created, 1 modified)

## Accomplishments

- **Calendar-critical entitlement body drafted.** `.planning/phases/01-spike/fixtures/MULTICAST-ENTITLEMENT-REQUEST.md` is ready to paste into <https://developer.apple.com/contact/request/networking-multicast> with no further editing required (PII-clean per T-01-01).
- **Test fixtures committed.** `test-stream.wav` (5.05 MB / `RIFF WAVE PCM 16-bit stereo 44.1 kHz`) and `test-stream.aac` (713 KB / `MPEG ADTS AAC LC 44.1 kHz stereo`) are checked in and reproducible from `fixtures/README.md`'s deterministic ffmpeg recipe.
- **Spike harness scaffold landed.** `swift run api-explorer sonos` now dispatches to five placeholder subcommands (`discover`, `play`, `tap-coexist`, `measure-latency`, `spike-all`); each prints its `SPIKE-NN` marker and exits 0. Plans 02–06 only need to replace one placeholder body each — no further imports, types, or dispatcher wiring required.
- **Shared helpers in place.** `sendSonosSOAP()` (literal-quoted `SOAPACTION` + body-level SOAP-fault detection per RESEARCH.md PITFALLS Pitfall 1) and `detectMacLANIP()` (getifaddrs + RFC-1918 heuristic) are reusable across plans 03 and 05.
- **All quality gates green.** `swift build` clean (no warnings), `swiftlint --strict Sources/APIExplorer/main.swift` clean (0 violations), `swiftformat --lint` clean (0/1 files require formatting).

## Task Commits

Each task was committed atomically:

1. **Task 1: Draft entitlement request + generate audio fixtures** — `170ab2c` (docs)
2. **Task 2: User submits multicast entitlement request to Apple** — DEFERRED (no commit; checkpoint:human-action — see "Checkpoint State" below)
3. **Task 3: Add `sonos` subcommand dispatcher + shared helpers to api-explorer** — `52fc8c9` (feat)

## Files Created/Modified

- `.planning/phases/01-spike/fixtures/MULTICAST-ENTITLEMENT-REQUEST.md` — Ready-to-paste body for Apple's multicast entitlement request form. Contains the four required key strings (`com.apple.developer.networking.multicast`, `com.sertacozercan.Kaset`, `239.255.255.250:1900`, `ssdp:discover`). PII-clean.
- `.planning/phases/01-spike/fixtures/test-stream.wav` — 30s stereo 16-bit PCM 44.1 kHz, 5,292,078 bytes. SPIKE-03 WAV-probe content.
- `.planning/phases/01-spike/fixtures/test-stream.aac` — 30s stereo AAC-LC ADTS 192 kbps, 730,006 bytes. SPIKE-03 AAC-probe content.
- `.planning/phases/01-spike/fixtures/README.md` — Documents synthetic ffmpeg signal source, deterministic regeneration commands, license/PII guarantees.
- `.planning/phases/01-spike/fixtures/.gitkeep` — Empty file to anchor the fixtures dir in git for future-proofing (per plan's `files_modified` list).
- `Sources/APIExplorer/main.swift` — +206 lines (no deletions): added `import Darwin` and `import Network`; added `// MARK: - SonosService` / `SonosSpikeError` enums; added `// MARK: - Sonos Spike Helpers` (`sendSonosSOAP`, `detectMacLANIP`); added five placeholder subcommands; added `case "sonos":` to `runMain()`'s switch.

## Decisions Made

- **Synthetic signals for fixtures, not CC0 music.** The plan suggested pulling a public-domain music sample from Free Music Archive or archive.org. Instead, the fixtures are generated deterministically from ffmpeg's built-in `sine` (440 Hz with `beep_factor=4` accent) + `anoisesrc=color=pink` filters. Rationale: (a) reproducibility — anyone with ffmpeg can regenerate bit-identical files without hunting for the original URL, (b) license clarity — synthetic ffmpeg output has no plausible chain-of-rights ambiguity, (c) the spike's purpose is to validate Sonos S1 *acceptance* of the encoded bytes, not fidelity to specific music, so a varied dynamic + spectral signal is sufficient. Documented in `fixtures/README.md` "Why synthetic, not music?" section. If a future spike iteration needs richer musical content, the file can be swapped without touching code.
- **Task 2 (entitlement submission) deferred to post-merge.** This is a `checkpoint:human-action` task that requires Apple Developer portal login. Parallel-executor agents in worktrees cannot complete it. Surfaced loudly in the "Checkpoint State" section below so the orchestrator/user can act on it after merge. Per CONTEXT.md D-05, the unsandboxed CLI spike work proceeds without the entitlement, so deferral does not block plans 02–06; it only delays the SPIKE-04 sandboxed re-test (which lands in Phase 3).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Replaced deprecated `String(cString: [CChar])` in `detectMacLANIP()`**
- **Found during:** Task 3 (build after first add)
- **Issue:** The plan's reference snippet for `detectMacLANIP()` uses `String(cString: hostBuf)` where `hostBuf` is a `[CChar]` array. macOS 26 SDK marks this overload deprecated with the message "Use `String(decoding: array, as: UTF8.self)` instead, after truncating the null termination." This produced a `swift build` warning that violated the plan's "no new warnings" acceptance criterion.
- **Fix:** Truncate `hostBuf` at the first NUL byte, map the prefix to `[UInt8]`, then `String(decoding: bytes, as: UTF8.self)`. Note: the same call on `current.pointee.ifa_name` (a C `UnsafePointer<CChar>`, not a Swift array) is *not* deprecated and was left unchanged.
- **Files modified:** `Sources/APIExplorer/main.swift` (one block in `detectMacLANIP()`)
- **Verification:** `swift build` clean (no warnings); both lint passes still green; `swift run api-explorer sonos discover` still prints the placeholder marker correctly (no runtime behavior change because the IP-detection path is currently unused).
- **Committed in:** `52fc8c9` (Task 3 commit)

**2. [Rule 3 - Blocking] Installed `swiftlint` and `swiftformat` via brew**
- **Found during:** Pre-Task-1 environment check
- **Issue:** Neither `swiftlint` nor `swiftformat` was installed on this machine, but the plan's verification block depends on them and the project's `CLAUDE.md` mandates `swiftlint --strict && swiftformat .` as the pre-commit workflow.
- **Fix:** `brew install swiftlint swiftformat` (these are project tooling, not Swift Package Manager dependencies — the no-third-party-frameworks rule does not apply). Versions: swiftlint 0.63.2, swiftformat 0.61.1.
- **Files modified:** None in the repo — this was a host-environment fix.
- **Verification:** `swiftlint --strict Sources/APIExplorer/main.swift` exits 0; `swiftformat --lint Sources/APIExplorer/main.swift` exits 0.
- **Committed in:** N/A (host-environment change, not a code change).

**3. [Format-pass cleanup] SwiftFormat reorganized the new MARK comments and pruned redundant `return` keywords**
- **Found during:** Task 3 (running `swiftformat .`)
- **Issue:** SwiftFormat split my single `// MARK: - Sonos Spike Types` block into per-type marks (`// MARK: - SonosService`, `// MARK: - SonosSpikeError`) and removed the explicit `return` keywords from the single-expression switch cases in `SonosSpikeError.description` (per `--implicitreturn`).
- **Fix:** None needed — these are project-policy-driven reformats. Re-built after the format pass; clean.
- **Files modified:** `Sources/APIExplorer/main.swift`
- **Verification:** `swift build` clean; `swiftformat --lint` reports `0/1 files require formatting`.
- **Committed in:** `52fc8c9` (Task 3 commit, post-format).

---

**Total deviations:** 3 (1 deprecation auto-fix, 1 blocking environment fix, 1 format-pass cleanup)
**Impact on plan:** All deviations were necessary for the acceptance criteria to pass cleanly. No scope creep; no functionality added beyond what the plan specified.

## Issues Encountered

- **Worktree branch was based on the wrong commit.** This worktree was created with HEAD at `1c6db27` (an older "Add Ko-fi username" commit) instead of the orchestrator's expected base `30c2a3b` (the planning state). The startup `<worktree_branch_check>` block detected the mismatch and ran `git reset --hard 30c2a3b658ca5f4dbc873d6d38e6403ef0c99517` to correct it. After reset, `.planning/` and the rest of the orchestrator artifacts were available as expected. No data was lost (fresh worktree, no user changes).

## Checkpoint State

### Task 2: Multicast entitlement submission — DEFERRED

**Type:** `checkpoint:human-action` (gate=blocking in plan; treated as deferred in parallel-executor mode)

**Why deferred:** Apple's entitlement request form requires interactive Apple Developer portal login. A parallel executor running in a git worktree cannot perform the submission. Per the `<parallel_execution>` instructions in this agent's prompt, structured checkpoint state is recorded here for the orchestrator/user to act on post-merge.

**What is ready for the user:**

1. Open `.planning/phases/01-spike/fixtures/MULTICAST-ENTITLEMENT-REQUEST.md` in any editor.
2. Visit <https://developer.apple.com/contact/request/networking-multicast> and log in with the Apple Developer account on the team that owns `com.sertacozercan.Kaset`.
3. Copy the use case description body from the markdown file into the form's free-text field.
4. Fill in the App Store URL field — either paste the App Store listing URL, or use the no-App-Store workaround documented in the markdown file (paste the project landing page or Sparkle appcast URL and add a one-line note about external distribution).
5. Submit.

**Resume signal options (paste into the SPIKE-06 REPORT.md `Multicast entitlement status` field):**

- `submitted YYYY-MM-DD` — the date the form was sent. Apple's email confirmation arrives within minutes; full approval typically takes 3–5 business days (worst case 3–10 per Apple Developer Forums thread 663271).
- `deferred` — explicit deferral; delays the SPIKE-04 sandboxed re-test (D-06) by the same number of days but does NOT block any other spike work because per CONTEXT.md D-05 the spike CLI runs unsandboxed.

**Impact of deferral on Phase 1:** None. Plans 02–06 all run via the unsandboxed `swift run api-explorer` CLI, which inherits the terminal's TCC grants and is not subject to the App Sandbox per CONTEXT.md D-05. The entitlement-pending status only blocks Phase 3 (DISC-01) where the same SSDP code must work inside the sandboxed `Kaset.app`.

## User Setup Required

Yes — submit the multicast entitlement request to Apple. See "Checkpoint State / Task 2: Multicast entitlement submission — DEFERRED" above for the exact steps and the file to copy.

The plan's frontmatter records this under `user_setup`:

- **service:** apple-developer-portal
- **why:** File the multicast entitlement request day 1 (3–5 business day SLA per CONTEXT.md D-04)
- **dashboard_config:** Submit multicast entitlement request via <https://developer.apple.com/contact/request/networking-multicast>

## Next Phase Readiness

**Ready for plans 02–06.** Each downstream plan can replace exactly one placeholder body in `Sources/APIExplorer/main.swift`:

- Plan 02 → fill `runSonosDiscover(args:)` with SSDP M-SEARCH (uses `import Network` already in place).
- Plan 03 → fill `runSonosPlay(args:)` with NWListener + `sendSonosSOAP()` + `detectMacLANIP()`.
- Plan 04 → fill `runSonosTapCoexist(args:)` with the dual-consumer fan-out test.
- Plan 05 → fill `runSonosMeasureLatency(args:)` using `sendSonosSOAP()` + stopwatch UI.
- Plan 06 → fill `runSonosSpikeAll(args:)` to chain the previous four.

No further imports, type definitions, or dispatcher wiring are required by any of those plans.

**Concerns / blockers carried into Phase 1's downstream waves:**

- Multicast entitlement submission is queued for the user (see Checkpoint State above). Does not block plans 02–06 in this phase.
- Plans 03/04/05 require the user's actual Sonos S1 hardware on the user's actual home Wi-Fi (CONTEXT.md D-15). This is confirmed present per the phase's Environment Availability table.

## Self-Check: PASSED

Verified the following claims before finalizing:

- [x] `.planning/phases/01-spike/fixtures/MULTICAST-ENTITLEMENT-REQUEST.md` exists and contains all four required key strings.
- [x] `.planning/phases/01-spike/fixtures/test-stream.wav` exists, 5,292,078 bytes (>1 MB sanity check).
- [x] `.planning/phases/01-spike/fixtures/test-stream.aac` exists, 730,006 bytes (>100 KB sanity check).
- [x] `.planning/phases/01-spike/fixtures/README.md` exists.
- [x] `.planning/phases/01-spike/fixtures/.gitkeep` exists.
- [x] `Sources/APIExplorer/main.swift` contains 5 `^func runSonos…` definitions (verified via `grep -c`).
- [x] `Sources/APIExplorer/main.swift` contains `^func sendSonosSOAP` (verified).
- [x] `Sources/APIExplorer/main.swift` contains `^func detectMacLANIP` (verified).
- [x] `swift build` exits 0 with no warnings.
- [x] `swiftlint --strict Sources/APIExplorer/main.swift` exits 0 (0 violations).
- [x] `swiftformat --lint Sources/APIExplorer/main.swift` reports 0/1 files require formatting.
- [x] All five `swift run api-explorer sonos <subcmd>` invocations print the expected `SPIKE-NN` marker.
- [x] PII grep on the entitlement request returns no matches for emails, Team IDs, RINCON USNs, or RFC-1918 IPs.
- [x] Commit `170ab2c` exists in `git log` (Task 1).
- [x] Commit `52fc8c9` exists in `git log` (Task 3).

---
*Phase: 01-spike*
*Completed: 2026-04-28*
