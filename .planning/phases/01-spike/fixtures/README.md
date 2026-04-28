# SPIKE-01 Fixtures

Test assets used by the Phase 1 spike (`Sources/APIExplorer/main.swift`,
`api-explorer sonos …` subcommands).

## Files

| File | Spec | Size | Purpose |
|------|------|------|---------|
| `test-stream.wav` | Stereo, 16-bit PCM, 44.1 kHz, 30s | ~5.1 MB | SPIKE-03 WAV-probe content (per CONTEXT.md D-08 — WAV is tried first) |
| `test-stream.aac` | Stereo, AAC-LC ADTS, 192 kbps, 44.1 kHz, 30s | ~715 KB | SPIKE-03 AAC-probe content |
| `MULTICAST-ENTITLEMENT-REQUEST.md` | Markdown | n/a | Ready-to-paste body for Apple's multicast entitlement request form (filed by user, day 1 of the spike per D-04) |

`file(1)` reports:

- `test-stream.wav` → `RIFF (little-endian) data, WAVE audio, Microsoft PCM, 16 bit, stereo 44100 Hz`
- `test-stream.aac` → `MPEG ADTS, AAC, v4 LC, 44.1 kHz, stereo`

## Source / license

The audio fixtures are **synthetic, generated deterministically with ffmpeg's
built-in lavfi audio sources** — no third-party music sample is involved. Both
files are unambiguously redistributable: there is no underlying recording with
its own licensing, only mathematical signals produced by ffmpeg's signal
generators.

The signal is intentionally varied — a 440 Hz sine tone with periodic emphasis
("beep") on one channel, mixed with pink noise on the other — so the encoders
have non-trivial dynamic and spectral content to compress (rather than a pure
tone, which AAC handles trivially and which would not exercise the encoder
path realistically).

License: Public domain / not subject to copyright (synthetic signal output
from ffmpeg's `sine` and `anoisesrc` filters, both BSD-style licensed code).
Either file may be redistributed under any terms.

## Regeneration

If a future contributor needs to recreate the fixtures (e.g., the binaries
were lost, or specs change), run from the repo root:

```bash
# Requires: ffmpeg (one-time install: `brew install ffmpeg`).
# ffmpeg is NOT a runtime dependency of Kaset — only used at fixture-gen time.

# 1. Synthetic 30s stereo WAV (16-bit PCM, 44.1 kHz, ~5 MB).
#    Channel 0: 440 Hz sine with beep accent every 4 cycles.
#    Channel 1: pink noise at 0.3 amplitude.
ffmpeg -y \
  -f lavfi -i "sine=frequency=440:beep_factor=4:duration=30:sample_rate=44100" \
  -f lavfi -i "anoisesrc=color=pink:duration=30:sample_rate=44100:amplitude=0.3" \
  -filter_complex "[0:a][1:a]amerge=inputs=2,pan=stereo|c0=c0|c1=c1[out]" \
  -map "[out]" \
  -t 30 \
  -acodec pcm_s16le -ar 44100 -ac 2 \
  .planning/phases/01-spike/fixtures/test-stream.wav

# 2. Re-encode the WAV to AAC-LC ADTS at 192 kbps, ~715 KB.
ffmpeg -y -i .planning/phases/01-spike/fixtures/test-stream.wav \
  -t 30 -c:a aac -b:a 192k -ar 44100 -ac 2 -f adts \
  .planning/phases/01-spike/fixtures/test-stream.aac
```

Verify by:

```bash
file .planning/phases/01-spike/fixtures/test-stream.wav
# Expected: WAVE audio, Microsoft PCM, 16 bit, stereo 44100 Hz

file .planning/phases/01-spike/fixtures/test-stream.aac
# Expected: MPEG ADTS, AAC, v4 LC, 44.1 kHz, stereo

stat -f%z .planning/phases/01-spike/fixtures/test-stream.wav
# Expected: > 1000000  (≈ 5.3 MB)

stat -f%z .planning/phases/01-spike/fixtures/test-stream.aac
# Expected: > 100000   (≈ 715 KB)
```

## Why synthetic, not music?

The original plan suggested pulling a royalty-free / public-domain music
sample (CC0 from Free Music Archive or similar). We deliberately use a
synthetic signal instead because:

1. **Reproducibility** — anyone with ffmpeg can regenerate bit-identical files
   without hunting for the original source URL or worrying about it disappearing.
2. **License clarity** — synthetic ffmpeg output has no plausible chain-of-rights
   ambiguity. CC0 / public-domain music samples on the open web are sometimes
   re-uploaded after stripping rights metadata; verifying provenance for a
   committed test asset is friction the spike doesn't need.
3. **Spike purpose** — the spike validates *whether Sonos S1 accepts the bytes*,
   not how the speakers reproduce specific music. A synthetic signal with
   non-trivial dynamic and spectral content is sufficient to:
   - exercise AAC encoder paths realistically (sine + noise has both tonal and
     broadband components),
   - produce audible content the user can confirm on their actual speaker,
   - run for the full ≥30s acceptance window without looping artifacts.

If a future spike iteration needs richer musical content (e.g., to test
Sonos's S1 firmware behavior on dynamic-range-rich orchestral material), the
file can be replaced with a CC0 sample at that time. Until then, the synthetic
signal is the lowest-risk choice for a committed git asset.

## PII guarantee

These fixtures contain:

- No human voice (no voice memos, no spoken-word content).
- No metadata referencing the user, their network, or any device.
- No copyrighted melodies — the 440 Hz sine and pink noise are mathematical
  primitives, not creative works.

Safe to commit to a public repository.
