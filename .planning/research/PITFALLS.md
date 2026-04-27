# Pitfalls Research

**Domain:** Mac-side audio relay to Sonos S1 (UPnP/SOAP control + local HTTP audio server) for a sandboxed macOS 26 SwiftUI app whose audio source is a hidden WKWebView playing DRM-protected YouTube Music
**Researched:** 2026-04-27
**Confidence:** MEDIUM-HIGH (HIGH on Sonos protocol behavior, codec acceptance, and AirConnect/swyh-rs prior art; MEDIUM on the specific WKWebView+ScreenCaptureKit DRM interaction because Apple has never publicly confirmed the exact policy boundary)

---

## How to read this document

Every pitfall has a **Severity** (BLOCKER / HIGH / MEDIUM / LOW), a **Phase** (spike / build / polish), a **Falsification test** the spike can run to disprove the assumption, and **Warning signs** that mean "this path is dead, stop digging."

The spike's job is to convert BLOCKER/HIGH pitfalls from *possibilities* into *known-resolved-or-fatal*. A spike that reports "we built a thing and it played" without naming which of these pitfalls it confirmed-or-refuted is not a useful spike.

---

## Critical Pitfalls

### Pitfall 1: ScreenCaptureKit silently drops DRM-tagged WKWebView audio (the project-killer)

**Severity:** BLOCKER
**Phase:** spike (this is uncertainty #1 — must validate or kill in the first day)

**What goes wrong:**
The spike wires up `SCStream` with audio capture against a window filter that targets the host app (or a per-process filter against Kaset's PID). The stream starts, callbacks fire, but the audio buffers contain silence whenever the WKWebView is decoding YouTube Music's DRM-protected audio (Widevine via EME). Non-DRM tabs/windows in the same process may capture fine, masking the issue during smoke tests.

**Why it happens:**
Apple's protected-media path routes EME-decrypted samples through hardware DRM contexts that are deliberately excluded from the screen-capture compositing layer. This is the same mechanism that makes screenshots of Netflix/Apple TV+ come out black. The exclusion applies to **video frames** authoritatively; the policy on **EME audio** is less publicly documented but every prior-art project that captures DRM-streamed audio works around it via system-wide loopback drivers (BlackHole, Loopback) rather than per-process screen capture, which is suggestive. WKWebView specifically lacks Widevine VMP (Verified Media Path) support — meaning it falls back to whichever Widevine path Safari/WebKit can offer, which may further constrain what's exposed to capture APIs.

**Falsification test (do this on day 1 of the spike):**
1. Build a 50-line `SCStream` consumer that writes captured PCM to a `.caf` file for 30 seconds.
2. Test 1: capture while the existing Kaset WebView is playing a YouTube Music track. Verify peak amplitude > -60 dBFS.
3. Test 2: capture while the WebView is playing a YouTube *non-Music* video (regular YouTube, no DRM). Compare amplitudes.
4. Test 3: capture while a separate app (Music.app or Safari on a podcast) is the audio source.

If Test 1 yields silence (or near-silence noise floor) while Tests 2/3 yield real signal, **the per-process ScreenCaptureKit path is dead** and the milestone must pivot to: (a) Core Audio process-tap (`CATapDescription`, macOS 14.2+), (b) a virtual loopback aggregate device the user installs, or (c) abandon the local-relay architecture entirely.

**Warning signs:**
- `SCStreamOutput` callbacks deliver `CMSampleBuffer`s of valid duration but the audio data is all zeros or very low noise floor
- Console.app shows `kAudioFormatProtectedContent` or similar DRM-related entries when the WebView starts playback
- AVAudioPCMBuffer peak measurements stay below -80 dBFS during what should be loud passages

**Recovery path if confirmed:**
Move directly to Core Audio process-tap on Kaset's own PID (the `EqualizerService` already uses this API on macOS 14.2+, so the team has prior art in the codebase). Process-taps capture from the Audio HAL *after* DRM decryption but *before* device output — same point Loopback/BlackHole intercept. This is a more promising path than ScreenCaptureKit for this specific use case anyway.

---

### Pitfall 2: Process-tap conflicts with the existing EqualizerService

**Severity:** HIGH
**Phase:** spike (must be characterized before the build phase commits to either approach)

**What goes wrong:**
Kaset already runs a Core Audio process tap inside `EqualizerService` (per `.planning/codebase/ARCHITECTURE.md` line 22 and `CONCERNS.md` line 228). Adding a second tap on the same source — Kaset's own audio output — produces one of: (a) one tap getting silence while the other works, (b) sample-rate or format mismatches between taps, (c) the aggregate device created by one tap making the other's `AudioObjectGetPropertyData` calls fail intermittently, (d) ordering ambiguity (does the Sonos relay get pre-EQ or post-EQ audio? — both answers are wrong for some user expectation).

**Why it happens:**
Process taps and aggregate devices are global Core Audio constructs. The HAL doesn't fan-out per consumer cleanly when two consumers want the same source PID. Sample-code-level examples of two simultaneous process-taps on the same process are essentially nonexistent in public documentation.

**Falsification test:**
Spike must explicitly test "EQ enabled + Sonos relay enabled simultaneously." If they cannot coexist, decide *now* whether the Sonos path **shares** EqualizerService's existing tap (refactor EqualizerService into a fan-out producer) or **replaces** it when Sonos is the active output (mutex). Don't defer this to build phase.

**Warning signs:**
- Audio drops to silence in either the local speakers or the Sonos when both EQ and relay are on
- `AudioDeviceStart` returns OSStatus `1852797029` ("nope") intermittently
- Sample-rate conversion artifacts (chipmunk voices, robotic stuttering) when both are active

**Prevention strategy:**
Spike deliverable: an architectural decision — "EqualizerService becomes the single tap owner and exposes a publish-subscribe AudioBufferList stream; Sonos relay is one subscriber" OR "Sonos relay disables EqualizerService while active." Pick one, document in an ADR (`docs/adr/`).

---

### Pitfall 3: Sonos rejects the stream with UPnP error 714 ("Illegal MIME-Type")

**Severity:** HIGH
**Phase:** spike (uncertainty #2)

**What goes wrong:**
Spike successfully captures audio, encodes it, serves it over HTTP. `SetAVTransportURI` returns `200 OK`. Then `Play` returns or events with **UPnP error 714: Illegal MIME-Type**, or simply nothing happens. Sonos refuses to fetch or play the stream.

**Why it happens:**
Sonos S1 is unforgiving about Content-Type. Confirmed-working MIME types for direct HTTP streaming on S1: `audio/mpeg` (MP3), `audio/aac` or `audio/mp4` (AAC). FLAC over HTTP UPnP works on newer firmware but is documented as historically broken on older S1 software (per swyh-rs README). Anything not in the supported list, or with parameters Sonos doesn't recognize (e.g., `audio/mpeg; codecs="mp3"`), can trigger 714. WAV (`audio/wav` or `audio/x-wav`) works for some Sonos configs but is documented as "may stutter" on Sonos in swyh-rs's notes.

**Additionally:** Sonos parses the URL extension *and* the Content-Type. Mismatch (e.g., URL ending `.flac` served as `audio/wav`) is a fast 714.

**Falsification test:**
Hardcode a static, known-good MP3 file behind the spike's HTTP server first (before involving live capture). Verify Sonos plays it. *Then* swap to live-encoded MP3 from the capture pipeline. If the static file works and the live pipeline doesn't, the issue is in the encoder/headers, not protocol.

**Warning signs:**
- SOAP response body contains `<errorCode>714</errorCode>`
- Sonos transport state cycles `STOPPED → TRANSITIONING → STOPPED` without ever reaching `PLAYING`
- The Sonos device makes the HTTP GET request, reads a few hundred bytes, then closes the connection

**Prevention strategy:**
- Default to MP3 CBR 320 kbps with `Content-Type: audio/mpeg` and URL ending `.mp3`. This is the safest path for S1.
- For live continuous streams (no known length), use **the `x-rincon-mp3radio://` scheme** instead of `http://` in `SetAVTransportURI` — this tells Sonos to treat the URL as a Shoutcast-style live stream and adjusts buffering accordingly. AirConnect uses this trick.
- Set `Content-Length` only if the stream length is known and finite. For live capture it isn't, so omit it and rely on `Connection: close` or chunked encoding (see Pitfall 4).
- If MP3 latency is unacceptable, only then explore AAC-LC in `audio/mp4` or raw FLAC. Do not start with FLAC.

---

### Pitfall 4: Chunked transfer encoding breaks Sonos MP3 streaming

**Severity:** HIGH
**Phase:** spike

**What goes wrong:**
Spike's HTTP server uses `Transfer-Encoding: chunked` (which is the obvious choice for an unknown-length live stream). Sonos either fails to start, plays for a few seconds and stops, or never sends ICY metadata requests. Logs show Sonos receiving the chunked frames but acting as if the stream ended.

**Why it happens:**
Sonos's HTTP client is built around the radio-streaming model: it expects either (a) a known `Content-Length` for files, or (b) a continuous, **non-chunked** byte stream for radio (matching Shoutcast/Icecast conventions). Icecast itself doesn't support chunked encoding precisely because the Sonos/Squeezebox/etc. ecosystem doesn't either. The Sonos community thread on chunked-MP3 confirms this pattern: Sonos works best with HTTP/1.0-style `Connection: close` for indefinite streams, not HTTP/1.1 chunked.

**Falsification test:**
Run two spike HTTP server modes:
1. `Content-Length: <huge>` and serve until Sonos disconnects
2. `Transfer-Encoding: chunked`
3. HTTP/1.0, no `Content-Length`, `Connection: close`

Mode 3 is what AirConnect / SWYH / swyh-rs converged on. If the spike validates this, lock it in.

**Warning signs:**
- Sonos plays exactly one buffer's worth of audio (~10 seconds) then stops
- Sonos opens the HTTP connection but never sends `Icy-MetaData: 1` request header
- HTTP server logs show client closing the connection cleanly mid-stream

**Prevention strategy:**
Build the spike's HTTP server as **HTTP/1.0 + `Connection: close` + no `Content-Length`** for live streams. Use the `x-rincon-mp3radio://` URI scheme so Sonos treats it as a live stream (longer pre-buffer, no seeking expected). This is well-trodden ground; don't reinvent it.

---

### Pitfall 5: Sonos attempts byte-range requests for "scrub," gets confused

**Severity:** MEDIUM
**Phase:** build (only matters once basic playback works)

**What goes wrong:**
User scrubs the timeline in Kaset. Naive implementation tells Sonos to seek via `AVTransport::Seek`. Sonos issues an HTTP `Range:` request against the relay URL, expecting a seekable file. The relay is a live capture — there are no past samples to serve. Sonos either returns to position 0, errors out, or hangs.

**Why it happens:**
Sonos's seek behavior assumes a finite, seekable source (file or HLS playlist). Live HTTP streams are not seekable by design.

**Prevention strategy:**
Scrubbing in Kaset must be **handled in the WebView** (tell YouTube Music's player to seek; the new audio just flows through the capture pipeline as if it were continuous playback), then potentially issue a brief stop/start of the Sonos stream URL (with a tiny URL-cache-busting query parameter so Sonos refetches rather than resuming from its buffer). Do NOT rely on Sonos's `Seek` action against the live URL.

**Warning signs:**
- HTTP server logs show `Range: bytes=N-` requests coming back from Sonos
- After a scrub, Sonos plays from the wrong position or stops

**Phase to address:** Document this in spike's findings; implement workaround in build phase.

---

### Pitfall 6: SSDP discovery silently does nothing because the multicast entitlement is missing

**Severity:** HIGH
**Phase:** spike (uncertainty #3)

**What goes wrong:**
Spike sends SSDP M-SEARCH multicast packets to `239.255.255.250:1900`. No replies arrive. No errors are thrown. The code looks correct. Sonos devices are visibly responding to the official Sonos S1 app on the same machine.

**Why it happens:**
On macOS 11+ and iOS 14+, multicast networking requires the `com.apple.developer.networking.multicast` entitlement, which is **gated by Apple — you must request it from Apple via a dev support form**. Without it, multicast send/receive silently fails (no error, just no packets). This is the single most common SSDP-on-Apple-platforms gotcha and burns multiple weeks of debugging time across the developer forums.

Additionally, even with the entitlement: `NWConnection` is not multicast-capable; you must use `NWConnectionGroup` with a multicast group descriptor, or fall back to BSD sockets. Mixing IPv6 SSDP (`ff02::c`) with IPv4 SSDP (`239.255.255.250`) on the wrong interface index is another silent-failure mode.

**Falsification test:**
- Day-1 spike test: confirm that Apple's `com.apple.developer.networking.multicast` entitlement has been requested and granted for Kaset's bundle ID. **This has a multi-day-to-weeks turnaround at Apple.** If not requested, request it the moment the spike starts so it isn't a hard dependency at end of spike.
- Day-1 spike test: build a tiny `tcpdump`/Wireshark loop that confirms M-SEARCH packets are actually leaving the Mac. Compare with packets sent by SSDP-Browser (open source: tempelmann/SSDP-Browser) running from the same Mac.

**Warning signs:**
- Code runs cleanly, no errors, but `NWConnectionGroup`'s receive handler never fires
- Wireshark/`tcpdump -i any port 1900` shows no outgoing packets from Kaset
- Discovery works in a non-sandboxed CLI tool (`api-explorer`-style) but fails inside the sandboxed app

**Prevention strategy:**
1. Request the multicast entitlement *immediately* at spike start (don't wait for the spike to "need" it).
2. Use `NWConnectionGroup` with explicit interface binding (Wi-Fi vs Ethernet — pick the interface that has the LAN, not the one with the VPN).
3. Implement IPv4 SSDP first; IPv6 SSDP is a polish-phase concern.
4. If `NWConnectionGroup` fights you, fall back to `Network.framework`'s lower-level paths or BSD sockets — Apple's own documentation warns NWConnection isn't built for multicast.

---

### Pitfall 7: UPnP eventing requires an inbound HTTP server reachable from the Sonos device

**Severity:** HIGH
**Phase:** spike (must be designed-in, not bolted-on)

**What goes wrong:**
Spike implements `SUBSCRIBE` to AVTransport state changes and provides a callback URL. The Sonos returns a SID happily. Then no NOTIFY callbacks ever arrive. Kaset can't tell when the user pressed "pause" on a Sonos remote, when a track ends naturally on Sonos's side, or when another controller stole the speaker.

**Why it happens:**
GENA eventing requires the control point (Kaset) to expose its own inbound HTTP listener that the device can POST NOTIFY messages to. The callback URL given in the SUBSCRIBE header must be:
1. Reachable from the Sonos device (correct interface, no NAT in between)
2. Not blocked by macOS application firewall ("Do you want to allow incoming connections?" prompt the user must accept)
3. Backed by an `com.apple.security.network.server` entitlement under App Sandbox (the audio relay HTTP server already needs this — same entitlement)
4. Bound to the *right* IP — `127.0.0.1` won't work because Sonos can't reach it

Subscriptions also expire (commonly 1800 seconds default) and must be renewed *before* expiry by re-SUBSCRIBE'ing with the SID. If renewal fails (network blip, Sonos reboot, SID dropped on Sonos side), code must re-SUBSCRIBE from scratch.

**Falsification test:**
Spike must NOTIFY-test, not just SUBSCRIBE-test. Trigger a state change from a different controller (Sonos S1 app on phone) and confirm Kaset receives the NOTIFY.

**Warning signs:**
- SUBSCRIBE returns 200 with SID but NOTIFY callbacks never fire
- macOS firewall prompts every Kaset launch ("Do you want to allow Kaset to accept incoming network connections?")
- The first NOTIFY arrives (UPnP guarantees an initial-state NOTIFY on subscription), then nothing — likely subscription expired silently
- Behavior diverges between Wi-Fi and Ethernet (different default routes / interface binding)

**Prevention strategy:**
- **Single inbound HTTP server**: serve both audio streams AND GENA NOTIFY callbacks from one listener (one port, two URL paths). Saves entitlement complexity and firewall prompts.
- Bind to `0.0.0.0` (all interfaces) so Sonos can reach via the LAN IP, not `127.0.0.1`.
- Build automatic resubscribe on a timer at `timeout * 0.75` and on application wake-from-sleep.
- Sign the app and ensure the firewall prompt is acceptable (signed apps get a friendlier prompt and respect the user's allow decision across launches).

---

### Pitfall 8: DIDL-Lite metadata XML escaping disasters

**Severity:** MEDIUM
**Phase:** build

**What goes wrong:**
`SetAVTransportURI` requires two arguments: the URI itself, and `CurrentURIMetaData`, which is a DIDL-Lite XML document **embedded as an escaped string inside the SOAP XML body**. The DIDL-Lite contains track title, artist, etc. — fields that come from YouTube Music data, which routinely contains characters like `&`, `'`, `<`, smart-quotes, em-dashes, and emoji. Get any of this wrong and Sonos throws SOAP fault `718` ("Invalid InstanceID"), `402` ("Invalid Args"), or just silently doesn't display the track info.

**Why it happens:**
Double-escaping problem. The DIDL-Lite XML must be valid XML (escape `&` as `&amp;` etc.) AND that entire string must then be XML-escaped *again* to embed inside the SOAP envelope (so `&amp;` becomes `&amp;amp;`). Hand-rolled XML construction gets this wrong constantly. The SoCo Python library has dedicated `escape()` helpers for exactly this reason.

**Prevention strategy:**
- Use `XMLDocument` / `XMLElement` from Foundation rather than string interpolation. Let Apple's serializer handle escaping.
- Write a unit test fixture with a song titled `Tom & Jerry's "Best" <of> 2006 — café` and verify the SOAP body parses back identically.
- Include the standard Sonos DIDL-Lite namespaces:
  - `xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"`
  - `xmlns:dc="http://purl.org/dc/elements/1.1/"`
  - `xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"`
  - `xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/"`
- Set `<upnp:class>object.item.audioItem.musicTrack</upnp:class>` for tracks, `object.item.audioItem.audioBroadcast` for live streams.

**Warning signs:**
- SOAP fault 402, 712, 714, 718 with valid-looking XML
- Sonos plays audio but shows "Unknown" / "Untitled" on the speaker LEDs and the controller app
- Specific tracks fail consistently (the ones with `&` in their titles)

---

### Pitfall 9: Latency stackup pushes pause-response above the 2-second target

**Severity:** HIGH
**Phase:** spike (uncertainty #4 — measure end-to-end and report a number)

**What goes wrong:**
Spike "works" — audio plays through the Sonos. User presses pause. Audio continues for **3-4 seconds** before stopping. User presses play. Three more seconds before audio resumes. UX is unusable.

**Why it happens:**
The latency budget compounds across stages:
| Stage | Typical latency |
|---|---|
| Capture buffer (process tap or SCK) | 20-100 ms |
| Encoder buffer (MP3 LAME frame size + bitrate quantization) | 100-300 ms |
| HTTP server send buffer | 10-50 ms |
| TCP/Wi-Fi RTT | 5-30 ms |
| **Sonos input pre-buffer** | **~2000 ms** (intentional, prevents dropouts) |
| Sonos audio pipeline output | 50-200 ms |
| **Total perceived latency** | **~2.2 - 2.7 seconds** |

The Sonos side dominates. The 2-second pre-buffer is documented Sonos behavior — line-in delay alone is minimum 75 ms, *streaming* pre-buffer is much larger. AirConnect users discuss this exact pain on the project's discussion board.

**The pause problem specifically:** when the user pauses, Kaset can stop sending audio bytes immediately, but the Sonos already has ~2 seconds of audio in its pre-buffer that it will play out before going quiet. Telling Sonos to `Pause` via SOAP works but adds the SOAP RTT (~50-100 ms).

**Falsification test:**
The spike must measure pause-to-silence and play-to-audible with a stopwatch and a phone microphone, and report a number. If > 2.5 seconds, decide: ship anyway, or pivot to telling Sonos to `Stop` (faster than `Pause` because it discards the buffer) and re-send the URL on resume.

**Prevention / mitigation strategies:**
- **Pause = Stop**: When user pauses, send `Stop` to Sonos (drains buffer quickly) instead of `Pause`. On resume, re-`SetAVTransportURI` and `Play`. Trades resume latency for pause latency, but pause perception matters more.
- **Skip = Stop + new URL**: Each track gets a unique URL (`/stream/<trackid>.mp3`) so Sonos's URL cache doesn't replay the previous track.
- **Volume = SOAP-direct**: Use `RenderingControl::SetVolume` for volume changes, not the audio stream — instant.
- Don't try to tune away the 2-second Sonos pre-buffer. It's not user-configurable on S1.

**Warning signs:**
- User pause feels "delayed" in informal demo
- Sonos continues audio for >1 second after `Pause` SOAP command returns 200
- Skip/next produces overlapping audio or a brief replay of the previous track's tail

---

### Pitfall 10: Sandbox blocks the inbound HTTP listener on `0.0.0.0`

**Severity:** HIGH
**Phase:** spike (one-line config fix, but if missed, blocks everything)

**What goes wrong:**
Spike's HTTP server calls `listen()` on port 5000. `bind` succeeds in non-sandbox builds but fails with `EPERM` or "Address already in use" or returns success but the socket never receives connections in sandboxed builds.

**Why it happens:**
App Sandbox requires `com.apple.security.network.server` entitlement for the app to listen on a socket. Without it, `bind()` may succeed (especially with `__darwinAllowLocalNetworking`-style workarounds noted in NixOS issue #11269) but external connections won't reach. Documented Apple Developer Forums issue with multiple repro reports.

**Prevention strategy:**
- Add to Kaset's `.entitlements` file:
  ```xml
  <key>com.apple.security.network.server</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  ```
- The `network.client` is already there for YTMusicClient; verify both are present for the Sonos build.
- Test the server in a sandboxed Release build, not just Debug — sandbox enforcement is stricter in some build configurations.

**Warning signs:**
- `curl http://<mac-lan-ip>:5000/` from another device on the same network connects but hangs or returns ECONNREFUSED
- `lsof -i :5000` shows the listener on `127.0.0.1` only, not `0.0.0.0` or `*`
- Works in `swift run` (CLI, no sandbox) but fails in the .app bundle

---

### Pitfall 11: macOS application firewall prompt blocks Sonos inbound connections

**Severity:** MEDIUM
**Phase:** build / polish

**What goes wrong:**
First time Kaset opens its HTTP listener, macOS prompts: "Do you want to allow Kaset to accept incoming network connections?" If the user is unsigned/ad-hoc, the prompt re-appears every launch. If the user clicks "Deny" once, all incoming connections (audio fetch, GENA NOTIFY callbacks) are silently dropped forever until they manually fix it in System Settings → Network → Firewall.

**Why it happens:**
macOS's app firewall (separate from the packet filter) is on by default on most modern Macs. Unsigned listeners trigger the prompt every time. Signed and notarized listeners are remembered.

**Prevention strategy:**
- Ship signed + notarized (Kaset already does this for Sparkle updates, so the infra exists).
- Add a first-run UX: "Kaset needs to receive connections from your Sonos speakers. If macOS asks, click Allow." with a screenshot of the prompt.
- Detect deny-state by attempting a self-connection from another local interface and surfacing a recovery hint if it fails.

---

### Pitfall 12: AirSonos-style firmware breakage — Sonos changes the rules and your bridge dies

**Severity:** MEDIUM (long-term), HIGH (planning the maintenance burden)
**Phase:** roadmap (decision: how much to invest)

**What goes wrong:**
Spike succeeds. Build phase ships. Six months later, Sonos pushes a firmware update and the relay stops working. Users complain. The root-cause investigation reveals Sonos changed something subtle: a SOAP error code that was previously a soft failure now hard-disconnects, the URL fetch UA-sniffing is stricter, or the new firmware ignores `x-rincon-mp3radio://` for non-whitelisted hosts.

**Why it happens:**
This is the AirSonos / AirConnect lifecycle. AirSonos was archived June 2023 after years of mounting compatibility complaints with each Sonos firmware revision (issues #367 about Sonos 7.2, #383 about High Sierra/AirPlay 2). AirConnect users reported that a Sonos firmware update in mid-2024 broke playback (10-second connect-then-disconnect symptom — issue #458). Sonos has business reasons to discourage non-partner relays; firmware changes frequently break them, sometimes incidentally, sometimes pointedly. The S1 firmware *line* is in maintenance mode (no new features, only critical fixes) which is paradoxically *helpful* — the rate of breaking change is lower than on S2 — but doesn't eliminate it.

**Prevention strategy:**
- Pin the realistic expectation in `PROJECT.md`: this is a **best-effort integration**, not a contract. Document in user-facing copy ("Works with current S1 firmware. May break on Sonos updates.").
- Build a **diagnostics view** that lets users self-report enough info to fix breakage quickly: discovered devices, last SOAP error, last successful play timestamp, current Sonos firmware version (exposed by `DeviceProperties::GetZoneInfo`).
- Subscribe to Sonos S1 release notes and budget a half-day-per-quarter for compatibility regressions.
- Don't promise "Sonos support" in marketing copy — promise "Plays to legacy Sonos systems where supported." The framing matters.

**Warning signs (post-launch):**
- A clump of bug reports immediately following a Sonos firmware date
- Specific device models start failing while others continue working (Sonos doesn't always update all models simultaneously)
- A SOAP action that previously returned 200 now returns a fault code

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|---|---|---|---|
| Hardcode MP3 320 CBR encoding | Simplest pipeline; broadest Sonos compatibility | Loses bit-perfect playback users care about; +CPU/battery | **Acceptable for v1.** Ship MP3 first. FLAC is a polish-phase feature. |
| Skip GENA eventing, poll AVTransport state every 2s | Removes inbound-server complexity; works even if user denies firewall | Misses external state changes (Sonos S1 app pause); 2s lag on detecting track-end; constant network chatter | **Never.** Polling defeats the integration's UX promise — the whole point is feeling native. |
| Hardcode the user's first discovered Sonos | Skips the device-picker UI for the spike | Unusable for any user with multiple Sonos rooms; can't switch outputs | **Spike only.** Build phase must do device selection. |
| Synchronous SOAP calls on the main actor | Simple `await` chain | Network blips freeze the UI; one slow SOAP holds up all transport | **Never.** SOAP must be off-main-actor with a single-flight queue. |
| Reuse a single `<upnp:class>object.item.audioItem.audioBroadcast</upnp:class>` for everything | Skips the music-track-vs-radio distinction | "Now playing" UI on Sonos hardware shows wrong icon/format; some controllers misbehave | **Acceptable for spike**, fix in build. |
| Local hardcoded port (e.g., always 5000) | Easy to test, easy to log | Conflicts when user has another local server (Plex Media Server uses 32400 but plenty of others squat 5000) | **Spike only.** Build picks an ephemeral port and advertises it in the URL. |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|---|---|---|
| Sonos UPnP control | Hitting `:1400/MediaRenderer/AVTransport/Control` directly without first reading the device description XML | Always GET `http://<sonos-ip>:1400/xml/device_description.xml` first, parse the service list, use the URLs Sonos advertises (they vary by model and firmware) |
| Sonos coordinator vs member | Issuing `Play` to a grouped Sonos member, not the coordinator | Read `ZoneGroupTopology::GetZoneGroupAttributes` to find the coordinator before issuing transport commands; sending to a non-coordinator silently no-ops |
| ScreenCaptureKit audio | Filtering by window when the goal is per-process audio | Use `SCContentFilter(audio)` per-process, not per-window — audio is application-level not window-level |
| GENA SUBSCRIBE | Sending `CALLBACK: <http://127.0.0.1:port/>` | Sonos can't reach localhost; use `CALLBACK: <http://<your-lan-ip>:port/path>` and ensure you can detect interface changes (Wi-Fi → Ethernet handover) |
| SOAP over HTTP | Forgetting `SOAPACTION` header | Sonos returns `405` or `412` without the right `SOAPACTION: "urn:schemas-upnp-org:service:AVTransport:1#Play"` header (note the literal quotes around the value) |
| Network.framework + multicast | Using `NWConnection.send` for multicast | Use `NWConnectionGroup` with a multicast group descriptor; `NWConnection` is not multicast-rated per Apple's own forum guidance |
| Sonos volume | Setting volume via the audio stream amplitude | Use `RenderingControl::SetVolume` SOAP action — instant feedback, doesn't fight the user's hardware volume buttons |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|---|---|---|---|
| Encoding on the main actor | UI hitches on track changes; PlayerService state updates lag | Encoder runs in a detached `Task` with explicit dispatch off `@MainActor`; use AVAudioConverter to a background queue | Any sustained 320 kbps MP3 encoding on M-series CPUs is fine in raw throughput, but blocking main thread is fatal |
| Per-frame logging in the audio path | Hot path generates thousands of log lines/sec; `os.Logger` ring buffer overflows; Console.app freezes | Use level guards: `if logger.shouldLog(.debug)` before formatting; structured fields not interpolated strings | Always when DEBUG; never in Release — but if a Release log statement leaks in, it's quietly expensive |
| Re-encoding silence | When playback paused but capture pipeline still running, encoder eats CPU producing silent MP3 | Detect silence in capture (`peak < threshold for N frames`), short-circuit encoder, or stop pipeline on pause | After ~30 min of paused-but-running, battery noticeably warmer |
| Single SOAP queue contention | Volume slider drag fires 60 SOAP calls/sec; each waits for the previous; UI volume lags real Sonos volume | Coalesce volume updates with a `debounce`; only send the latest value when no SOAP is in flight | Any user with a fast scroll wheel on the volume slider |
| Subscription leak | App goes to sleep, never unsubscribes; Sonos keeps trying to NOTIFY a closed port; eventually subscription times out anyway but logs are noisy | Explicit UNSUBSCRIBE on quit/sleep; rely on timeout as backup not primary | A few hours of runtime; mostly invisible but a polish concern |
| HTTP server thread-per-connection | Sonos reconnects + GENA NOTIFY traffic spawn threads | Use Network.framework's `NWListener` (event-driven) not pthread-style server; a couple of concurrent TCP connections is fine but model it correctly | Never breaks at this scale; just don't start with the wrong pattern |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---|---|---|
| HTTP server exposed on all interfaces with no auth | Any device on the LAN (or an attacker on the same Wi-Fi) can hit `http://<mac>:5000/stream.mp3` and listen to whatever Kaset is playing | Bind to LAN-only interfaces (skip VPN tunnels); use a per-session unguessable URL path token (`/stream/<random-uuid>.mp3`); rotate on each session |
| HTTP server doubles as command channel | If the audio server also accepts control POSTs, you've built a remote-control surface for whoever's on the LAN | Keep the HTTP server **read-only and audio-only**; UPnP control is *outbound* SOAP from Kaset to Sonos, no inbound control needed |
| Logging captured audio path | Logs include track titles + timestamps that leak listening history off the device if telemetry is on | Audit `DiagnosticsLogger` calls in the relay path; treat track titles like PII |
| Cookies leaked into HTTP server | Forgetting that the audio relay is a different request context from the YTMusic API and accidentally reusing the same `URLSession` with auth cookies | The relay's `NWListener` and the YTMusic `URLSession` share nothing; verify by code review |
| GENA callback URL leaks LAN IP to remote | Not really a risk for LAN-only Sonos, but if the multicast escapes to a guest network bridge, the callback URL identifies the Mac | Bind callback URL to the same interface where the Sonos was discovered; don't advertise on interfaces the device isn't on |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---|---|---|
| No "Sonos is playing" indicator distinct from local playback | User starts playback, hears nothing from local speakers, panics, doesn't realize it routed to Sonos | First-class output picker UI (like AirPlay's) with persistent indicator in the player bar; Apple Music / Spotify both nail this |
| Pause looks broken because of the 2-second buffer | User clicks pause, audio keeps playing, clicks pause again, second click lands on play, audio restarts from buffer | UI should reflect *intent* immediately (button toggles to "Play" instantly) even though audio takes 2s to actually stop. Optionally: dim the album art during the transition |
| Mac sleep silently kills playback | User puts Mac to sleep, music stops, no obvious explanation when they return | First-run education: "Sonos playback requires the Mac to stay awake." Detect sleep events and show a clear notification. Optionally offer a "keep awake while playing to Sonos" toggle that uses `IOPMAssertionCreateWithName` |
| Switching outputs causes a gap of dead air | User toggles from "This Mac" to "Sonos" mid-track; 3-4 seconds of silence | Acceptable for v1 if there's a visible "switching to Sonos…" indicator; unacceptable if silent |
| Sonos discovery shown as "Sonos" generic icon when Sonos S1 has named rooms | User sees "Speaker 1, Speaker 2" instead of "Living Room, Kitchen" | Read `DeviceProperties::GetZoneAttributes` for `CurrentZoneName`; show that name |
| User has multiple Sonoses grouped — only one shows up but audio comes out of all | Confusing because Kaset's UI says "Living Room" but Kitchen and Bedroom are also playing | Read `ZoneGroupTopology` and either show all members of the group or display the group name explicitly |
| External pause from Sonos S1 app doesn't update Kaset | Out-of-sync transport state; user thinks Kaset is broken | Implement GENA NOTIFY (Pitfall 7) so Kaset sees state changes from any controller |

---

## "Looks Done But Isn't" Checklist

Verify each before declaring the spike (or the build phase) complete:

- [ ] **Audio capture:** Verified with peak-amplitude measurement on a known-loud DRM track, not just "I heard sound." Silent capture is the failure mode, not "errors." Pitfall 1.
- [ ] **EQ coexistence:** Tested EqualizerService ON and Sonos relay ON simultaneously. Both work, or there's a documented mutex. Pitfall 2.
- [ ] **Sonos accepts the stream:** Verified with `tcpdump`/Wireshark that Sonos issued the GET, received `audio/mpeg`, and didn't disconnect within 30 seconds. Pitfall 3.
- [ ] **No chunked encoding:** Server response headers verified to use HTTP/1.0 + `Connection: close`, no `Transfer-Encoding: chunked`. Pitfall 4.
- [ ] **Discovery works in sandbox:** SSDP M-SEARCH packets verified leaving the Mac via a packet sniffer; replies arrive; entitlement granted. Tested in `.app` bundle, not just CLI. Pitfall 6.
- [ ] **Eventing works end-to-end:** Pause from the Sonos S1 phone app reaches Kaset's NOTIFY handler within 1 second. Pitfall 7.
- [ ] **DIDL-Lite escape test:** Played a track titled `Tom & Jerry's "Best" — café` and saw it correctly displayed on the Sonos hardware. Pitfall 8.
- [ ] **Pause latency measured:** Stopwatched pause-to-silence and reported a number ≤ 2.5s. Pitfall 9.
- [ ] **Sandbox network.server:** Verified another device on the LAN can curl the audio URL successfully from a Release build. Pitfall 10.
- [ ] **Firewall behavior:** Tested first launch on a Mac with default firewall settings; documented the prompt UX. Pitfall 11.
- [ ] **Multi-room Sonos group:** If user has grouped Sonoses, the controller correctly sends to the group coordinator. Integration Gotchas table.
- [ ] **Skip behavior:** Skipping a track on Kaset doesn't briefly play the previous track's tail on the Sonos. Pitfall 5.
- [ ] **Volume coalescing:** Dragging the volume slider doesn't lag — UI volume tracks finger position, Sonos catches up. Performance Traps table.
- [ ] **Sleep handling:** Mac sleep / wake doesn't leave the relay in a broken half-state requiring app restart.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---|---|---|
| ScreenCaptureKit returns silent for DRM (Pitfall 1) | MEDIUM | Pivot to Core Audio process tap (`CATapDescription` on Kaset's own PID). Existing `EqualizerService` is prior art. ~2-3 days additional spike work. |
| EQ + relay can't coexist (Pitfall 2) | MEDIUM | Either refactor `EqualizerService` to be the single tap owner with fan-out subscribers, OR add a mutex (Sonos active disables EQ). ADR + 2-4 days build work. |
| 714 MIME-type rejection (Pitfall 3) | LOW | Toggle Content-Type to `audio/mpeg`, switch URI scheme to `x-rincon-mp3radio://`, remove parameters. Hours, not days. |
| Chunked encoding rejected (Pitfall 4) | LOW | Switch HTTP server to HTTP/1.0 mode for live streams. Library-level config change. |
| Multicast entitlement not granted (Pitfall 6) | HIGH (calendar) | Apple turnaround for the entitlement is days-to-weeks. Mitigation: request immediately at spike start; meanwhile prototype with BSD sockets in a CLI helper to validate the rest of the stack. |
| GENA NOTIFY callbacks don't arrive (Pitfall 7) | MEDIUM | Verify network.server entitlement, verify firewall allow, verify callback URL uses LAN IP not loopback, verify Sonos can route to that IP (`ping` test from a phone on same LAN). |
| Latency > 3s (Pitfall 9) | MEDIUM | Switch pause-implementation from `Pause` SOAP to `Stop` SOAP. Switch encoder buffer settings. If still bad: accept and document. |
| Firmware update breaks integration (Pitfall 12) | HIGH (recurring) | Diagnostics view ships in v1 specifically to make remote debugging tractable. Maintain a known-bad-firmware list in app config (could be served from an updates feed without a release). |

---

## Pitfall-to-Phase Mapping

| Pitfall | Severity | Phase | Verification |
|---|---|---|---|
| 1: ScreenCaptureKit silent on DRM | BLOCKER | spike | Day-1 amplitude test on captured `.caf` file |
| 2: EQ + relay tap conflict | HIGH | spike | Both services enabled simultaneously; both produce audio |
| 3: Sonos rejects with 714 | HIGH | spike | Static MP3 file plays on Sonos via SetAVTransportURI |
| 4: Chunked encoding breaks streaming | HIGH | spike | Live capture stream plays for >5 minutes uninterrupted |
| 5: Seek/scrub against live URL | MEDIUM | build | Scrub UI test: target position reached on Sonos within 3s |
| 6: SSDP discovery silent failure | HIGH | spike | Multicast entitlement granted; M-SEARCH packets visible in Wireshark; replies parsed |
| 7: GENA NOTIFY not delivered | HIGH | spike | External pause from Sonos S1 app reflects in Kaset within 1s |
| 8: DIDL-Lite XML escaping | MEDIUM | build | Unit test fixture with adversarial track titles round-trips correctly |
| 9: End-to-end latency | HIGH | spike | Stopwatched measurement reported with target threshold |
| 10: Sandbox blocks listener | HIGH | spike | curl from a different LAN device hits Release build's port |
| 11: Firewall prompts every launch | MEDIUM | polish | Signed+notarized build; first-run UX; docs |
| 12: Firmware drift | MEDIUM | roadmap | Diagnostics view; expectation-setting in user copy |

**Spike must answer all four BLOCKER/HIGH "spike" rows above with a binary outcome (works / doesn't work / works with workaround X) before the milestone re-scopes to a build phase.**

---

## Sources

### Prior art / post-mortems

- [AirSonos GitHub repo (archived June 2023)](https://github.com/stephen/airsonos) — historical Node.js AirPlay-to-Sonos bridge; the canonical reference for "this used to work, then Sonos firmware changed"
- [AirSonos issue #367 — Sonos 7.2 firmware breakage](https://github.com/stephen/airsonos/issues/367) — example of how a single Sonos firmware update breaks a working bridge
- [AirSonos issue #383 — High Sierra / AirPlay 2 incompatibility](https://github.com/stephen/airsonos/issues/383) — Apple-side breakage compounding the problem
- [AirConnect (philippe44/AirConnect)](https://github.com/philippe44/AirConnect) — the modern descendant; README documents the HTTP-pull architecture Sonos requires
- [AirConnect issue #458 — post-Sonos-update playback broken](https://github.com/philippe44/AirConnect/issues/458) — concrete recent example: 10s connect-then-disconnect after Sonos firmware update
- [AirConnect discussion #467 — latency in Sonos environment](https://github.com/philippe44/AirConnect/discussions/467) — pause-latency UX pain
- [swyh-rs (dheijl/swyh-rs)](https://github.com/dheijl/swyh-rs) — Stream What You Hear in Rust; README documents the silence-injection trick for keeping Sonos from disconnecting
- [swyh-rs issue #71 — stream breaks at any pause](https://github.com/dheijl/swyh-rs/issues/71) — the "Sonos disconnects when no samples for a moment" gotcha
- [swyh-rs issue #84 — stuttering every 30s on Sonos One](https://github.com/dheijl/swyh-rs/issues/84) — example of subtle Sonos buffering edge cases
- [SWYH issue #16 — Sonos PLAY:1 doesn't work](https://github.com/StreamWhatYouHear/SWYH/issues/16) — original SWYH project's Sonos pain
- [Sonos community: chunked encoding transfer and MP3](https://en.community.sonos.com/advanced-setups-229000/chunked-encoding-transfer-and-mp3-a-technical-question-6763502) — direct confirmation Sonos doesn't play well with chunked encoding
- [Sonos community: 2 second delay removed?](https://en.community.sonos.com/components-and-architectural-228996/2-second-delay-removed-6891913) — 2-second pre-buffer is intentional architecture
- [Sonos community: custom radio URL broken on S1 app](https://en.community.sonos.com/controllers-and-music-services-229131/custom-radio-url-completely-broken-sonos-s1-app-legacy-system-6927934) — S1-specific fragility
- [Hacker News: Sonos CEO steps down after app update debacle](https://news.ycombinator.com/item?id=42687932) — context for "Sonos as a platform partner is unreliable" framing
- [Digital Trends: Sonos software meltdown 2024](https://www.digitaltrends.com/home-theater/sonos-software-meltdown/) — same context

### Sonos protocol references

- [Sonos: Supported audio formats (docs.sonos.com)](https://docs.sonos.com/docs/supported-audio-formats) — authoritative codec list
- [Sonos: Supported audio formats for music library (S1 app)](https://support.sonos.com/en/article/supported-audio-formats-for-sonos-music-library) — confirms S1 16-bit FLAC ceiling
- [Sonos community: S1 Controller and HD/FLAC](https://en.community.sonos.com/controllers-and-music-services-228995/s1-controller-and-hd-flac-6851642) — S1-specific FLAC limitation
- [svrooij Sonos API: AVTransport service](https://sonos.svrooij.io/services/av-transport) — third-party but well-maintained protocol reference
- [svrooij sonos-api-docs (GitHub)](https://github.com/svrooij/sonos-api-docs/blob/main/docs/services/av-transport.md) — same, version-controlled
- [Sonos UPnP Error 714 thread (Home Assistant)](https://community.home-assistant.io/t/sonos-upnp-error-714-received-illegal-mime-type/763320) — common 714 root causes
- [Home Assistant issue #74869 — TTS error 714 on Sonos](https://github.com/home-assistant/core/issues/74869) — concrete 714 reproduction
- [Home Assistant issue #37444 — error playing MP3 stream](https://github.com/home-assistant/core/issues/37444) — Sonos rejecting otherwise-valid MP3 streams
- [SoCo issue #247 — DIDL-Lite for music services](https://github.com/SoCo/SoCo/issues/247) — DIDL-Lite gotchas
- [gotwalt/sonos issue #61 — SetAVTransportURI failing](https://github.com/gotwalt/sonos/issues/61) — DIDL-Lite escaping bug repro
- [SpinlockLabs/upnp.dart issue #5 — SetAVTransportURI metadata problems](https://github.com/SpinlockLabs/upnp.dart/issues/5) — same gotcha in another lang
- [UPnP AVTransport:3 specification](https://upnp.org/specs/av/UPnP-av-AVTransport-v3-Service-20101231.pdf) — authoritative protocol spec

### macOS audio capture

- [Apple: Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps) — official docs for the macOS 14.2+ process-tap API
- [Apple: ScreenCaptureKit documentation](https://developer.apple.com/documentation/screencapturekit/) — official docs
- [Apple: Capturing screen content in macOS](https://developer.apple.com/documentation/ScreenCaptureKit/capturing-screen-content-in-macos) — sample code reference
- [insidegui/AudioCap (GitHub)](https://github.com/insidegui/AudioCap) — Guilherme Rambo's well-regarded sample for macOS 14.4+ system audio capture
- [Sudara Gist: Core Audio Tap API example for macOS 14.2](https://gist.github.com/sudara/34f00efad69a7e8ceafa078ea0f76f6f) — short, working CATapDescription sample
- [makeusabrew/audiotee (GitHub)](https://github.com/makeusabrew/audiotee) — Core Audio Taps CLI tool; useful as a comparison baseline
- [stronglytyped.uk: AudioTee article](https://stronglytyped.uk/articles/audiotee-capture-system-audio-output-macos) — explainer on Core Audio taps
- [pyobjc issue #647 — SCStream audio errors on macOS 15](https://github.com/ronaldoussoren/pyobjc/issues/647) — concrete repro of ScreenCaptureKit audio failure modes (`-3805`)
- [Lobsters: Why can't we screenshot DRM video on Apple devices](https://lobste.rs/s/5ltsh1/why_can_t_we_screenshot_frames_from_drm) — explainer on Apple's DRM compositing-layer exclusion

### macOS networking / sandbox / multicast

- [Apple: com.apple.security.network.server entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.server) — the entitlement Pitfall 10 hinges on
- [Apple Forums: SSDP discovery not working](https://developer.apple.com/forums/thread/680731) — the canonical Apple-side multicast/SSDP debugging thread
- [Apple Forums: SSDP discovery — address in use](https://developer.apple.com/forums/thread/725717) — common SSDP port-binding gotcha on macOS
- [Apple Forums: Multicast Networking entitlement](https://developer.apple.com/forums/thread/694041) — entitlement application process
- [Apple: NWMulticastGroup documentation](https://developer.apple.com/documentation/network/nwmulticastgroup) — `NWConnectionGroup` for multicast
- [Apple Forums: Network.framework multicast UDP enhancement](https://developer.apple.com/forums/thread/104724) — historical context
- [tempelmann/SSDP-Browser](https://github.com/tempelmann/SSDP-Browser) — open-source macOS SSDP browser; useful spike reference and packet-comparison ground truth
- [coolaj86: Adventures in UPnP on OS X](https://coolaj86.com/articles/adventures-in-upnp-on-osx/) — old but relevant
- [NixOS issue #11269 — sandbox bind/listen failure](https://github.com/NixOS/nix/issues/11269) — concrete example of `network.server` entitlement gotcha
- [.NET runtime issue #30739 — server entitlement needed even for client connect](https://github.com/dotnet/runtime/issues/30739) — surprising entitlement edge case
- [Haivision/srt issue #647 — server sandbox entitlement](https://github.com/Haivision/srt/issues/647) — same theme

### UPnP eventing reference

- [UPnP Device Architecture tutorial (UDA July 2014)](https://upnp.org/resources/documents/UPnP_UDA_tutorial_July2014.pdf) — authoritative GENA reference
- [pupnp DeepWiki: GENA Events](https://deepwiki.com/pupnp/pupnp/3.3-gena-events) — implementation guide
- [Sonos community: UPnP Event Subscription in .NET](https://en.community.sonos.com/advanced-setups-229000/upnp-event-subscription-net-c-34484) — concrete GENA-on-Sonos example
- [SoCo events module documentation](https://docs.python-soco.com/en/latest/api/soco.events.html) — Python implementation, useful as reference
- [a-lurker/Vera-Plugin-UPnP-Event-Proxy](https://github.com/a-lurker/Vera-Plugin-UPnP-Event-Proxy) — explainer on the eventing callback model
- [Sonos community: notifications, detect volume changes from other client](https://en.community.sonos.com/advanced-setups-229000/notifications-how-to-detect-volume-changes-from-other-client-6748825) — Sonos-specific GENA usage

---

*Pitfalls research for: Mac-side audio relay to Sonos S1 via local HTTP server + Swift-native UPnP/SOAP, with audio sourced from a hidden DRM-protected WKWebView*
*Researched: 2026-04-27*
