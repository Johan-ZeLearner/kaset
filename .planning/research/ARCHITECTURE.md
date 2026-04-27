# Architecture Research

**Domain:** macOS native client adding LAN-side audio relay + UPnP control to a service-based MVC SwiftUI app
**Researched:** 2026-04-27
**Confidence:** MEDIUM-HIGH (existing EQ proves the capture half; UPnP half is unproven in-tree but the protocol surface is well-documented)

## Why This Document Exists

Kaset already plays DRM-protected audio through a hidden `WKWebView` and routes its output to system default via `EqualizerService`'s Core Audio process tap. The Sonos milestone needs to **insert a second output destination** — a Sonos S1 speaker on the LAN — without disturbing the existing playback path or the EQ.

The Sonos integration is fundamentally a **bridge**: capture audio from a process inside this Mac, expose it as an HTTP URL on the LAN, and tell the Sonos via UPnP/SOAP to fetch that URL. This is not new architecturally — AirConnect, AirSonos, and Sonospy all use the same pattern. What is new is doing it natively in Swift, inside an `@MainActor @Observable` service-based codebase, with no third-party dependencies and a Core Audio tap that is already partly claimed by the existing EQ.

This document maps the components, their boundaries, the data flow, the build order, and — critically — the conflict surface with `EqualizerService`.

---

## Standard Architecture (the v1 bridge pattern)

The realistic v1 pattern, validated by AirConnect/AirSonos prior art, is **push-in / pull-out**:

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                            SwiftUI Layer                                 │
│  PlayerBar ──► OutputDevicePicker (new) ──► reads PlayerService.output  │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │ user picks "Living Room (Sonos)"
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                  PlayerService (existing, @MainActor @Observable)        │
│   - already owns: queue, playback state, WKWebView control              │
│   - NEW: var activeOutput: AudioOutput { .system, .sonos(SonosDevice) } │
│   - NEW: delegates output-specific concerns to OutputRouter             │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │ play / pause / seek / volume / load
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│              AudioOutputRouter (NEW, @MainActor @Observable)             │
│   Strategy/router: dispatches transport commands to the right backend.  │
│   Owns the active SonosOutputSession when applicable.                   │
└──────────┬─────────────────────────────────────────────────┬────────────┘
           │ output == .system → no-op (current behaviour)   │ output == .sonos
           │                                                  ▼
           │                              ┌───────────────────────────────────┐
           │                              │   SonosOutputSession (NEW)        │
           │                              │   Coordinates the three Sonos     │
           │                              │   subsystems for one active       │
           │                              │   playback session.               │
           │                              └──┬─────────────┬─────────────┬────┘
           │                                 │             │             │
           │                                 ▼             ▼             ▼
           │                       ┌─────────────┐ ┌────────────┐ ┌─────────────┐
           │                       │ AudioCapture│ │HTTPRelay   │ │ SonosControl│
           │                       │ Pipeline    │ │Server      │ │ Client      │
           │                       │ (NEW)       │ │ (NEW)      │ │ (NEW)       │
           │                       └──────┬──────┘ └─────┬──────┘ └──────┬──────┘
           │                              │              │               │
           │                       captures              serves          UPnP/SOAP
           │                       WebKit PCM            HTTP audio      to Sonos
           │                              │              │               │
           ▼                              ▼              ▼               ▼
┌────────────────────┐        ┌──────────────────┐ ┌──────────┐ ┌────────────────┐
│ EqualizerService   │ shares │ Core Audio tap   │ │NWListener│ │ URLSession +   │
│ (existing) - owns  │ tap?   │ (WebKit process  │ │on TCP    │ │ Network.fwk    │
│ the WebKit tap     │ ◄────► │ subset)          │ │1400-9999 │ │ (SOAP envelope)│
│ today              │        └──────────────────┘ └──────────┘ └────────────────┘
└────────────────────┘                  ▲                  ▲              ▲
         │                              │                  │              │
         │ post-EQ audio                │ tapped PCM       │ HTTP GET     │ POST /MediaRenderer/...
         ▼                              │                  │              │ SUBSCRIBE event URL
   System Output                        │                  │              │
   (speakers/AirPlay)                   │                  │              │
                                        │                  │              │
                                        │      ┌───────────┴───────────┐  │
                                        │      │   Sonos S1 speaker    │◄─┘
                                        │      │ (192.168.x.y:1400)    │──── NOTIFY events
                                        │      │ pulls /stream.wav     │     (volume, transport)
                                        │      └───────────────────────┘
                                        │                                 │
                                        └─────────── shared LAN ──────────┘

                  ┌─────────────────────────────────────────────────┐
                  │       SonosDiscoveryService (NEW)               │
                  │  Independent — runs on app start regardless of  │
                  │  whether the user ever picks a Sonos output.    │
                  │  SSDP M-SEARCH on 239.255.255.250:1900 +        │
                  │  passive NOTIFY listener, builds device roster. │
                  └─────────────────────────────────────────────────┘
                                       │ feeds
                                       ▼
                          AudioOutputRouter.availableOutputs
                                       │ feeds
                                       ▼
                              OutputDevicePicker UI
```

### What's already in place (do not rebuild)

| Existing piece | What it gives the Sonos work |
|----------------|------------------------------|
| `WKWebView` + `PlayerService` | Audio source, transport control, queue. No change needed for Sonos. |
| `ProcessTapHelper` (macOS 14.2+ Core Audio tap on WebKit subprocess) | **Proves the capture path works in this exact app.** The Sonos pipeline reuses the same tap technique — and likely the same physical tap. |
| `EqualizerAudioEngine` (real-time HAL I/O proc on aggregate device) | Reference implementation of "tap → DSP → output" on the audio thread. Sonos pipeline is "tap → encode → HTTP buffer". |
| `DiagnosticsLogger`, `@MainActor @Observable` patterns | Direct fit. New services follow the same shape. |
| `Network` framework (Apple) | Used today for nothing audio-related, but available for `NWListener` (HTTP server) and `NWConnection` (SSDP UDP). No new dep needed. |
| `URLSession` | Used for YT Music API. Reusable for SOAP POSTs and event SUBSCRIBE/UNSUBSCRIBE — these are just HTTP. |

### Component Responsibilities (new components only)

| Component | Responsibility | Owns | Does NOT own |
|-----------|---------------|------|--------------|
| **AudioOutputRouter** | Single source of truth for "where does audio go right now?". Strategy dispatcher between `.system` (existing path) and `.sonos(...)`. Holds at most one active `SonosOutputSession`. | `activeOutput`, `availableOutputs` (merges discovery + system), routing decisions. | Audio capture, network IO, UPnP commands. |
| **SonosDiscoveryService** | Find Sonos devices on the LAN. SSDP M-SEARCH + passive NOTIFY listener. Parse device descriptions. Maintain a live roster with availability heartbeat. | `discoveredDevices: [SonosDevice]`, SSDP socket, parsed `device.xml` per device. | Audio, transport control, eventing of state variables. |
| **SonosControlClient** | Issue UPnP/SOAP commands to a single device: `SetAVTransportURI`, `Play`, `Pause`, `Stop`, `Seek`, `SetVolume`, `GetPositionInfo`. Per-action `URLSession` POSTs with the SOAP envelope. | SOAP envelope construction, response parsing, error mapping. | Discovery, audio bytes, eventing. |
| **SonosEventSubscriber** | Subscribe to `AVTransport` and `RenderingControl` events on a device via UPnP GENA `SUBSCRIBE`. Run a tiny `NWListener` HTTP server on a chosen port to receive `NOTIFY` callbacks. Renew subscriptions before the timeout. Parse `LastChange` XML and surface deltas. | Subscription IDs, callback URL, `NOTIFY` listener, timeout renewals. | Outbound commands, audio. |
| **AudioCapturePipeline** | Get PCM audio out of the WebKit process tap and hand it to the encoder. Reuses (or shares) `ProcessTapHelper`. The HAL I/O proc reads from the tap and writes to a thread-safe ring buffer. | Tap setup (or coordination with EQ), ring buffer between RT thread and encode thread. | EQ DSP, network, encoding choice. |
| **AudioEncoder** | Convert tap PCM (typically 48 kHz stereo Float32) into a Sonos-compatible HTTP body. v1 candidate: **uncompressed LPCM in a chunked WAV stream** (no encoder framework dependency, lowest latency, Sonos S1 accepts it per format docs). v2 candidate: AAC via `AudioToolbox` `AudioConverter` if bandwidth becomes an issue. | Format conversion, output framing. | Capture, network, transport. |
| **HTTPRelayServer** | Serve a single HTTP endpoint (`/kaset-stream.wav` or similar) on a LAN-reachable port using `NWListener`. Stream encoded audio chunks as the client (Sonos) reads them. Handle one or more connections, support range/seek headers iff needed (Sonos prefers no-seek live streams). | TCP listener, response framing, client connection lifecycle. | Encoding, capture. |
| **SonosOutputSession** | Per-Sonos-output coordinator. Wires `AudioCapturePipeline → AudioEncoder → HTTPRelayServer` and uses `SonosControlClient` to point the speaker at the relay's URL. Drives transport commands from `PlayerService`. Listens to `SonosEventSubscriber` for external state changes (Sonos app changes volume) and reflects them back into `PlayerService`. | Session lifecycle, the chosen device, the active stream URL. | The constituent subsystems' internals. |

---

## Recommended Project Structure

```
Sources/Kaset/Services/
├── Audio/                                  # existing — touched only at coordination edges
│   ├── EqualizerService.swift              # existing
│   ├── EqualizerAudioEngine.swift          # existing
│   ├── ProcessTapHelper.swift              # existing — REFACTOR to be sharable (see below)
│   └── BiquadFilter.swift                  # existing
├── Player/                                  # existing
│   └── PlayerService.swift                 # existing — extended via PlayerService+Output.swift
├── Player/PlayerService+Output.swift        # NEW — adds activeOutput, output-aware play/pause/volume forwarding
└── Sonos/                                   # NEW — the entire milestone lives here
    ├── SonosDevice.swift                    # Model: name, UDN, IP, services, icon URL
    ├── SonosError.swift                     # Typed errors mirroring YTMusicError style
    ├── Discovery/
    │   ├── SonosDiscoveryService.swift      # @MainActor @Observable singleton
    │   ├── SSDPClient.swift                 # M-SEARCH + passive NOTIFY listener (UDP/multicast)
    │   └── DeviceDescriptionParser.swift    # GET /xml/device_description.xml → SonosDevice
    ├── Control/
    │   ├── SonosControlClient.swift         # Per-device SOAP client
    │   ├── SOAPEnvelope.swift               # XML builder (small, hand-rolled)
    │   ├── SOAPResponseParser.swift         # XML parser using XMLParser
    │   └── UPnPActions.swift                # Typed wrappers: SetAVTransportURI, Play, Seek, ...
    ├── Eventing/
    │   ├── SonosEventSubscriber.swift       # SUBSCRIBE/UNSUBSCRIBE + renewal
    │   ├── EventListener.swift              # NWListener that handles inbound NOTIFY HTTP requests
    │   └── LastChangeParser.swift           # Parse the inner XML inside <LastChange>
    ├── Audio/
    │   ├── AudioCapturePipeline.swift       # Owns or shares the WebKit tap; ring buffer to encoder
    │   ├── AudioEncoder.swift               # Protocol; PCMWavEncoder is v1 default
    │   ├── PCMWavEncoder.swift              # Streaming WAV header + raw PCM frames
    │   └── AudioRingBuffer.swift            # Lock-free single-producer single-consumer ring
    ├── Relay/
    │   ├── HTTPRelayServer.swift            # NWListener-based; serves the live audio body
    │   └── StreamURLProvider.swift          # Builds the http://<mac-ip>:<port>/<token>.wav URL
    ├── Routing/
    │   ├── AudioOutputRouter.swift          # @MainActor @Observable; the strategy dispatcher
    │   ├── AudioOutput.swift                # enum AudioOutput { case system; case sonos(SonosDevice) }
    │   └── SonosOutputSession.swift         # Per-active-Sonos coordinator
    └── README.md                            # Subsystem overview, links to ADRs

Sources/Kaset/Views/
└── OutputDevicePicker.swift                 # NEW — Apple Music-style speaker picker in the player bar

Sources/Kaset/ViewModels/
└── OutputDevicePickerViewModel.swift        # NEW — reads AudioOutputRouter, drives picker UI

Tests/KasetTests/Sonos/
├── Fixtures/                                # Captured SOAP requests + LastChange events
│   ├── SetAVTransportURI.xml
│   ├── LastChange-AVTransport.xml
│   └── device_description.xml
├── SOAPEnvelopeTests.swift
├── LastChangeParserTests.swift
├── DeviceDescriptionParserTests.swift
└── AudioRingBufferTests.swift               # The thread-safety test that actually matters
```

### Structure Rationale

- **Everything new lives under `Services/Sonos/`** so the milestone has a clean boundary you can `git mv` or rip out wholesale if the spike kills it.
- **Subdirectories mirror the conceptual subsystems** (Discovery / Control / Eventing / Audio / Relay / Routing). Each is independently testable; each maps 1:1 to a phase in the build order below.
- **`Routing/` is at the top of the dependency graph inside `Sonos/`** — it's the only thing `PlayerService` talks to, and it's what the UI binds to. Everything else is leaf-side.
- **`Audio/` inside `Sonos/` is separate from the top-level `Services/Audio/`** to avoid colliding with the existing EQ. The existing folder keeps its current scope (system-output DSP); the new folder is "audio for Sonos". The shared `ProcessTapHelper` will need to migrate to a neutral home or expose a coordinator — see Conflict Surface below.
- **Tests mirror service folders** with a dedicated `Fixtures/` for captured SOAP/event XML so tests don't need a real Sonos.

---

## Architectural Patterns

### Pattern 1: Strategy/Router for Output

**What:** `AudioOutputRouter` owns an `enum AudioOutput { case system; case sonos(SonosDevice) }` and forwards transport calls to the right backend. `PlayerService` does not know about Sonos directly — it asks the router.

**When to use:** Any time you want to add new output types later (Chromecast, Bluetooth speaker as virtual device, AirPlay 2 group...) without reopening `PlayerService`.

**Trade-offs:** One extra hop. Slightly more code than putting an `if isUsingSonos` inside `PlayerService`. Worth it because `PlayerService.swift` is already 445 lines + 7 extension files; mixing in network + UPnP would push it past the 1500-line SwiftLint hard cap.

**Example:**
```swift
@MainActor
@Observable
final class AudioOutputRouter {
    static let shared = AudioOutputRouter()

    enum Output: Equatable, Hashable {
        case system
        case sonos(SonosDevice)
    }

    private(set) var activeOutput: Output = .system
    private(set) var availableOutputs: [Output] = [.system]

    private var sonosSession: SonosOutputSession?

    func select(_ output: Output) async throws {
        try await self.tearDownCurrentIfNeeded()
        switch output {
        case .system:
            // Existing path. Nothing to spin up.
            break
        case .sonos(let device):
            let session = SonosOutputSession(device: device)
            try await session.start()
            self.sonosSession = session
        }
        self.activeOutput = output
    }

    func setVolume(_ value: Double) async {
        switch self.activeOutput {
        case .system:
            // PlayerService keeps doing what it does today (WebView volume).
            break
        case .sonos:
            try? await self.sonosSession?.setVolume(value)
        }
    }
}
```

### Pattern 2: Capture-once, fan-out (resolves the EQ conflict)

**What:** Refactor the WebKit process tap so it can be created once and have multiple consumers (EQ DSP, Sonos encoder). Today `EqualizerService` owns `ProcessTapHelper` exclusively. Move tap ownership to a neutral `WebKitAudioTapCoordinator` that vends PCM frames to N subscribers.

**When to use:** Any time more than one subsystem wants the same captured audio. Trying to create a second tap on the same WebKit PIDs is the path to subtle Core Audio bugs (and contradicts how `mutedWhenTapped` is meant to work — only one consumer is supposed to drive the muted output).

**Trade-offs:** Mid-flight refactor of a working subsystem. Adds an actor or queue between RT thread and consumers. Without it: real risk of either silencing WebKit twice, or silently breaking the EQ when Sonos starts.

**Example:**
```swift
// New:
final class WebKitAudioTapCoordinator {
    static let shared = WebKitAudioTapCoordinator()

    private let tapHelper = ProcessTapHelper()
    private var consumers: [UUID: (UnsafePointer<AudioBufferList>, Int) -> Void] = [:]
    // ... ring-buffer fan-out on the audio thread

    func addConsumer(_ block: @escaping ...) -> UUID
    func removeConsumer(_ id: UUID)
    var streamFormat: AudioStreamBasicDescription? { tapHelper.tapStreamDescription }
}

// EqualizerEngine becomes a consumer:
let id = WebKitAudioTapCoordinator.shared.addConsumer(self.renderEQ)

// SonosOutputSession becomes another consumer:
let id = WebKitAudioTapCoordinator.shared.addConsumer(self.encodeAndQueue)
```

### Pattern 3: Push-in / Pull-out audio bridge

**What:** Audio capture pushes PCM frames into a bounded ring buffer at the tap rate (~48 kHz). HTTP server reads from the same ring buffer at whatever rate the Sonos client requests. The two sides are decoupled by the buffer's depth — typically 2-5 seconds of audio.

**When to use:** Any time you bridge a real-time push source (Core Audio I/O proc) to a TCP-paced consumer (HTTP). This is exactly the pattern AirConnect uses for AirPlay→UPnP.

**Trade-offs:** Buffer adds latency. Too small and Sonos underruns (audio glitches). Too large and play/pause feels sluggish. AirConnect literature suggests 1-3 s is the sweet spot for Sonos; the spike must measure end-to-end.

### Pattern 4: Per-session lifecycle

**What:** `SonosOutputSession` is created when the user selects a Sonos output and destroyed when they switch away. It owns the encoder, the HTTP relay, the active control client, and the event subscription for that one device. Switching to a different Sonos = tear down old session, build new one.

**When to use:** Stateful subsystems that have setup/teardown costs (TCP listener, UPnP subscription) and shouldn't outlive the user's choice.

**Trade-offs:** Switching speakers has a brief gap (new TCP listener, new SOAP `SetAVTransportURI`). Acceptable for v1 — users switch outputs rarely.

---

## Data Flow

### Flow 1: User picks a Sonos speaker as output

```
User taps speaker icon in PlayerBar
        │
        ▼
OutputDevicePicker (View)
  reads availableOutputs from AudioOutputRouter
  shows: "MacBook" | "Living Room (Sonos)" | "Kitchen (Sonos)"
        │
        ▼
User selects "Living Room (Sonos)"
        │
        ▼
AudioOutputRouter.select(.sonos(livingRoom))
  ├─► tear down previous session if any
  ├─► create SonosOutputSession(device: livingRoom)
  └─► session.start():
        ├─► AudioCapturePipeline.start()  (or attach as consumer to WebKitAudioTapCoordinator)
        ├─► AudioEncoder.start()           (PCM Float32 → 16-bit LPCM, prebuild WAV header)
        ├─► HTTPRelayServer.start()        (NWListener on port N, e.g. 8088, route /kaset-stream.wav)
        ├─► (optional v2) SonosEventSubscriber.subscribe(device: livingRoom)
        └─► SonosControlClient.setAVTransportURI(
              "http://192.168.1.42:8088/kaset-stream.wav"
            )
            ↳ Sonos POSTs back: HTTP 200 OK
        └─► SonosControlClient.play()
              ↳ Sonos opens HTTP GET to relay
              ↳ HTTPRelayServer accepts connection,
                writes WAV header, then streams PCM chunks from ring buffer
              ↳ Audio comes out of Living Room speakers ~1-2 s later
        │
        ▼
PlayerService.activeOutput now == .sonos(livingRoom)
PlayerBar reflects new output, volume slider now controls Sonos volume
```

### Flow 2: User hits Pause while Sonos output is active

```
User clicks pause in PlayerBar
        │
        ▼
PlayerService.pause()
  ├─► (existing) tells WKWebView JavaScript to pause YouTube player
  │       ↳ WebView stops emitting audio → tap goes silent → ring buffer drains
  │       ↳ Sonos' HTTP fetch starts underrunning within ~1 buffer-depth seconds
  │
  └─► (new) AudioOutputRouter.notifyTransportChange(.paused)
        └─► SonosOutputSession.pause()
              └─► SonosControlClient.pause()  (UPnP AVTransport#Pause)
                    ↳ Sonos stops fetching cleanly, holds last frame
        │
        ▼
PlayerBar shows paused state immediately;
Sonos LED indicates pause within ~200ms.
```

**Why both:** Telling Sonos to pause via UPnP is the responsive path. Letting the buffer drain is the fallback. Doing only one is fragile: if you only stop emitting audio, Sonos buffers and keeps playing for 1-3 s; if you only send `Pause` SOAP, the relay keeps streaming and the buffer overflows.

### Flow 3: Track ends naturally, advance to next

```
WKWebView fires "ended" event → PlayerService.handleTrackEnded()
  ├─► (existing) determine next track from queue + repeat/shuffle rules
  ├─► (existing) tell WKWebView to load next videoId
  │       ↳ ~500ms gap during which the tap is silent
  │
  └─► (new) decision: leave the relay open or restart?
        ├─► OPTION A (simple): leave it open. Buffer underruns briefly,
        │   Sonos may glitch, then audio resumes.
        └─► OPTION B (clean): SonosControlClient.stop(); on next track,
              SetAVTransportURI(same URL); play(). Adds a clean gap, no glitch.
              SPIKE MUST DECIDE.
```

### Flow 4: External state change (user changes volume on Sonos app)

```
Sonos device → POST NOTIFY /events/<sid> HTTP/1.1 → EventListener
  Body: <e:propertyset>...<LastChange>... &lt;Volume val="42"/&gt; ...</LastChange>...
        │
        ▼
EventListener (NWListener for inbound NOTIFY)
  hands raw body to LastChangeParser
        │
        ▼
LastChangeParser yields VolumeChanged(channel: "Master", value: 42)
        │
        ▼
SonosOutputSession.handleEvent(.volume(42))
        │
        ▼
PlayerService.volume = 0.42  (only when activeOutput == .sonos)
        │
        ▼
PlayerBar volume slider re-renders to 42% — no user action.
```

The event subscriber is **the only way** to learn about state changes from elsewhere (the Sonos app, voice assistant, hardware buttons on the speaker, another household member's phone). Polling `GetVolume` instead is possible but wasteful and laggy.

### Flow 5: Discovery (runs in background regardless of active output)

```
App launch → SonosDiscoveryService.start()
  ├─► open SSDP socket on 239.255.255.250:1900 (UDP, multicast)
  ├─► send M-SEARCH for ST: urn:schemas-upnp-org:device:ZonePlayer:1
  ├─► listen for unicast SSDP responses (LOCATION header → device.xml URL)
  ├─► concurrently listen for passive NOTIFY ssdp:alive announcements
  └─► for each new IP:
        └─► URLSession.GET <LOCATION>
              └─► DeviceDescriptionParser → SonosDevice(name, UDN, services, icon)
                    └─► append to discoveredDevices
                          └─► AudioOutputRouter.availableOutputs recomputes
                                └─► OutputDevicePicker UI updates
```

Discovery is **purely additive** — the existing PlayerService never sees it unless the user actually picks a Sonos.

---

## Suggested Build Order

The spike phase is its own thing — see "Spike vs build" below. The build order assumes the spike validated the four bets in `PROJECT.md`.

### Phase Build-1: Discovery (independently testable, no Sonos audio at all)

**Build:** `SonosDevice`, `SSDPClient`, `DeviceDescriptionParser`, `SonosDiscoveryService`.

**Proof:** App boots, `SonosDiscoveryService.discoveredDevices` populates with the user's actual Sonos speakers within ~3 s. Logged via `DiagnosticsLogger.sonos` (new subsystem). No UI yet. Validate with the API explorer pattern — extend `Sources/APIExplorer/main.swift` with a `sonos discover` command.

**Why first:** Zero coupling to anything else. Pure I/O. No audio risk. Failures here only block UI population, not playback. SSDP on Apple's `Network` framework has known quirks (multicast/unicast mismatch — see Sources) so it's the riskiest non-audio component and worth proving early.

### Phase Build-2: Control commands (still no audio)

**Build:** `SOAPEnvelope`, `SOAPResponseParser`, `SonosControlClient`, typed `UPnPActions`.

**Proof:** A test that picks a discovered device and successfully calls `SetVolume`, `GetVolume`, and `Play`/`Pause` against a known stream URL (use any public internet radio MP3). The Sonos audibly responds. Again exposed via API explorer: `swift run api-explorer sonos play <ip> <streamURL>`.

**Why second:** Discovery returns the device descriptor with the per-service control URLs. Control commands are pure HTTP/XML — no audio capture, no relay. If this fails, the entire milestone fails, so prove it cheap.

### Phase Build-3: Audio capture refactor (no Sonos involvement)

**Build:** `WebKitAudioTapCoordinator` extracted from current `ProcessTapHelper` ownership. Migrate `EqualizerAudioEngine` to be a consumer of the coordinator instead of owning the tap directly. Add a no-op second consumer (for tests) that just counts frames.

**Proof:** EQ continues to work bit-identically with the refactor. Frame-counter consumer demonstrates that two consumers can read the same tap without distortion or muting issues.

**Why third — and critically, before Sonos audio:** This is the highest-risk refactor in the milestone. It touches working code in production. Doing it as its own step, with the EQ as the only consumer that needs to keep behaving, lets you ship/revert independently. **Doing it in the same change as the new Sonos audio work makes both untestable.**

### Phase Build-4: Audio capture pipeline + encoder (still no network)

**Build:** `AudioCapturePipeline`, `AudioRingBuffer`, `AudioEncoder` protocol, `PCMWavEncoder`.

**Proof:** Hook a consumer to the tap coordinator. Encode 30 s of playback into a `.wav` file on disk. Open the file in QuickTime — it sounds correct, no clicks, no drift. This is the encoding choke-point the spike already partly answered, but here you confirm the production code path produces a valid WAV.

**Why fourth:** Independently runnable as a test (write to file). No HTTP yet. Lets you nail the format negotiation (sample rate from tap → 16-bit LPCM, byte order, header size) without TCP variables in the way.

### Phase Build-5: HTTP relay server (with prerecorded audio)

**Build:** `HTTPRelayServer`, `StreamURLProvider`. Test with a static WAV file first, then with the real ring buffer.

**Proof:** Curl `http://<mac.local>:8088/kaset-stream.wav` from the same Mac, then from a phone on the same Wi-Fi. Audio plays in QuickTime. Sonos S1's `SetAVTransportURI` against this URL works (test by calling `SonosControlClient.setAVTransportURI` from Phase Build-2's tooling).

**Why fifth:** This is the moment audio first leaves the Mac. Failure modes are network-shaped (firewall, sandbox, Bonjour, port collision) and have nothing to do with audio quality. Isolating them here keeps the bug surface narrow.

### Phase Build-6: End-to-end glue (`SonosOutputSession` + `AudioOutputRouter`)

**Build:** `AudioOutput` enum, `AudioOutputRouter` (start with one consumer), `SonosOutputSession`, minimum `OutputDevicePicker` view, `PlayerService+Output.swift` extension.

**Proof:** Real user flow: start playing a song with system output → tap speaker icon → pick Sonos → audio transitions to the Sonos within target latency. Tap pause → audio stops. Tap play → audio resumes. Tap next → next track plays.

**Why sixth:** Everything below this is a building block. This is the first end-to-end commit. Critical-path bug surface = "the integration", not the parts.

### Phase Build-7: Eventing (state sync from Sonos → Kaset)

**Build:** `EventListener` (NWListener for inbound NOTIFY), `SonosEventSubscriber`, `LastChangeParser`. Wire volume changes back into `PlayerService.volume`.

**Proof:** Open the Sonos S1 app on a phone. Change volume. PlayerBar slider in Kaset moves to match within ~500 ms. Same for play/pause if changed externally.

**Why seventh:** Functionally optional for v1 (Kaset can be the only controller and never need to learn about external changes). Worth it for polish, but not blocking. Implementing late means there's a working product before this lands; implementing early couples too much.

### Phase Build-8: Polish

- Robust error UX (Sonos went offline mid-playback, network changed, port already in use, etc.)
- Persistence of last-used output across app restarts
- AppleScript `tell application "Kaset" to set output to "Living Room"`
- `EqualizerService` interaction polish: when output is Sonos, the EQ's effect on system audio is irrelevant; either show that in the EQ UI or apply the EQ DSP to the Sonos pipeline instead (design decision deferred — see Open Questions)
- `MediaRemote` / Now Playing integration so the Mac's lock screen reflects Sonos transport
- ADR documenting the WebKitAudioTapCoordinator refactor

### Build dependency graph

```
Build-1 Discovery ──┐
                    ├──► Build-6 End-to-end ──► Build-7 Eventing ──► Build-8 Polish
Build-2 Control ────┤
                    │
Build-3 Tap refactor ──► Build-4 Capture+encode ──► Build-5 HTTP relay ──┘
```

**Parallelizable:** Build-1, Build-2, Build-3 are independent and can be done in any order or in parallel. Build-4 needs Build-3. Build-5 needs Build-4 only for live audio testing (static file works without it). Build-6 needs everything before it.

---

## Spike vs Build (do not conflate)

`PROJECT.md` correctly demands a spike before committing to a build. The architecture above describes the **build phase**. The spike is much smaller and answers four binary questions. Its minimum proof set:

| Spike question | Minimum proof | Discardable code? |
|----------------|---------------|-------------------|
| 1. Can we capture WebKit audio with mute-tapped semantics while EQ is also active? | Two `print`s of frame counts — one from the EQ engine, one from a second tap or shared consumer. Both increment. | Yes — throwaway. |
| 2. Will Sonos S1 fetch and play HTTP-served LPCM? | A minimum NWListener that serves a static `.wav` + a single hand-built SOAP `SetAVTransportURI` POST. Sound comes out of the Sonos. | Yes — but the relay code is close to production-shaped already. |
| 3. Can we discover and SOAP-control with no third-party deps using only `URLSession` + `Network`? | One M-SEARCH that prints the device's IP. One SOAP `SetVolume` that audibly works. | Yes — but `SOAPEnvelope` is reusable. |
| 4. Is end-to-end latency < 2 s? | Stopwatch from "click play in Kaset" to "first audible frame from Sonos". | Yes — measurement script only. |

**The spike does NOT need to:** integrate with `PlayerService`, build the strategy router, do eventing, parse `LastChange`, or have any UI. If the spike answers all four "yes", Build phases 1-8 begin against the architecture above. If any answer is "no", the milestone re-scopes per `PROJECT.md`.

---

## Conflict Surface (what could break existing code)

### Conflict 1: Two consumers of the WebKit process tap

**Risk:** HIGH. `EqualizerService` today creates a tap with `mutedWhenTapped: true` and renders post-EQ audio to system output. If `SonosOutputSession` independently creates a second tap on the same WebKit PIDs, behaviour is undefined: Apple's docs do not guarantee multiple taps with `mutedWhenTapped` semantics on the same process compose cleanly, and at minimum we'd be double-muting WebKit.

**Mitigation:** Build-3's `WebKitAudioTapCoordinator` refactor is **mandatory before Build-4 (Sonos audio)** lands. Single tap, multi-consumer fan-out. The EQ consumes for DSP-to-system-output. The Sonos session consumes for encode-to-relay.

**Detection:** If you skip the refactor, the fastest symptom is that turning on Sonos either silences the EQ (its tap was destroyed when Sonos created its tap) or gives the Sonos no audio (Sonos' tap was rejected because the EQ's tap is exclusive). Either way, broken.

### Conflict 2: EQ DSP doesn't reach Sonos by default

**Risk:** MEDIUM. The current EQ pipeline is `WebKit tap → DSP → system output`. If the user has EQ on and then switches to Sonos, the Sonos receives the **pre-EQ** audio (because the Sonos consumer reads the same tap PCM, not the EQ's output node).

**Mitigation:** Two acceptable answers (decide in Build-8 polish):
- (a) "EQ is system-output-only" — disable EQ UI when Sonos is active, document the limitation. Cheap. Honest.
- (b) "EQ applies on Sonos too" — interpose a second `EqualizerAudioEngine` instance in the Sonos pipeline reading from the same tap and writing to the encoder. More code, more CPU, but matches user expectation.

The spike should at least confirm option (b) is *possible* (it is — biquads are stateless across instances).

### Conflict 3: System output keeps playing while Sonos plays

**Risk:** HIGH for UX. WebKit's WKWebView is still emitting audio that the EQ's aggregate device routes to system output, even when the user picked Sonos. The user hears their music from both Mac and Sonos simultaneously.

**Mitigation:** When `activeOutput == .sonos`, the system-output path must be silenced. Two options:
- (a) Tell the EQ engine to stop driving system output (it has a `stop()` already).
- (b) Mute WebKit's effective output (which `mutedWhenTapped` already does — but only if a tap is active).

Option (a) is cleanest: when Sonos is selected, `AudioOutputRouter` tells `EqualizerService` to enter a "muted, Sonos has output" mode. When user switches back to system, EQ resumes normal operation. This needs a small new entry point on `EqualizerService`.

### Conflict 4: PlayerService volume vs Sonos volume

**Risk:** LOW but visible. Today `PlayerService.volume` controls WKWebView volume (0.0-1.0). On Sonos, volume is a UPnP `RenderingControl` value (0-100). The slider should map to whichever is active.

**Mitigation:** `PlayerService.volume` becomes a computed property delegating to the router. Setting it forwards to either the WebView (system output) or `SonosControlClient.setVolume` (Sonos output). Reading it returns whichever the router last knew. The event subscriber updates the value when Sonos changes externally.

### Conflict 5: App sandbox + Info.plist

**Risk:** MEDIUM. The current entitlements / Info.plist allow audio + screen capture for the EQ. Sonos adds:
- **Inbound TCP listening** on a high port → needs `com.apple.security.network.server` in `Kaset.entitlements`.
- **Multicast UDP** for SSDP → may need `com.apple.developer.networking.multicast` (a request-only entitlement, granted automatically for unsandboxed apps but explicit for sandboxed).
- Already-granted: outbound network, screen recording (which doubles as Core Audio tap permission per the existing comment in `ProcessTapHelper`).

**Detection:** First Build-1 SSDP test will fail silently if multicast isn't allowed. First Build-5 NWListener will fail on bind if the server entitlement is missing.

---

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Sonos S1 (UPnP/SOAP) | Outbound HTTP POST to `:1400/MediaRenderer/AVTransport/Control` and `:1400/MediaRenderer/RenderingControl/Control`; outbound HTTP SUBSCRIBE for events; **inbound** HTTP NOTIFY callbacks. | S1 is locked at firmware. Don't probe S2-only endpoints. AVTransport is shared with audio-CD-era UPnP, well-documented. |
| Sonos discovery (SSDP) | UDP multicast to 239.255.255.250:1900; M-SEARCH for `urn:schemas-upnp-org:device:ZonePlayer:1`; listen for unicast responses + passive `ssdp:alive` NOTIFYs. | Apple's `Network` framework has known issues with the multicast-out / unicast-in pattern. May need raw `Darwin` socket. Confirm in spike. |
| YouTube Music (existing) | Unchanged. | Audio source. Sonos is downstream. |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| PlayerService ↔ AudioOutputRouter | Direct method calls, `@MainActor`. PlayerService notifies router on transport changes; router can update PlayerService volume from external Sonos events. | Two-way, but each direction has a clear owner. PlayerService is the "what should play" authority; router is the "where it goes" authority. |
| AudioOutputRouter ↔ SonosOutputSession | 1:1 ownership while session is active. Router holds the strong reference; tearing down the session is the router's responsibility. | Session must clean up tap consumer, listener, subscription before router replaces it. |
| SonosOutputSession ↔ AudioCapturePipeline | Pipeline pushes PCM into a ring buffer; session reads. | Real-time → main-actor handoff via the ring buffer. The buffer is the only shared state. |
| SonosOutputSession ↔ HTTPRelayServer | Session starts/stops the listener; the listener pulls bytes from the ring buffer via the encoder. | Encoder sits between buffer and listener; the listener does not know about audio formats. |
| WebKitAudioTapCoordinator ↔ EqualizerEngine | Engine is a consumer subscribed to PCM frames. | Refactor target. Engine no longer owns `ProcessTapHelper`. |
| EqualizerService ↔ AudioOutputRouter | Router asks EQ to "go quiet, Sonos has output" when output flips; EQ resumes when output flips back. | New, small method on `EqualizerService`. Decoupled by the router so EQ doesn't import any Sonos types. |
| SonosDiscoveryService → AudioOutputRouter | One-way notification: "device list changed". | Router observes the discovery service; not the other way. |
| OutputDevicePicker (View) → AudioOutputRouter | Reads `availableOutputs`, calls `select(_:)`. | Standard View → @Observable service flow already used everywhere in Kaset. |

---

## Anti-Patterns (specific to this milestone)

### Anti-Pattern 1: Putting Sonos logic directly inside PlayerService

**What people do:** Add `if isSonosActive { ... }` branches throughout `PlayerService.swift` and its 7 extensions.

**Why it's wrong:** PlayerService is already at the upper edge of comfortable file size (445 lines + 7 extensions). Sonos is a multi-thousand-line subsystem. Mixing them makes both untestable and pushes PlayerService past SwiftLint's 1500-line cap. It also couples a domain (YouTube playback control) to an unrelated domain (LAN audio bridging).

**Do this instead:** `AudioOutputRouter` strategy pattern. PlayerService calls `router.pause()`, router decides what that means.

### Anti-Pattern 2: Creating a second Core Audio tap on the same WebKit PIDs

**What people do:** "The EQ has a tap, I'll just create my own for Sonos." Two `AudioHardwareCreateProcessTap` calls on the same processes.

**Why it's wrong:** Behaviour is not specified for two `mutedWhenTapped` taps on the same process. Reports indicate level attenuation, ordering issues, or silent failures.

**Do this instead:** `WebKitAudioTapCoordinator` — single tap, fan-out to N consumers via a thread-safe ring buffer (or an ordered consumer list invoked on the audio thread).

### Anti-Pattern 3: HTTP server using DispatchQueue + BSD sockets

**What people do:** Reach for `socket(AF_INET, ...)` because that's what every UPnP tutorial in C does.

**Why it's wrong:** Project policy forbids `DispatchQueue` and prefers Swift Concurrency. `Network` framework's `NWListener` is the Apple-blessed path and integrates with structured concurrency cleanly. BSD sockets bypass the sandbox network entitlements in surprising ways.

**Do this instead:** `NWListener(using: .tcp, on: .any)` + `NWConnection` per accepted client. Async iteration of received data.

### Anti-Pattern 4: Polling Sonos state instead of subscribing

**What people do:** Every 1 s, call `GetVolume`, `GetTransportInfo`, `GetPositionInfo` to learn what the speaker is doing.

**Why it's wrong:** Wasteful, laggy (~1 s detection), and easy to flood the speaker. Sonos provides UPnP eventing for exactly this purpose — a single SUBSCRIBE gets you push notifications until you UNSUBSCRIBE.

**Do this instead:** GENA `SUBSCRIBE` to `AVTransport/Event` and `RenderingControl/Event`. Run an `NWListener` to receive `NOTIFY` callbacks. Renew subscriptions before timeout. Polling only as a fallback when subscription fails.

### Anti-Pattern 5: Encoding to AAC/MP3 in v1

**What people do:** Reach for `AudioConverter` to encode the tap to AAC because "MP3 streams smaller".

**Why it's wrong:** Adds latency (encoder buffering — typically 2048+ samples), CPU cost, complexity, and potential format-negotiation bugs with Sonos. Sonos S1 explicitly accepts uncompressed WAV/LPCM. LAN bandwidth is not a constraint (48 kHz × 2 ch × 16-bit ≈ 1.5 Mbps; S1 was designed for 320 kbps lossy).

**Do this instead:** v1 ships PCM WAV. Encoding to AAC is a Build-8 polish item if the spike measurements suggest network is a problem (it won't be on a normal home Wi-Fi).

### Anti-Pattern 6: Doing the spike inside `Sources/Kaset/` instead of as a CLI

**What people do:** Add WIP services into the main app target during the spike.

**Why it's wrong:** Couples the spike to app launch, build times, sandbox, signing. Hard to discard cleanly. Pollutes git history.

**Do this instead:** Extend `Sources/APIExplorer/main.swift` (`swift run api-explorer sonos discover`, `sonos play`, etc.) per the existing convention. The spike's throwaway code lives there. Production code migrates into `Services/Sonos/` only after the spike validates the approach.

---

## Scaling Considerations (different "scale" axis here)

This isn't a multi-user system. The relevant axes are:

| Axis | v1 | Future |
|------|----|--------|
| Number of Sonos speakers controlled simultaneously | 1 (single output) | Stereo pair / group / household-wide multi-room: needs N parallel sessions or GroupRenderingControl |
| Audio formats served | LPCM in WAV | + AAC for low-bandwidth networks; + FLAC for lossless (Sonos S1 supports FLAC up to 48 kHz) |
| Discovery network surface | Single LAN, IPv4 multicast | Multi-VLAN setups (Sonos VLAN issue is well-documented) — out of scope for v1 |
| EQ + Sonos coexistence | EQ silenced when Sonos active (Option a) | EQ applies to Sonos pipeline (Option b) |
| Latency target | < 2 s end-to-end | Sub-500 ms requires giving up bridge architecture entirely (or running on dedicated UDP) |

**First bottleneck:** Probably ring buffer sizing tuning. Too small = audible glitches when Wi-Fi hiccups. Too large = sluggish play/pause UX. AirConnect's solution: configurable, default ~1 s. Kaset can ship a sensible default and expose a hidden setting.

**Second bottleneck:** Discovery on noisy networks. Some routers/firewalls drop multicast. Fallback: passive listen for `ssdp:alive` (Sonos sends them every 30 min) + manual IP entry as escape hatch.

---

## Open Questions (decide during build, not now)

1. **Should EQ DSP be applied to the Sonos stream?** (Conflict 2.) Option a (no, EQ is system-only) is cheaper; option b (yes) matches user expectation. Defer to Build-8.
2. **WAV vs raw PCM in HTTP body?** Sonos identifies stream type by URL suffix per the format docs. `.wav` is safest. Confirm in spike.
3. **One persistent ring buffer or new buffer per session start?** New per session is simpler to reason about; persistent allows seamless device switching. Defer.
4. **Where should `WebKitAudioTapCoordinator` live in the source tree?** Currently proposed under `Services/Audio/` (since it's a generic capture facility). Could also live at top level. Defer to Build-3 PR review.

---

## Sources

### Apple / Core Audio
- [Capturing system audio with Core Audio taps — Apple Developer Documentation](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps) — Authoritative, but light on examples.
- [ScreenCaptureKit — Apple Developer Documentation](https://developer.apple.com/documentation/screencapturekit/) — Alternative capture path; less suitable here per the audio-only thread.
- [Is it possible to get only audio from ScreenCaptureKit? — Apple Developer Forums](https://developer.apple.com/forums/thread/718279) — Apple engineer recommends Core Audio taps for audio-only capture.
- [How can I capture audio samples — Apple Developer Forums](https://developer.apple.com/forums/thread/756428)
- [Encoding and decoding audio | Apple Developer Documentation](https://developer.apple.com/documentation/audiotoolbox/encoding-and-decoding-audio)
- [AVAudioEngine | Apple Developer Documentation](https://developer.apple.com/documentation/avfaudio/avaudioengine)

### Reference implementations of audio taps in Swift
- [AudioCap (insidegui) — Sample code for system audio recording](https://github.com/insidegui/AudioCap) — Most useful reference; macOS 14.4+ tap setup.
- [AudioTee — Strongly Typed article](https://stronglytyped.uk/articles/audiotee-capture-system-audio-output-macos)
- [AudioTee on GitHub](https://github.com/makeusabrew/audiotee)
- [Core Audio Tap API gist (sudara)](https://gist.github.com/sudara/34f00efad69a7e8ceafa078ea0f76f6f) — Compact macOS 14.2 example.
- [From Core Audio to LLMs — DEV Community](https://dev.to/yingzhong_xu_20d6f4c5d4ce/from-core-audio-to-llms-native-macos-audio-capture-for-ai-powered-tools-dkg)

### Sonos / UPnP
- [AVTransport service — Sonos API (svrooij)](https://sonos.svrooij.io/services/av-transport) — Best-organised modern reference for Sonos UPnP.
- [RenderingControl — Sonos API](https://sonos.svrooij.io/services/rendering-control)
- [Sonos communication — Sonos API](https://sonos.svrooij.io/sonos-communication)
- [Supported audio formats — Sonos developer docs](https://docs.sonos.com/docs/supported-audio-formats) — Confirms WAV/LPCM acceptance and the URL-suffix-decides-format quirk.
- [Sonos UPnP Interface — Sonos Community](https://en.community.sonos.com/troubleshooting-228999/sonos-upnp-interface-7718/index3.html)
- [SonosControl LastChange example XML](https://github.com/kkalass/SonosControl/blob/master/sonos-control-api-generator/doc/sonos/example-events/AVTransport/LastChange.xml)
- [SoCo events module (Python reference for parsing patterns)](https://docs.python-soco.com/en/latest/api/soco.events.html)
- [AVTransport:1 Service Template UPnP Spec](https://upnp.org/specs/av/UPnP-av-AVTransport-v1-Service.pdf)

### UPnP eventing / SSDP
- [GENA Events — pupnp/pupnp DeepWiki](https://deepwiki.com/pupnp/pupnp/3.3-gena-events)
- [UPnP Device Architecture 2.0 spec](https://openconnectivity.org/upnp-specs/UPnP-arch-DeviceArchitecture-v2.0-20200417.pdf)
- [Notifications: How to detect volume changes — Sonos Community](https://en.community.sonos.com/advanced-setups-229000/notifications-how-to-detect-volume-changes-from-other-client-6748825)
- [Simple Service Discovery Protocol — Wikipedia](https://en.wikipedia.org/wiki/Simple_Service_Discovery_Protocol)
- [SSDP — Wireshark Wiki](https://wiki.wireshark.org/SSDP)
- [SSDP discovery not working — Apple Developer Forums](https://developer.apple.com/forums/thread/680731) — Documents `NWConnectionGroup` multicast/unicast issue.

### Bridge architecture prior art
- [AirConnect — philippe44](https://github.com/philippe44/AirConnect) — The closest production-quality reference for the push-RTP-in / pull-HTTP-out pattern.
- [AirConnect README architecture section](https://github.com/philippe44/AirConnect/blob/master/README.md)
- [AirSonos — original PCM/MP3 issue thread](https://github.com/stephen/airsonos/issues/26)

### Network framework HTTP server
- [Building a server-client application using Network Framework — RDerik](https://rderik.com/blog/building-a-server-client-application-using-apple-s-network-framework/)
- [Intro to Network.framework Servers — Helge Heß](http://www.alwaysrightinstitute.com/network-framework/)
- [MacOS HTTP Listener for a Swift App — Apple Developer Forums](https://developer.apple.com/forums/thread/706865)

### In-tree references (read these too)
- `.planning/codebase/ARCHITECTURE.md` — service-based MVC overview.
- `.planning/codebase/STRUCTURE.md` — directory conventions; `Services/Sonos/` placement.
- `.planning/codebase/CONVENTIONS.md` — `@MainActor @Observable`, `DiagnosticsLogger`, no third-party deps.
- `.planning/PROJECT.md` — milestone scope, four spike bets, the "Mac stays awake" constraint.
- `Sources/Kaset/Services/Audio/ProcessTapHelper.swift` — reference implementation for the audio capture half; refactor target for `WebKitAudioTapCoordinator`.
- `Sources/Kaset/Services/Audio/EqualizerAudioEngine.swift` — reference for HAL I/O proc patterns.
- `Sources/Kaset/Services/Player/PlayerService.swift` — integration point for `activeOutput`.

---

*Architecture research for: Sonos S1 audio integration via Mac-side relay in Kaset (SwiftUI/Swift 6/macOS 26+)*
*Researched: 2026-04-27*
