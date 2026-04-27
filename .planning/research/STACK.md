# Stack Research

**Domain:** Sonos S1 audio integration for a native macOS YouTube Music client (Kaset)
**Researched:** 2026-04-27
**Confidence:** HIGH for pillars 1, 3, 4 / MEDIUM for pillar 2 (Sonos S1 firmware behavior is the residual unknown — must be confirmed in spike)

## Scope

This document covers ONLY the four new pillars introduced by the Sonos milestone:

1. Real-time audio capture from the WKWebView playing DRM-protected content
2. Embedded HTTP audio streaming server in Swift, in a format Sonos S1 accepts
3. SSDP discovery + UPnP/SOAP control + UPnP eventing in Swift
4. Audio re-encoding pipeline (PCM taps → encoded chunks → HTTP body)

Existing Kaset stack (Swift 6 / SwiftUI / macOS 26 / WKWebView / `YTMusicClient` / `EqualizerService`) is documented in `.planning/codebase/STACK.md` and is treated as locked.

> Critical constraint reminder (per `CLAUDE.md`): no third-party Swift packages without explicit approval, no `print()` (use `DiagnosticsLogger`), no `DispatchQueue` (Swift Concurrency only), no force unwraps, `@MainActor` on `@Observable` classes.

---

## Recommended Stack

### Core Technologies (one per pillar)

| Pillar | Technology | Min macOS | Purpose | Why Recommended |
|--------|------------|-----------|---------|-----------------|
| 1. WebView audio capture | **Core Audio Process Tap** (`AudioHardwareCreateProcessTap` + `CATapDescription` + `AudioHardwareCreateAggregateDevice`) | 14.2 | Tap audio output of `com.apple.WebKit.WebContent` / `com.apple.WebKit.GPU` XPC processes that host the YouTube player | Kaset **already ships this exact mechanism** in `Sources/Kaset/Services/Audio/ProcessTapHelper.swift` for the EQ pipeline. Zero new entitlements, zero new permission prompts (`NSAudioCaptureUsageDescription` is already declared), and the tap survives the WKWebView lifecycle because it's process-targeted, not view-targeted. ScreenCaptureKit is the wrong choice here — see "What NOT to Use". |
| 2. Audio format on the wire | **MP3 over HTTP, Shoutcast/ICY-style** (CBR 192–320 kbps, 44.1 kHz stereo, `audio/mpeg`, no `Content-Length`, served as an open-ended stream) | n/a | Format the Sonos S1 plays from a `SetAVTransportURI` URL | Sonos S1 firmware identifies stream type **from URL suffix and protocol scheme, not from `Content-Type` headers**, and Shoutcast-style MP3 is the path every working third-party bridge (AirSonos, raop-play, etc.) uses. FLAC and WAV are accepted as *files*, but for an open-ended live capture stream MP3 is the format Sonos's "internet radio" path was built for. Use the `x-rincon-mp3radio://` URI scheme for the stream URL, not `http://`. |
| 3. Discovery + control + eventing | **`Network.framework` (`NWConnectionGroup` + `NWMulticastGroup`)** for SSDP, **`URLSession` `dataTask`** for SOAP control, **`Network.framework` `NWListener`** for the GENA event callback HTTP endpoint | 13.0+ for `NWConnectionGroup`; 10.15+ for `NWListener` and `URLSession` | Discover Sonos players on the LAN; issue SOAP `Play`/`Pause`/`SetAVTransportURI`/`SetVolume` actions to port 1400; receive UPnP `NOTIFY` events for transport state | All Apple-native, no third-party UPnP/SOAP library. `NWConnectionGroup` is the **only** modern Apple-blessed multicast API on macOS — `NWConnection` does not support multicast. SOAP is just XML POSTs over HTTP, which `URLSession` already handles. UPnP eventing is just an HTTP listener that receives `NOTIFY` requests, which is symmetric with the streaming server in pillar 4. |
| 4. Re-encoding pipeline | **`AVAudioEngine` tap → `AVAudioConverter` (PCM Float32 → MP3)** feeding an in-memory ring buffer that an **`NWListener`-based HTTP server** drains as the response body | 26.0 | Convert tapped PCM into a continuous Shoutcast-compatible MP3 byte stream and serve it on the LAN | Sits one node downstream of the existing `EqualizerAudioEngine`'s output, so the EQ and Sonos paths share a single capture upstream. **MP3 encoding requires a clarification**: Apple ships an MP3 *decoder* in Core Audio but no MP3 *encoder*. The two clean native paths are (a) AAC encoding via `AVAudioConverter` with `kAudioFormatMPEG4AAC` wrapped in ADTS, or (b) the platform LAME-equivalent encoder in Audio Toolbox (`kAudioFormatMPEGLayer3`) which is **encode-disabled by Apple on macOS**. **Spike must confirm whether Sonos S1 accepts AAC-in-ADTS over `x-rincon-mp3radio://`** — if yes, ship AAC. If no, the milestone needs explicit approval to vendor the LAME source (LGPL) as a Swift target — which violates the "no third-party deps" rule and so requires a human sign-off before scoping the build phase. |

### Supporting APIs and Types

| API / Type | Framework | Purpose | When to Use |
|------------|-----------|---------|-------------|
| `CATapDescription(stereoMixdownOfProcesses:)` | CoreAudio | Build a stereo mixdown tap targeting an array of `AudioObjectID`s representing WebKit XPC processes | At service startup, after enumerating audio processes via `kAudioHardwarePropertyProcessObjectList` and filtering for `com.apple.WebKit.WebContent` / `com.apple.WebKit.GPU` (already implemented in `ProcessTapHelper.processBundleID` / `isWebKitAudioCandidate`) |
| `AudioHardwareCreateAggregateDevice` | CoreAudio | Wrap the tap as an HAL aggregate device that `AVAudioEngine` can read from | Once per session at start; destroy on stop. Already implemented |
| `AVAudioEngine.inputNode.installTap(onBus:bufferSize:format:block:)` | AVFoundation | Pull PCM `AVAudioPCMBuffer`s off the aggregate device's input | Install a *second* tap (alongside the existing EQ render path) that forwards buffers into the Sonos encoder. Tap blocks run on a Core Audio thread — bridge into a `MainActor`-isolated service via `Task { await ... }`, never `DispatchQueue.main.async` |
| `AVAudioConverter(from:to:)` + `convert(to:error:withInputFrom:)` | AVFoundation | Convert tap PCM (Float32 interleaved, 48 kHz stereo by default for the existing tap) to AAC-in-ADTS at e.g. 192 kbps CBR | One converter per stream session. Set `bitRate` and `bitRateStrategy = .constant` to keep ICY metadata math sane |
| `NWConnectionGroup(with: NWMulticastGroup, using: .udp)` | Network | Send SSDP `M-SEARCH * HTTP/1.1` to `239.255.255.250:1900` and receive `HTTP/1.1 200 OK` responses listing Sonos players | At Sonos service startup and on a periodic refresh timer. Falls under the multicast entitlement (see "Entitlements") |
| `URLSession.shared.data(for: URLRequest)` | Foundation | POST SOAP envelopes to `http://<player-ip>:1400/MediaRenderer/AVTransport/Control` and `…/RenderingControl/Control` with `SOAPACTION` header | Every transport / volume command. Use a custom session with short timeouts (~3s) — control should fail loud, not stall the UI |
| `XMLParser` | Foundation | Parse `device_description.xml` from `http://<player-ip>:1400/xml/device_description.xml`, parse SOAP responses, parse GENA `<LastChange>` event payloads | Discovery, capability detection, event handling. Streaming SAX parser is fine — payloads are small |
| `NWListener` (TCP) | Network | (a) Serve the audio stream on `0.0.0.0:<port>` over HTTP/1.1 with `Transfer-Encoding: chunked` and ICY metadata; (b) accept UPnP `NOTIFY` callbacks from Sonos players for GENA events | One listener per role, both bound to a stable port (or reserved at startup and embedded in the SUBSCRIBE callback URL and the `SetAVTransportURI` URL) |
| `Bonjour` / `NetService` / `NWBrowser` | Network | **NOT** for Sonos discovery — Sonos S1 announces UPnP, not Bonjour. Mentioned only to rule out | n/a |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `swift run api-explorer` | Existing API explorer for YouTube Music endpoints | Per `CLAUDE.md`, **extend this binary** if adding any API exploration helpers (e.g. a `sonos discover` subcommand) rather than writing a one-off script |
| Wireshark with Sonos capture filter | Confirm the exact SOAP envelope, headers, and stream format Sonos accepts during the spike | Capture port 1400 + UDP 1900 + the streaming port. Essential for pillar 2 verification |
| `DiagnosticsLogger` (existing) | Add a `sonos` subsystem alongside `api`, `auth`, `player`, `ui`, `webkit` | Mandatory — `print()` is forbidden |

## Installation

No SPM additions. Every dependency is a system framework that already ships in macOS 26:

```swift
// Package.swift — no changes needed for any of these:
import AVFoundation     // AVAudioEngine, AVAudioConverter
import CoreAudio        // AudioHardwareCreateProcessTap, CATapDescription
import AudioToolbox     // AudioFormatID constants, ADTS helpers
import Network          // NWListener, NWConnectionGroup, NWMulticastGroup
import Foundation       // URLSession, XMLParser
import os               // os.Logger (via DiagnosticsLogger)
```

### Entitlements

Add to `Kaset.entitlements`:

| Entitlement | Value | Why |
|-------------|-------|-----|
| `com.apple.developer.networking.multicast` | `true` | Required by `NWConnectionGroup` to send SSDP `M-SEARCH` to `239.255.255.250:1900`. **Requires an Apple-issued multicast networking add-on entitlement** — request at https://developer.apple.com/contact/request/networking-multicast. Plan for ~1–2 week approval lead time |
| `com.apple.security.network.server` | `true` (sandbox) | Required for `NWListener` (the audio stream server **and** the GENA event callback server) to accept inbound TCP from Sonos players on the LAN |
| `com.apple.security.network.client` | `true` (already present implicitly via existing networking) | Outbound SOAP, SUBSCRIBE, and SSDP requests |

Add to `Info.plist` (already present per `.planning/codebase/STACK.md` for Core Audio process tap, but worth re-confirming):

| Key | Why |
|-----|-----|
| `NSAudioCaptureUsageDescription` | Required by the Core Audio process tap to capture audio from another process (the WKWebView's `WebContent` XPC) |

## Alternatives Considered

| Recommended | Alternative | When Alternative Could Win |
|-------------|-------------|----------------------------|
| Core Audio Process Tap (existing `ProcessTapHelper`) | `ScreenCaptureKit` `SCStream` with `capturesAudio = true` and a per-window `SCContentFilter` | Only if the existing process tap stops working on macOS 26 or stops capturing the WebContent XPC's audio. ScreenCaptureKit's audio is **filtered at app level only** ([Apple Forums thread 718279](https://developer.apple.com/forums/thread/718279)), and our app *is* the host — meaning we'd capture our own EQ output, including any future system sounds, not the cleanly-isolated WebContent stream. Process tap stays cleaner |
| MP3 over `x-rincon-mp3radio://` | FLAC over HTTP (lossless) | If the spike confirms Sonos S1 will accept a `x-rincon-mp3radio://` URL whose body is FLAC and not give up at the buffering stage. **Unlikely to work** — `x-rincon-mp3radio://` is hard-wired to the MP3 radio code path on S1 firmware ([Sonos community](https://en.community.sonos.com/advanced-setups-229000/chunked-encoding-transfer-and-mp3-a-technical-question-6763502)). FLAC works for *files*, not radio streams |
| MP3 over `x-rincon-mp3radio://` | WAV (uncompressed PCM) over HTTP | If MP3 encoding is blocked (no native encoder, see pillar 4 caveat) and AAC is rejected by S1. WAV would deliver true zero-encoding-latency audio at the cost of ~1.4 Mbps per stream — fine on a wired LAN, fragile on Wi-Fi. Sonos accepts WAV files but I have not found evidence S1 accepts a chunked, length-unknown WAV *stream* via `SetAVTransportURI`. Spike must verify before this becomes a real fallback |
| `AVAudioConverter` → AAC-in-ADTS | `AVAssetWriter` → fragmented MP4 (fMP4) → HLS | If Sonos S1 actually honors HLS (the modern Sonos docs claim HLS support, but S1 firmware is frozen and HLS support there is unverified). HLS would give us a clean spec-compliant story but adds a manifest server, segment lifecycle, and ~6s of inherent latency that violates the <2s target |
| `NWConnectionGroup` for SSDP | BSD sockets via `Darwin.socket` / `setsockopt(IP_ADD_MEMBERSHIP)` | If the multicast entitlement is denied or `NWConnectionGroup`'s [known unicast-response issue](https://developer.apple.com/forums/thread/657849) blocks SSDP responses. BSD sockets work today, but they bypass the strict-concurrency-friendly Network framework and bring their own Sendable problems |
| `URLSession` for SOAP | Hand-rolled HTTP over `NWConnection` | Never. SOAP is just HTTP POST with XML; `URLSession` is the path of least resistance and integrates with existing `YTMusicClient` patterns |
| `XMLParser` (SAX) for SOAP responses | `XMLDocument` (DOM, AppKit/Foundation) | DOM is fine for `device_description.xml` (small, parsed once) but SAX is required for the embedded XML inside `<LastChange>` event bodies because UPnP double-encodes XML there and DOM gets ugly fast |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `ScreenCaptureKit` (`SCStream` + `SCStreamConfiguration.capturesAudio`) for WebView capture | (1) ScreenCaptureKit audio is filtered at the **application** level, not the window or XPC subprocess level — it would capture *our* app, not the WebKit `WebContent` subprocess that hosts the YouTube player. (2) Adds a `NSScreenCaptureUsageDescription` permission prompt the user shouldn't have to grant for an audio-only feature. (3) Duplicates a capture path Kaset already ships and trusts | The existing `ProcessTapHelper` (Core Audio process tap targeting `com.apple.WebKit.WebContent` / `com.apple.WebKit.GPU`) — extend it to support multiple downstream consumers (EQ + Sonos) rather than re-implement |
| `AVCaptureSession` for audio capture | Designed for `AVCaptureDevice` inputs (microphone, camera). Cannot tap another process's audio output | Core Audio process tap |
| `Sparkle` / any third-party Swift package for UPnP, SOAP, SSDP, or RTSP | `CLAUDE.md` forbids new third-party deps without explicit approval, and the surface area we need is small (~6 SOAP actions, 1 SSDP query, 1 GENA subscriber) | Hand-roll on `URLSession` + `Network.framework` + `XMLParser`. Reference `svrooij/sonos-api-docs` for the action contracts (use as documentation, not as code) |
| `SonosKit`, `SwiftSonos`, similar community packages | None are well-maintained, all are third-party, all violate the no-deps rule | Same as above |
| `DispatchQueue.main.async` to bridge from Core Audio render threads back to UI | Forbidden by `CLAUDE.md` strict-concurrency policy | `Task { @MainActor in ... }` from inside the tap block, or pass `AVAudioPCMBuffer`s to a `Sendable` actor that owns the encoder and HTTP server |
| Plain `http://...` URLs in `SetAVTransportURI` | Sonos firmware (S1 included) since ~v6.4.2 routes `http://` URLs through a different (track-oriented, length-required) code path that does not handle open-ended chunked streams | `x-rincon-mp3radio://<mac-ip>:<port>/stream.mp3` — replace the scheme client-side before the SOAP call |
| LAME (vendored as a Swift target) for MP3 encoding | LGPL, third-party, requires explicit approval per `CLAUDE.md`. Brings build complexity (C source, conditional compilation, code-signing implications) | Try AAC-in-ADTS via `AVAudioConverter` first; only escalate to a "vendor LAME with approval" conversation if the Sonos S1 spike proves AAC won't play. Document the fork in the road in the spike report |
| `print()` for debug logging | Forbidden by `CLAUDE.md` | `DiagnosticsLogger.sonos.info(...)` (add the `sonos` subsystem) |
| Force unwraps | Forbidden by `CLAUDE.md` | `guard let` / typed throws / a `SonosError` enum mirroring `YTMusicError` |
| `@Observable` without `@MainActor` | Forbidden by `CLAUDE.md` | `@MainActor @Observable final class SonosService` — same pattern as `PlayerService` |
| Mixing `WKWebView`-side audio handoff (a la Spotify Connect / SMAPI) | Out of scope per `PROJECT.md` (requires Sonos partnership) | Local audio relay (the four pillars above) |

## Stack Patterns by Variant

**If the Mac-side capture latency budget proves tight (< 2s end-to-end is hard to hit):**
- Drop the encoder bitrate to 192 kbps CBR (smaller frames → faster fill)
- Use a 1-second ring buffer between encoder and HTTP server, not 5
- Prime the buffer with 2 KB of silent MP3 frames so Sonos's pre-roll doesn't stall
- Accept that play/pause/skip will incur the unavoidable Sonos buffer (≥ 75ms hardware floor + buffer prefetch ≈ 1–3s in practice for radio streams)

**If the multicast entitlement approval is delayed:**
- Ship discovery as a manual "Add Sonos by IP address" UI in v1
- Keep an SSDP code path behind a feature flag, ready to enable when the entitlement lands
- This also covers the user whose router has IGMP snooping issues that break SSDP

**If AAC-in-ADTS is rejected by Sonos S1:**
- Pause the milestone, surface the trade-off to the human:
  - Option A: ask for explicit approval to vendor LAME (LGPL) — violates the no-deps rule, requires sign-off
  - Option B: ship WAV-over-HTTP and accept ~1.4 Mbps on the LAN (Wi-Fi quality dependent)
  - Option C: drop Sonos S1 from scope and target only S2 / modern Sonos (hardware not available for testing)
- Do NOT silently vendor a third-party encoder without approval

**If the user has multiple Sonos zones / wants stereo pair / grouping:**
- Defer to v2. Single-zone playback is the milestone goal. Grouping uses additional UPnP actions on the `ZoneGroupTopology` service which is non-standard UPnP (Sonos-specific) and warrants its own research pass

## Version Compatibility

| Component | Minimum macOS | Notes |
|-----------|---------------|-------|
| `AudioHardwareCreateProcessTap` / `CATapDescription` | 14.2 | Already required by Kaset's existing `EqualizerService`, so no new floor |
| `NWConnectionGroup` / `NWMulticastGroup` | 14.0+ for stable behavior; the API exists since 14.0 but several macOS bugs were fixed through 15.x. macOS 26 is fine | Multicast entitlement still required even when running unsandboxed in some configurations |
| `AVAudioConverter` for AAC encoding | 10.11+ — well past the floor | Hardware-accelerated AAC encode available on Apple Silicon |
| `NWListener` (TCP) | 10.15+ — well past the floor | Use `.tcp` parameters and call `start(queue:)` with a dedicated `DispatchQueue` (the framework requires a `DispatchQueue` here even though we don't otherwise use `DispatchQueue` for app work — that's the framework boundary, not our code calling `DispatchQueue.main.async`) |
| `URLSession` async/await `data(for:)` | 12.0+ — well past the floor | Use a dedicated `URLSession` configured with `timeoutIntervalForRequest = 3.0` for SOAP control |
| Sonos S1 firmware | 11.x (frozen) | All recommendations target the S1 firmware code paths. **Do not** assume any S2-only feature works (Cloud Control API, modern HLS, etc.) |

## Key Native API Touchpoints (Reference)

These are the literal API entry points the build phase will call. Provided so the roadmap has concrete checkpoints.

**Pillar 1 — Audio capture (extend existing code):**
- `Sources/Kaset/Services/Audio/ProcessTapHelper.swift` (existing) — already creates the tap and aggregate device
- New: a `Sendable` "fanout" actor that takes `AVAudioPCMBuffer`s from a *second* `installTap(onBus:)` and routes them to N consumers (currently 1 = EQ; soon 2 = EQ + Sonos)

**Pillar 2 — Wire format:**
- HTTP/1.1 `200 OK`
- Headers: `Content-Type: audio/mpeg`, `Connection: close`, `Cache-Control: no-cache`, `icy-name: Kaset`, `icy-metaint: 16000` (only if injecting now-playing metadata; can omit for v1)
- Body: continuous concatenation of MP3 (or AAC-ADTS, pending spike) frames, no `Content-Length`, **no chunked encoding** (Sonos S1 explicitly does not handle `Transfer-Encoding: chunked` correctly per [Sonos community thread](https://en.community.sonos.com/advanced-setups-229000/chunked-encoding-transfer-and-mp3-a-technical-question-6763502)) — just keep the connection open and write bytes
- Stream URL handed to Sonos: `x-rincon-mp3radio://<mac-lan-ip>:<port>/stream.mp3`

**Pillar 3 — UPnP control:**
- SSDP discovery: `M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nMX: 3\r\nST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n` via `NWConnectionGroup`
- Device description: `GET http://<player-ip>:1400/xml/device_description.xml`
- Control endpoint: `POST http://<player-ip>:1400/MediaRenderer/AVTransport/Control` with header `SOAPACTION: "urn:schemas-upnp-org:service:AVTransport:1#<Action>"`
- Volume endpoint: `POST http://<player-ip>:1400/MediaRenderer/RenderingControl/Control` with `SOAPACTION: "urn:schemas-upnp-org:service:RenderingControl:1#SetVolume"`
- Eventing: `SUBSCRIBE http://<player-ip>:1400/MediaRenderer/AVTransport/Event` with headers `CALLBACK: <http://<mac-ip>:<callback-port>/notify>`, `NT: upnp:event`, `TIMEOUT: Second-1800`. Re-SUBSCRIBE before timeout, including the returned `SID`. Player POSTs `NOTIFY` requests back to the callback URL with an XML body containing a `<LastChange>` element whose value is *itself* an XML document (double-encoded)
- Standard SOAP actions Kaset will issue: `SetAVTransportURI`, `Play`, `Pause`, `Stop`, `SetVolume`, `GetVolume`, `GetTransportInfo`

**Pillar 4 — Encoding:**
- Source format: `AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)` (matches the existing tap output)
- Target format: `AVAudioFormat(streamDescription: &outputDesc)` where `outputDesc` is an `AudioStreamBasicDescription` with `mFormatID = kAudioFormatMPEG4AAC`, `mSampleRate = 44100`, `mChannelsPerFrame = 2`
- ADTS framing: prepend a 7-byte ADTS header to each AAC frame (Apple's encoder emits raw AAC, not ADTS — you wrap it manually; reference: [Apple Forums thread 67106](https://developer.apple.com/forums/thread/67106))
- Backpressure: a bounded `AsyncStream<Data>` (e.g. capacity = 200 frames ≈ 4.6s @ 44.1 kHz) between encoder and HTTP writer; drop oldest if full to keep latency bounded

## Sources

**Apple official documentation (HIGH confidence):**
- [Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps) — tap creation API contract
- [`AudioHardwareCreateProcessTap(_:_:)`](https://developer.apple.com/documentation/coreaudio/audiohardwarecreateprocesstap(_:_:)) — function signature and lifecycle
- [`SCStreamConfiguration.capturesAudio`](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio) — confirmed audio capture is application-level only
- [`SCStreamConfiguration.excludesCurrentProcessAudio`](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/excludescurrentprocessaudio) — confirms ScreenCaptureKit's app-level filtering model
- [Is it possible to get only audio from ScreenCaptureKit? (Apple Forums)](https://developer.apple.com/forums/thread/718279) — Apple-confirmed limitation that audio capture is per-app, not per-window / per-XPC
- [`AVAudioConverter`](https://developer.apple.com/documentation/avfaudio/avaudioconverter) — PCM ⇄ AAC conversion API
- [`NWListener`](https://developer.apple.com/documentation/network/nwlistener) — TCP listener for HTTP server
- [How to use multicast networking in your app](https://developer.apple.com/news/?id=0oi77447) — `NWConnectionGroup` is the supported multicast path; entitlement is mandatory
- [`com.apple.developer.networking.multicast`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast) — entitlement docs, including the request flow
- [SSDP discovery (Apple Forums)](https://developer.apple.com/forums/thread/680731) and [Messages not/slowly arriving for NWConnectionGroup](https://developer.apple.com/forums/thread/657849) — known unicast-response edge cases that the spike must validate

**Sonos / UPnP authoritative references (MEDIUM confidence — third-party reverse-engineering, but cross-referenced and consistent):**
- [Sonos supported audio formats (official)](https://support.sonos.com/en/article/supported-audio-formats-for-sonos-music-library) — MP3, FLAC (16-bit on S1), WAV, AAC, OGG accepted; Sonos systems support up to 48 kHz / stereo
- [svrooij Sonos API docs — AVTransport](https://sonos.svrooij.io/services/av-transport) and [GitHub mirror](https://github.com/svrooij/sonos-api-docs/blob/main/docs/services/av-transport.md) — SOAP envelope structures, action names, control endpoints
- [Sonos communication overview](https://sonos.svrooij.io/sonos-communication) — port 1400, `device_description.xml` location, service control + event endpoint paths
- [SoCo PR #443](https://github.com/SoCo/SoCo/pull/443/files) — community-confirmed switch from `http://` to `x-rincon-mp3radio://` URI scheme for radio-style streams since Sonos firmware 6.4.2
- [Chunked encoding transfer and MP3 (Sonos community)](https://en.community.sonos.com/advanced-setups-229000/chunked-encoding-transfer-and-mp3-a-technical-question-6763502) — confirms Sonos identifies stream type by URL suffix, not `Content-Type`; confirms `Transfer-Encoding: chunked` is unreliable
- [AirSonos architecture write-up — Hacking AirPlay into Sonos](https://medium.com/@stephencwan/hacking-airplay-into-sonos-93a41a1fcfbb) — independent confirmation that the Shoutcast-style HTTP-MP3-on-`x-rincon-mp3radio://` path is the established pattern for "stream arbitrary audio to Sonos"
- [AirSonos issue #26 — send PCM instead of MP3 stream](https://github.com/stephen/airsonos/issues/26) — community confirmation that PCM/WAV streaming to Sonos is unreliable; MP3 is the proven path
- [Sonos firewall configuration](https://support.sonos.com/en/article/configure-your-firewall-to-work-with-sonos) — port reference (1400 control, 1900 SSDP)
- [Custom radio URL completely broken (Sonos S1, legacy system)](https://en.community.sonos.com/controllers-and-music-services-229131/custom-radio-url-completely-broken-sonos-s1-app-legacy-system-6927934) — **flag for spike**: at least one user reports `x-rincon-mp3radio://` regressed on a recent S1 firmware. Validate on the user's actual hardware before locking the build phase

**Existing Kaset code (HIGH confidence — read directly):**
- `Sources/Kaset/Services/Audio/ProcessTapHelper.swift` — already implements `CATapDescription` + `AudioHardwareCreateProcessTap` + aggregate device targeting `com.apple.WebKit.WebContent` and `com.apple.WebKit.GPU`. Sonos pillar should reuse, not reinvent
- `Sources/Kaset/Services/Audio/EqualizerAudioEngine.swift` — already runs an `AVAudioEngine` reading from the aggregate device. Add a second tap for Sonos
- `.planning/codebase/STACK.md` — confirms `NSAudioCaptureUsageDescription` is already declared

---

*Stack research for: Sonos S1 audio integration on Kaset*
*Researched: 2026-04-27*
