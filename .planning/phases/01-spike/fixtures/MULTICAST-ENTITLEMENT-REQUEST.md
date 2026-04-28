# Multicast Entitlement Request — Ready-to-Paste Body

> **Submit this body at <https://developer.apple.com/contact/request/networking-multicast> (login required).**
> **Approval SLA:** 3–5 business days per Apple Developer Forums thread 663271 (worst case 3–10 business days; treat as up to 2 weeks for planning).
> **Scope:** The `com.apple.developer.networking.multicast` entitlement is granted **per-team, not per-app** (Apple Developer Forums threads 663271, 679089). Once approved for the team that owns `com.sertacozercan.Kaset`, all apps signed with that team's Developer ID can use it.

---

## Form fields

### App identifier

```
com.sertacozercan.Kaset
```

### App description

Native macOS YouTube Music client (Swift 6 / SwiftUI, macOS 26+). Distributed
outside the Mac App Store via direct download with Sparkle auto-update.

### App Store URL

> [USER FILL IN]

If the app is listed on the Mac App Store, paste the App Store URL here.

If the app is **not** on the App Store (current Kaset distribution model is
direct download with Sparkle auto-update), use the workaround documented in
Apple Developer Forums thread 679128: paste the project landing page or the
Sparkle appcast URL, and add a one-line note in the use case description
that the app ships outside the App Store with code signing + notarization.
Suggested values:

- Project landing page: `https://github.com/sozercan/kaset`
- Sparkle appcast feed: `https://raw.githubusercontent.com/sozercan/kaset/main/appcast.xml`

### Use case description (free text)

Paste the body below verbatim into the form's free-text field. Adapt phrasing
to actual form labels at submission time — Apple's form is behind login and
exact wording may shift between the date this body was drafted and the date
of submission.

---

> **App:** Kaset (`com.sertacozercan.Kaset`) — a native macOS YouTube Music client.
>
> **Use case:** Kaset uses SSDP (Simple Service Discovery Protocol, RFC-equivalent)
> over IPv4 UDP multicast to `239.255.255.250:1900` to discover Sonos S1-generation
> speakers (Play:1, Play:3, Play:5 Gen 1, Connect, Connect:Amp) on the user's local
> network. Once a Sonos device is discovered, Kaset acts as a UPnP/SOAP control
> point and HTTP audio source, allowing the user to route Kaset's playback to their
> Sonos speakers — a capability the Sonos system itself does not provide for
> YouTube Music on this hardware generation.
>
> **Why no alternative exists:** Sonos S1-generation hardware does not support the
> modern Sonos Cloud Control API. Sonos Music Service / SMAPI partnership is
> reserved for licensed music partners and is not available to indie macOS
> developers. Bonjour/mDNS is not used by Sonos S1 for service advertisement —
> UPnP/SSDP is the only discovery protocol the hardware exposes. Manual IP entry
> is provided as a fallback for users with multicast-restricted networks (VLANs,
> hostile Wi-Fi), but the primary discovery flow requires SSDP.
>
> **Multicast group + port:** `239.255.255.250:1900` (UPnP standard).
>
> **Direction:** Send M-SEARCH multicast (`MAN: "ssdp:discover"` header,
> `ST: urn:schemas-upnp-org:device:ZonePlayer:1`); receive unicast HTTP/1.1
> 200 OK responses from devices.
>
> **Frequency:** Once at app launch and on a periodic refresh (default every
> 60 seconds, with passive listen for `ssdp:alive` NOTIFY broadcasts in
> between).
>
> **Scope:** Local network only. No multicast traffic leaves the user's LAN.
>
> **Distribution:** App ships outside the Mac App Store via direct download with
> Sparkle auto-update; code-signed and notarized with the requesting team's
> Developer ID. (Apple Developer Forums thread 679128 — workaround for the App
> Store URL form field for non-App-Store apps.)

---

## Required key strings (for traceability — do not remove this section)

The following strings MUST appear verbatim in the submitted body so the
spike's verification scripts can confirm the body was drafted from this
template:

- Entitlement key: `com.apple.developer.networking.multicast`
- App identifier: `com.sertacozercan.Kaset`
- Multicast endpoint: `239.255.255.250:1900`
- SSDP search keyword: `ssdp:discover`

## Submission checklist

- [ ] Logged in to Apple Developer portal with the account on the team that
  owns `com.sertacozercan.Kaset`
- [ ] Pasted the use case description body above into the form's free-text field
- [ ] Filled in App Store URL field (or used the no-App-Store workaround)
- [ ] Submitted form — Apple sends a confirmation email within minutes
- [ ] Recorded the submission date for the SPIKE-06 REPORT.md "Multicast
  entitlement status" field

## Privacy / PII guarantee

This document deliberately contains **no** real LAN IPs, no Sonos device USNs,
no Apple Team IDs, no developer email addresses, and no cookies or session
tokens. The only identifier is the public bundle ID `com.sertacozercan.Kaset`,
which already ships in the public `Info.plist`.

If you adapt the body before submission, do not paste your home network's
IP range, your Apple Team ID, or any device USNs into the form — Apple does
not need them to evaluate the request, and storing them in the developer
portal expands the surface for accidental disclosure.
