# Feature Research

**Domain:** Native macOS app sending audio to Sonos S1 speakers via local UPnP/SOAP relay
**Researched:** 2026-04-27
**Confidence:** HIGH for protocol surface (multiple independent UPnP-control libraries agree); MEDIUM for UX comparisons (synthesized from public docs and community accounts, not internal product specs); MEDIUM for latency targets (anchored on AirConnect's documented behavior, not yet measured for Kaset).

## Scope Note

This document covers ONLY the Sonos integration feature surface. Existing Kaset features (browse, queue, EQ, AppleScript, NL commands) are out of scope and documented in `.planning/codebase/`. Where this milestone needs to *integrate with* an existing feature (e.g., the queue, the now-playing model), that integration is treated as an existing capability we route to — not a new feature.

The architectural premise — a Mac-side local HTTP audio relay driven by UPnP/SOAP, with the Mac required to stay awake during playback — is taken as given from `PROJECT.md`. Features are evaluated against that premise. Anything that contradicts it is filed under anti-features.

---

## Reference Models (How Other Products Do This)

Concrete models matter more than abstract feature lists. Each is included only as a *contrast point*; we are not building any of them.

| Product | Architecture | Speaker Picker | Handoff Polish | Why It Works |
|---------|--------------|----------------|----------------|--------------|
| **Spotify Connect on Sonos** | Cloud → Sonos (Spotify is a registered SMAPI music partner). Phone/Mac is *only a remote*; audio never traverses the controller device after handoff. | In-app speaker icon → device list (devices grouped by Sonos zone topology, surfaced via Spotify's backend). | Seamless: "Move to this device" preserves track + position because state lives in Spotify's cloud. | Partnership + cloud architecture. **Not reachable** for an indie YouTube Music client. |
| **Apple Music via AirPlay 2** | macOS audio session → AirPlay 2 receivers. Mac/iPhone is the source. Multi-room mixing happens on the source device. | OS-level picker (Control Center on macOS / Now Playing on iOS) shows AirPlay receivers including AirPlay-capable Sonos. | Good but source-tethered: pause Mac → music stops. | OS-integrated audio routing. **S1 hardware does not speak AirPlay** so this path is closed for the user's gear. |
| **Roon → Sonos** | Roon Core (separate process, often a NAS / dedicated box) streams over UPnP to Sonos. | Roon's own zone picker; Roon understands Sonos stereo pairs as one device and Sonos zone groups as one zone. | Per-zone transport, per-zone volume, room grouping respected. Up to FLAC 24/48. | Local UPnP bridge done correctly. **Closest analog to what Kaset must do.** |
| **Plex for Sonos** | Plex implements Sonos' SMAPI music-service protocol; Sonos pulls directly from the Plex Media Server. | Inside the Sonos app — Kaset would never appear here. | Survives controller leaving (Sonos pulls). | Requires implementing SMAPI **and** being whitelisted by Sonos. **Not reachable.** |
| **AirSonos / AirConnect** | Daemon advertises a fake AirPlay receiver, decodes RTP, re-streams as HTTP MP3 to Sonos via UPnP. | OS AirPlay picker shows the bridged "speaker." | Functional but laggy (8–10s typical). | **Same protocol envelope** Kaset is targeting (UPnP relay), and the most honest reference for what's hard. |

The realistic ceiling for Kaset v1 is "Roon-quality control surface, AirConnect-tier latency budget at first, tightened later." The realistic floor is "anything substantially worse than AirConnect on latency or reliability is a regression for the user."

Sources:
- [Spotify Connect](https://support.spotify.com/us/article/spotify-connect/)
- [AirPlay vs Sonos architecture (Sonos community)](https://en.community.sonos.com/controllers-and-music-services-229131/are-there-any-advantages-of-sonos-multi-room-over-apple-airplay-2-multi-room-6908232)
- [Roon → Sonos help article](https://help.roonlabs.com/portal/en/kb/articles/sonos)
- [Plex for Sonos requirements](https://support.plex.tv/articles/218237558-requirements-for-using-plex-for-sonos/)
- [AirConnect — README and latency discussion](https://github.com/philippe44/AirConnect)

---

## Feature Landscape

### Table Stakes (Users Expect These)

If any of these are missing or visibly broken, the feature feels broken — not "v1." These are the bar set by AirConnect and the Sonos S1 app itself.

| Feature | Why Expected | Complexity (S1/UPnP-only) | Notes |
|---------|--------------|---------------------------|-------|
| **Speaker discovery on the LAN** | "I opened Kaset, why don't I see my Play:1?" | LOW–MEDIUM | SSDP `M-SEARCH` multicast + parse `device.xml` from the discovered device. Sonos historically supports both SSDP and mDNS; current S1 firmware still answers SSDP. Multicast is fragile across VLANs / corporate Wi-Fi — surface a "didn't find anything" empty state with a manual-IP fallback. |
| **Speaker picker UI in Kaset** | Spotify, AirPlay, Sonos app all have this. Cost of omission is "where do I send audio?" being unanswerable. | LOW | Menu in `PlayerBar` (or AirPlay-style popover) listing discovered zones. Show device name (`RoomName`), grouping state, and a current-playing indicator. Group coordinator is the addressable target — surface that, not raw player UUIDs. |
| **Output target: Mac speakers vs. a Sonos zone** | Today Kaset plays through macOS audio; users will want a one-tap toggle. | LOW (UI) / MEDIUM (state machine) | Single source-of-truth for "where audio is going right now." When Sonos is selected, the WebView still produces audio — we either route it locally OR mute the system output and only relay. Decision belongs in spike, but the *picker UX* is unchanged. |
| **Play / pause from Kaset** | Transport controls in `PlayerBar` already exist; users will press them when streaming to Sonos. | LOW | UPnP `AVTransport.Play` / `Pause` on the group coordinator. Round-trip is ~100–300ms on a healthy LAN. Kaset's `PlayerService` issues these in addition to (or instead of) WebView JS commands. |
| **Skip next / previous** | Same expectation as play/pause. | LOW | For Kaset's queue model, "next" = load the next track's audio into the relay and `SetAVTransportURI` again. UPnP `Next` only works inside the Sonos device's *own* queue, which we are not populating directly. |
| **Volume control (per zone)** | The PlayerBar has a volume slider; users will expect it to act on the Sonos. | LOW | `RenderingControl.SetVolume` on the coordinator (single speaker) or `GroupRenderingControl.SetGroupVolume` (group). Use the group variant when the zone is grouped — preserves relative volumes across players. |
| **Mute / unmute** | Standard. | LOW | `SetMute` / `SetGroupMute`. Do **not** simulate mute by setting volume to 0 — that loses the previous level (the official Sonos guidance). |
| **Now-playing metadata on the Sonos app** | When users open the Sonos S1 app, they expect to see the song that's playing — not "HTTP stream from kaset.local". | MEDIUM | Pass DIDL-Lite as `CurrentURIMetaData` on `SetAVTransportURI` (`<dc:title>`, `upnp:artist`, `upnp:album`, `upnp:albumArtURI`). Refresh on every track change. For continuous-stream relay (single long-lived URI), embed metadata in `r:streamContent` or as ID3v2 tags. |
| **Survives normal Wi-Fi flakes (a few seconds)** | If a microwave starts and the music stops permanently, that's a bug. | MEDIUM | Relay HTTP server should hold the connection / re-buffer; on transient `ConnectionLost` events from Sonos, reissue `Play` and resume. Don't tear down the relay on the first failure. |
| **Picker reflects current playback state** | If music is playing on the kitchen Sonos, the picker should make that obvious. | LOW | Subscribe to `AVTransport` GENA events from each known device; reflect `TRANSPORT_STATE` (PLAYING / PAUSED / STOPPED) and current track in the picker. Re-subscribe every ~25 minutes (default subscription expires at 30). |
| **Stop relay when user picks "Mac speakers"** | Otherwise the Sonos keeps playing silence forever. | LOW | `AVTransport.Stop` on the previous coordinator + tear down the HTTP relay session. |
| **Zone identification (which speaker is which)** | "Living Room" vs. "RINCON_5CAAFD..." — only one of those is acceptable in a UI. | LOW | `DeviceProperties.GetZoneAttributes` returns the user-visible room name. Cache and refresh on `ZoneGroupTopology` events. |

Sources for this section:
- [SSDP/mDNS on Sonos (community)](https://en.community.sonos.com/components-and-architectural-228999/local-communication-with-sonos-to-group-between-rooms-6865097)
- [AVTransport service reference (svrooij)](https://sonos.svrooij.io/services/av-transport)
- [RenderingControl + GroupRenderingControl](https://sonos.svrooij.io/services/rendering-control)
- [GENA event subscription (Sonos community)](https://en.community.sonos.com/advanced-setups-229000/upnp-event-subscription-net-c-34484)
- [DIDL-Lite metadata format (svrooij metadata reference)](https://sonos.svrooij.io/metadata)

### Differentiators (Competitive Advantage)

These are where Kaset can land above "yet another UPnP bridge." Each is achievable on S1/UPnP without partnership — but each costs real effort. Recommend picking 2–3 for v1, deferring the rest.

| Feature | Value Proposition | Complexity (S1/UPnP-only) | Notes |
|---------|-------------------|---------------------------|-------|
| **AirPlay-style picker UX** (icon in PlayerBar, popover with zones, instant feedback) | The main reason "Sonos integration" sells: it should *feel* like Sonos is just another output, not a configuration screen. | MEDIUM | Visual parity with macOS's AirPlay Control Center popover. Use `.glassEffect()` (per `CLAUDE.md`). Show grouped zones as a single picker entry with a sub-disclosure for the players inside. |
| **Bidirectional state sync** (volume changes made on the Sonos app appear in Kaset, and vice versa) | Distinguishes "we just send commands" from "we are a real controller." Spotify Connect and the Sonos app both do this. | MEDIUM | Subscribe to `RenderingControl` GENA events for volume; reflect into Kaset's `PlayerService.volume`. Two-way debounce to avoid feedback loops. Required infrastructure (event subscriptions) is also needed for the table-stakes "picker reflects current state" item, so marginal cost is low. |
| **Group-aware playback** (target a Sonos zone group, not just a single speaker) | Users with grouped Living Room + Kitchen want one button, not two streams. Roon and the Sonos app both expose this. | MEDIUM | Send commands to the group coordinator (resolved from `ZoneGroupTopology`). Audio relay URL stays the same — Sonos handles intra-group fan-out. Honest limitation: we *follow* the user's existing Sonos grouping; we don't *create* groups (see anti-features). |
| **Now-playing display on speakers with displays** (Sonos Roam, Move 2 — but **not S1 hardware**) | On modern Sonos with displays, showing track art is delightful. | N/A on S1 | S1-generation hardware (Play:1 / Play:3 / Play:5 Gen 1 / Connect / Connect:Amp) has **no displays**. Defer entirely. The DIDL-Lite metadata still goes to the Sonos app (table-stakes item). |
| **Per-zone EQ override** (use Kaset's existing system EQ but bypassed/different when on Sonos) | Sonos has its own bass/treble per room. Two EQs stacked sound bad. | LOW–MEDIUM | When a Sonos zone is selected, optionally bypass `EqualizerService` (since the audio leaves the Mac before EQ is meaningful for the listener). At minimum, document the interaction. Surfacing a "use Sonos' built-in EQ instead" toggle is one extra checkbox. |
| **Latency awareness in the UI** | If the user pauses and there's a 1–2s gap before the speaker actually pauses, they will press it again. Visible feedback ("…") prevents that. | LOW | Optimistic UI on transport buttons + a subtle "syncing" indicator when waiting on a SOAP response. No new tech, just discipline. |
| **Smart re-bond on Wi-Fi return** | Mac sleeps for a minute, wakes up — the relay URL is still in Sonos' transport but the HTTP server died. Auto-recover. | MEDIUM | On `NWPathMonitor` reachable + `IOPMSleepReason` wake, re-issue `Stop` + new `SetAVTransportURI` + `Play`, restoring position best-effort. |
| **Cross-fade / gapless on Kaset side** | YouTube Music users expect album-style gapless on classical, electronic, etc. | HIGH | Sonos' UPnP doesn't expose gapless reliably for ad-hoc HTTP streams (gapless inside Sonos' queue model is different from gapless across `SetAVTransportURI` calls). Achievable only by serving a single continuous stream and switching tracks server-side without `Stop`/`Set`. Significant complexity. **Defer.** |
| **AppleScript / NL command surface for Sonos** ("send to living room") | Kaset already has both AppleScript and FoundationModels NL commands. Extending them to Sonos is cheap once the picker exists. | LOW (additive) | `tell application "Kaset" to send playback to "Living Room"`. Extends an existing affordance; no new infrastructure. |
| **Last-used-zone memory** | Don't make the user re-pick the speaker every cold start. | LOW | Persist last selected zone UUID + room name; on launch, if discovery finds it, restore as the default output (without auto-playing — that's an anti-feature, see below). |
| **Diagnostics overlay** (latency, last SOAP error, current relay URL) | Power users running this on real networks will hit weird things. Devs supporting them need a button to press. | LOW | Hidden behind a Kaset diagnostics gesture; reuse `DiagnosticsLogger`. |

### Anti-Features (Commonly Requested, Often Problematic)

Each of these is the kind of thing a user will ask for (or that we will be tempted to add). Each is a trap given the Mac-relay + S1 architecture.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **"Sonos keeps playing after Mac sleeps / Kaset quits"** | This is the headline Spotify/AirPlay 2 feature. Users will ask for it. | Architecturally impossible in v1: Kaset is the HTTP audio source. If Kaset dies, the stream dies. The only path that satisfies this is SMAPI partnership (out of scope per `PROJECT.md`). | Be honest in UI: a small "Mac must stay awake" indicator on the picker when a Sonos zone is selected. Re-open if a future spike finds a workable cloud/partner path. |
| **Kaset auto-resumes Sonos playback at app launch** | "I always want music in the kitchen when I open Kaset." | Surprising and can interrupt other Sonos usage (e.g., the user is on a call routed through that speaker, or someone else is using the Sonos app). Spotify learned this the hard way and added "Stop Spotify auto-play" as a documented setting. | Restore the *picker selection* (so the speaker is pre-selected) but require an explicit Play. |
| **Creating Sonos stereo pairs / bonded zones from Kaset** | Sonos' own app does it; "why doesn't yours?" | Bonding/unbonding goes through `DeviceProperties.AddBondedZones` / `CreateStereoPair`. These work via UPnP but they touch persistent system topology — get the `ChannelMapSet` slightly wrong and the user's bonded pair desynchronizes until they re-pair via the Sonos app. Plus it's not what Kaset is for. | Read existing pairs (treat them as a single zone in the picker). Direct users to the Sonos S1 app for changes. Document as a deliberate non-feature. |
| **Creating Sonos zone *groups* from Kaset** | Same logic as stereo pairs — "let me check Living Room + Kitchen and play to both." | Achievable via `SetAVTransportURI` to `x-rincon:RINCON_xxx` (joins one player to another's group), but the failure modes are nasty: orphaned coordinators, audio splitting, user confusion when the Sonos app shows different grouping than Kaset. Roon does this but Roon owns the whole UX. | Respect the user's existing Sonos grouping (read-only). Re-open in v2 if there's clear demand. |
| **Hi-res / 24-bit / FLAC streaming to Sonos** | Audiophile users want lossless. Roon does it. | S1 firmware caps FLAC/ALAC at 16-bit. The audio source is YouTube Music's player — already lossy. Adding a lossless codec on the relay encodes lossy audio into lossless containers, which is busywork. | Use a sane lossy codec (MP3 320 or AAC) for the relay. Document the codec choice. |
| **In-Sonos-app playback control (queue, search, browse)** | "I want my YouTube Music library inside the Sonos app." | This is the SMAPI feature — requires Sonos Music Service partnership + YouTube Music licensing. Out of scope per `PROJECT.md`. | Kaset is the controller; the Sonos app is for Sonos-native services. The boundary is intentional. |
| **Multi-source mixing** ("ducking" Sonos when a Mac notification plays) | Spotify Connect does graceful ducking. | The Mac is no longer the audio source from the Sonos' point of view — it's just an HTTP server. Ducking would require interrupting the relay stream, which causes audible glitches on Sonos. | Don't try. If the user wants Mac notifications audibly, they use Mac speakers. |
| **Scrub through arbitrary positions during a long live stream** | Users will drag the progress slider. | Sonos' `AVTransport.Seek` returns error 701 on content that doesn't support seeking — and a continuous HTTP MP3 stream typically does not. Per-track HTTP serving (one URL per track, with a known duration in `Content-Length` and `r:duration`) is the only path. | Constrain v1 architecture to "one track per `SetAVTransportURI` call" (per-track HTTP responses). Treat continuous-stream-mode scrubbing as a known limitation if we ever go that route. |
| **Discovering / controlling non-Sonos UPnP renderers** | "Could it work with my Yamaha receiver too?" | Each renderer brand has quirks. The whole point of this milestone is "the user's Sonos S1 gear." | Lock the implementation to Sonos manufacturer string for v1. Generalize later only if asked. |
| **"Spotify Connect for YouTube Music"** (Kaset registers itself as a Sonos-visible source) | The dream UX. | Requires SMAPI registration + YouTube Music ToS-compatible licensing. Out of scope per `PROJECT.md`. | Set the user's expectation in the marketing copy: "Kaset controls Sonos; it doesn't appear inside the Sonos app." |
| **Per-track preset volume normalization** | "YouTube Music's loudness varies; can the Sonos volume auto-adjust?" | Requires real-time loudness analysis on the relay path. CPU cost + latency. | Defer indefinitely. Kaset's existing EQ doesn't do this either. |

Sources for anti-features:
- [Spotify auto-play opt-out (community workaround)](https://www.viwizard.com/spotify-music-tips/stop-spotify-from-automatically-playing.html)
- [Sonos AVTransport.Seek error 701 conditions](https://sonos.svrooij.io/services/av-transport)
- [DeviceProperties.AddBondedZones / CreateStereoPair](https://sonos.svrooij.io/services/device-properties)
- [16-bit FLAC cap on S1 (Sonos support)](https://support.sonos.com/en-us/article/supported-audio-formats-for-sonos-music-library)

---

## Feature Dependencies

```
Speaker discovery (SSDP)
    └──required-by──> Speaker picker UI
                          └──required-by──> Per-zone transport / volume
                                                └──required-by──> Bidirectional state sync
                                                                      └──enhances──> Picker reflects current state

Local HTTP audio relay (spike output)
    └──required-by──> SetAVTransportURI with relay URL
                          └──required-by──> Now-playing metadata via DIDL-Lite
                          └──required-by──> Per-track seek (must serve discrete-track responses)

ZoneGroupTopology subscription
    └──required-by──> Group-aware playback
    └──required-by──> Resolving the right coordinator for transport commands
    └──required-by──> Treating stereo pairs as a single picker entry

GENA event subscriptions (AVTransport, RenderingControl)
    └──required-by──> Bidirectional state sync
    └──required-by──> Smart re-bond on Wi-Fi return
    └──enhances──> Picker reflects current state (vs. polling)

Picker selection persistence
    └──conflicts──> "Auto-resume on launch" anti-feature (do NOT auto-play, only restore selection)
```

### Dependency Notes

- **Discovery → picker → transport** is the core spine. Without GENA events, transport still works but feels "fire and forget." With them, it feels like a real controller.
- **`ZoneGroupTopology` is the source of truth for "what is a zone right now."** Stereo pairs and groups both surface here. Trying to derive grouping from any other service is wrong.
- **The HTTP relay sits underneath everything Sonos-related.** It's gated by the spike. None of the features above exist if the spike fails to produce a Sonos-acceptable HTTP audio stream.
- **GENA event subscriptions are 30-minute leases.** Re-subscription is required infrastructure, not a feature; lump it into the discovery service.

---

## MVP Definition

### Launch With (v1)

The minimum that lets the user pick their Sonos and have Kaset play through it without feeling broken.

- [ ] **SSDP-based discovery of Sonos S1 zones on the LAN** — Foundation. Without this, nothing else exists.
- [ ] **Speaker picker in `PlayerBar`** — AirPlay-icon-style popover; lists zones (group coordinators), highlights current selection.
- [ ] **Toggle output between "Mac speakers" and "Sonos zone X"** — Single source-of-truth state in `PlayerService`.
- [ ] **Local HTTP audio relay serving the captured WebView audio** — Spike-validated; one HTTP response per track (not continuous stream) so seek can work later.
- [ ] **`SetAVTransportURI` + `Play` against the selected zone's coordinator** — With minimal DIDL-Lite metadata (`dc:title`, `upnp:artist`) so the Sonos app shows *something* useful.
- [ ] **Play / pause / next / previous from `PlayerBar` while routed to Sonos** — Skip = new `SetAVTransportURI` for the next track.
- [ ] **Per-zone volume + mute** — `RenderingControl` (single speaker) and `GroupRenderingControl` (when grouped).
- [ ] **Honest "Mac must stay awake" indicator on the picker when Sonos is selected** — Pre-empts the inevitable bug report.
- [ ] **Stop relay + Sonos transport when switching back to Mac speakers** — Cleanup; otherwise the speaker plays silence indefinitely.
- [ ] **Last-selected-zone restored on launch (selection only, no auto-play)** — Cheap; explicitly avoids the auto-play anti-feature.
- [ ] **Discovery empty-state with manual-IP fallback** — Multicast fails on hostile networks; provide an escape hatch.

### Add After Validation (v1.x)

Once v1 is in users' hands and the spike's latency and stability assumptions are real-world-tested.

- [ ] **GENA event subscriptions for `AVTransport` + `RenderingControl`** — Trigger: users complain that the Kaset volume slider is out of sync with the Sonos app, or that pausing on the Sonos app doesn't reflect in Kaset.
- [ ] **Group-aware playback** (route to the coordinator of an existing Sonos group) — Trigger: any user with multi-zone S1 setup (likely most of them).
- [ ] **Smart re-bond after brief Wi-Fi loss / Mac wake** — Trigger: first user reports of "music stopped after my Mac slept for 30 seconds."
- [ ] **Album-art metadata in DIDL-Lite (`upnp:albumArtURI`)** — Trigger: existence; users immediately notice album art missing in the Sonos app.
- [ ] **Diagnostics overlay** — Trigger: first hard-to-reproduce bug report.
- [ ] **AppleScript + NL command extensions** — Trigger: existence; cheap to add once the picker model is stable.

### Future Consideration (v2+)

Defer until v1 proves the architecture works at all. Re-evaluate once we have actual usage data.

- [ ] **EQ-on-Sonos handling** — Either bypass `EqualizerService` automatically or document the interaction explicitly.
- [ ] **Gapless across track changes** — Requires server-side stream continuity through track boundaries; significant complexity.
- [ ] **Generalize to non-Sonos UPnP renderers** — Only if multiple users with other gear ask. Each new brand adds quirks.
- [ ] **S2-generation Sonos via the modern Local Control API** — Re-open if user upgrades hardware. The S2 path is meaningfully nicer (cleaner cloud queue model, official support) but only matters once the user has S2 gear.

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost (S1/UPnP-only) | Priority |
|---------|------------|-------------------------------------|----------|
| SSDP discovery + picker | HIGH | LOW | P1 |
| Local HTTP audio relay | HIGH (gating) | HIGH (spike-dependent) | P1 |
| Play/pause/next/prev to Sonos | HIGH | LOW | P1 |
| Per-zone volume / mute | HIGH | LOW | P1 |
| DIDL-Lite metadata (title + artist) | MEDIUM | LOW | P1 |
| "Mac must stay awake" indicator | MEDIUM | LOW | P1 |
| Stop-on-disconnect cleanup | MEDIUM | LOW | P1 |
| GENA event sync (volume, transport) | MEDIUM–HIGH | MEDIUM | P2 |
| Group-aware coordinator routing | HIGH (for grouped users) | MEDIUM | P2 |
| Album-art metadata | MEDIUM | LOW | P2 |
| Smart re-bond on Wi-Fi return | MEDIUM | MEDIUM | P2 |
| AppleScript / NL command extensions | LOW–MEDIUM | LOW | P2 |
| Diagnostics overlay | LOW (devs only) | LOW | P2 |
| Per-zone EQ handling | LOW | LOW–MEDIUM | P3 |
| Gapless across tracks | LOW (most listeners) | HIGH | P3 |
| Non-Sonos UPnP renderer support | LOW | MEDIUM | P3 |
| Sonos S2 modern API | LOW (no S2 hardware) | HIGH | P3 |

**Priority key:** P1 = must-have for v1; P2 = strong v1.x candidates; P3 = defer.

---

## Competitor Feature Analysis

A grounded comparison — how each reference product actually handles each feature, and where Kaset realistically lands.

| Feature | Spotify Connect | AirPlay 2 (Apple Music) | Roon → Sonos | AirConnect | Kaset (proposed v1) |
|---------|-----------------|-------------------------|--------------|------------|----------------------|
| **Discovery** | Spotify cloud lists Connect devices; Sonos appears via Spotify's backend, not LAN scan. | OS-level (mDNS / Bonjour). | Roon Core does its own UPnP/Sonos detection. | SSDP — bridges advertise themselves as AirPlay receivers. | SSDP, Sonos-only filter. |
| **Picker UX** | In-app speaker icon; cloud-rendered list. | OS Control Center / app-level AirPlay button. | Roon's zone view (custom but well-known). | OS AirPlay picker (bridge appears as a regular speaker). | AirPlay-style popover in `PlayerBar`. |
| **Handoff** | Seamless: phone hands cloud session to speaker. Mac/phone optional after. | Source-tethered: phone/Mac stays in the loop. | Source-tethered to Roon Core (which is usually a server, so "always on"). | Source-tethered to the Mac running AirConnect. | Source-tethered to the Mac running Kaset (acknowledged limitation). |
| **Latency** | None perceptible (cloud → speaker direct). | Low (~2s, AirPlay sync). | Low–medium (RAAT-grade). | High (8–10s typical). | Target <2s; spike must validate. |
| **Transport (play/pause/skip)** | Cloud-issued; fast. | OS-mediated; fast. | Per-zone via UPnP; fast. | Translates AirPlay events; sometimes issues redundant Stop/Play. | Direct UPnP `AVTransport` calls on the coordinator. |
| **Volume sync (controller ↔ speaker)** | Two-way (cloud-mediated). | Two-way (OS-mediated). | Two-way (Roon subscribes to events). | One-way (AirPlay → Sonos). | One-way for v1; two-way via GENA events in v1.x. |
| **Group / room management** | Honors Sonos topology; doesn't change it. | Apple Home groups (separate from Sonos zones). | Reads pairs; can group Sonos zones; cannot group Sonos with non-Sonos. | Per-bridge, no grouping. | Read-only: respect user's existing Sonos grouping. Creation deferred. |
| **Now-playing on Sonos app** | Full metadata (Spotify owns the SMAPI registration). | Limited — appears as "AirPlay" with track title. | Full DIDL-Lite metadata. | Title only; no album art on most builds. | Title + artist v1; album art v1.x. |
| **Survives controller leaving** | Yes (cloud is the source). | No. | Yes if Roon Core stays up; Core is usually a separate machine. | No (kills bridge → kills audio). | No (this is the headline anti-feature). |
| **Lossless / hi-res** | Up to lossless on supported tiers. | ALAC up to 24-bit on capable gear. | Up to FLAC 24/48. | MP3 only (typical AirConnect setup). | Lossy (MP3 320 or AAC), capped by YouTube Music source quality. |
| **Stereo-pair / bond awareness** | Treats pair as one device. | Treats pair as one device. | Treats pair as one device. | Treats pair as one device (uses coordinator). | Same — read from `ZoneGroupTopology`. |

The honest summary: Kaset v1 will land roughly between AirConnect (functional bridge, Mac-tethered) and Roon (polished controller with full metadata), but without Roon's "Core stays up forever" advantage. That's an acceptable position given the constraint set.

---

## Honest Limitations of S1 / UPnP-Only

Worth stating bluntly so they're not surprises during build:

1. **No cloud handoff.** The Mac is in the loop for the full session. Period.
2. **Seek requires per-track HTTP responses.** A continuous-stream relay design forecloses scrubbing. Choose accordingly in the spike.
3. **Stereo pairs and zone grouping are read-only from third parties** (in practice — the UPnP actions exist, but using them safely without the Sonos app is treacherous).
4. **Album art needs an HTTP-reachable URL** (Sonos fetches it from the URL we pass). YouTube Music thumbnail URLs work; we just need to pass them through correctly in DIDL-Lite.
5. **Sonos firmware ≥ 6.4.2 requires `x-rincon-mp3radio://` for raw HTTP streams**, not plain `http://`. Trivial protocol-prefix swap, but easy to miss.
6. **GENA subscriptions expire (30-min default).** Re-subscription must be in the discovery service from day one or state sync silently breaks after the first half-hour.
7. **Latency floor on UPnP-relay architectures is real.** AirConnect users live with 8–10s. Beating that to <2s is the spike's hardest target.
8. **Multicast (SSDP) breaks on enterprise / VLAN-segmented networks.** Need a manual-IP fallback in the picker.

---

## Sources

### Reference products and architectural comparisons
- [Spotify Connect support article](https://support.spotify.com/us/article/spotify-connect/) — How handoff works from a user perspective
- [Spotify Connect Basics — Spotify for Developers](https://developer.spotify.com/documentation/commercial-hardware/implementation/guides/connect-basics) — Cloud-mediated control architecture
- [AirPlay vs Sonos architectural difference (Sonos community)](https://en.community.sonos.com/controllers-and-music-services-229131/are-there-any-advantages-of-sonos-multi-room-over-apple-airplay-2-multi-room-6908232) — "Source vs controller" distinction
- [Use AirPlay to stream audio (Apple Support)](https://support.apple.com/en-us/105068) — macOS AirPlay picker reference
- [Roon → Sonos help article](https://help.roonlabs.com/portal/en/kb/articles/sonos) — How a polished UPnP control point handles zones, pairs, FLAC
- [Plex for Sonos requirements](https://support.plex.tv/articles/218237558-requirements-for-using-plex-for-sonos/) — Why this is a different (SMAPI) integration class
- [AirConnect README + latency discussion](https://github.com/philippe44/AirConnect) — Most direct architectural analog; documented latency reality
- [AirConnect latency issue thread](https://github.com/philippe44/AirConnect/issues/15) — Concrete 8–10s gap evidence

### Sonos UPnP / SOAP protocol surface
- [AVTransport service reference (svrooij)](https://sonos.svrooij.io/services/av-transport) — `SetAVTransportURI`, `Play`, `Pause`, `Seek`, error codes
- [RenderingControl + GroupRenderingControl](https://sonos.svrooij.io/services/rendering-control) — Volume / mute / group volume actions
- [DeviceProperties service](https://sonos.svrooij.io/services/device-properties) — `GetZoneAttributes`, `AddBondedZones`, `CreateStereoPair`
- [Metadata reference (svrooij)](https://sonos.svrooij.io/metadata) — DIDL-Lite + `r:streamContent` formats
- [SoCo wiki — Sonos UPnP services and functions](https://github.com/SoCo/SoCo/wiki/Sonos-UPnP-Services-and-Functions) — Comprehensive service list, S1-relevant
- [SoCo data structures (DIDL-Lite handling)](https://docs.python-soco.com/en/latest/api/soco.data_structures.html) — Album-art URI helper patterns
- [node-sonos-http-api README](https://github.com/jishi/node-sonos-http-api) — Reference HTTP-bridge feature surface
- [GENA event subscription on Sonos (community)](https://en.community.sonos.com/advanced-setups-229000/upnp-event-subscription-net-c-34484) — `LastChange` variable, subscription timeout
- [Sonos discovery (SSDP / mDNS)](https://en.community.sonos.com/components-and-architectural-228999/local-communication-with-sonos-to-group-between-rooms-6865097) — Multicast discovery on the LAN
- [Custom radio URL on S1 — `x-rincon-mp3radio://` requirement (community)](https://en.community.sonos.com/controllers-and-music-services-229131/custom-radio-url-completely-broken-sonos-s1-app-legacy-system-6927934)

### Sonos-supported audio formats and S1-specific caps
- [Supported audio formats (Sonos support)](https://support.sonos.com/en-us/article/supported-audio-formats-for-sonos-music-library) — MP3 / AAC / FLAC / ALAC; 16-bit cap on S1
- [Sonos Developer — Supported audio formats](https://developer.sonos.com/build/content-service-add-features/supported-audio-formats/)

### macOS audio capture (relevant to spike, included for context)
- [ScreenCaptureKit overview (Apple)](https://developer.apple.com/documentation/screencapturekit/) — Audio capture is per-app/window
- [Capturing screen content in macOS (Apple)](https://developer.apple.com/documentation/ScreenCaptureKit/capturing-screen-content-in-macos)

### Hardware / S1 generation reference
- [Set up your Sonos Play:5 (Gen 1)](https://support.sonos.com/en/article/set-up-your-sonos-play-5-gen-1) — Confirms Play:5 Gen 1 is S1-only

---

*Feature research for: Sonos S1 audio integration via Mac-side UPnP relay (Kaset)*
*Researched: 2026-04-27*
