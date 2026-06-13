# Guitar Tuner

[![CI](https://github.com/Letch49/guitar-tuner/actions/workflows/ci.yml/badge.svg)](https://github.com/Letch49/guitar-tuner/actions/workflows/ci.yml)
[![Security Scan](https://github.com/Letch49/guitar-tuner/actions/workflows/security.yml/badge.svg)](https://github.com/Letch49/guitar-tuner/actions/workflows/security.yml)

Native guitar tuner for macOS. Pluck a string — the app detects which string you're playing and shows a needle for how far off you are (in cents).

Built with Swift + SwiftUI. Pitch detection uses the McLeod Pitch Method (MPM) — a time-domain algorithm based on the Normalized Square Difference Function with parabolic interpolation and string-aware hint detection. YIN/CMNDF is available as a drop-in alternative.

## Features

- **16 tunings** — Standard, Drop, Modal, and Open tunings
- **Visual needle** with a ±5 cent green zone; hold steady and the string is marked as in tune
- **Pin a string** — tap any string on the headstock to lock tuning to it and hear a reference tone; uses harmonic folding so low strings (E2, C#2…) are detected even when the fundamental is quiet
- **Shows actual note** — if the detected pitch doesn't match the target string, the app shows what note you're actually playing
- **Menu bar mode** — a compact popover lives in the macOS menu bar; the status item shows the detected note in real time so you can tune without opening the main window
- **Auto sensitivity** — gain is scaled automatically for lower tunings (Drop B, Drop A, etc.) to compensate for reduced acoustic output of low strings
- **Audio interface support** — tested with Focusrite Scarlett Solo (4th Gen)

## Demo

**Start screen** - pick a tuning and input device, then play a string.

![Start screen](.github/demos/demo-start.png)

**Tuning** - the needle shows how many cents off you are; the active string is highlighted and the app tells you which way to turn the peg.

![Tuning](.github/demos/demo-tune-it.png)

**In tune** - hold the note steady and the string is marked with a checkmark.

![In tune](.github/demos/demo-tuned.png)

## Download

Pre-built DMG on the releases page:

**[github.com/Letch49/guitar-tuner/releases](https://github.com/Letch49/guitar-tuner/releases)**

Open the DMG and drag Guitar Tuner into Applications. The app is ad-hoc signed, so on first launch use **Right click → Open**. Allow microphone access when prompted — macOS requires it for any audio input, including audio interfaces.

## Input devices

| Source | Status |
|--------|--------|
| **Audio interface (Focusrite)** | Tested and works well. Focusrite Scarlett Solo (4th Gen) was the only interface used during development — other brands/models are untested. |
| **Built-in Mac microphone** | Works. For low strings (E2 and below) pin the string on the headstock to improve detection. |
| **Bluetooth / Continuity mic (e.g. iPhone)** | Untested; may work with the same limitations as the built-in mic. |

For serious tuning, a direct guitar → interface connection is strongly recommended.

### Electric guitar + microphone

Tested on an electric guitar played **without an amplifier** (acoustic string output only):

- **With audio interface** — all strings detected reliably, tuning works great.
- **Without interface (built-in mic)** — strings 1–5 work well. String 6 (lowest E/D/C#…) is poorly detected due to the weak acoustic output of an unplugged electric guitar. This is expected behaviour — the fundamental is simply too quiet for the microphone to pick up cleanly.

If you have ideas on how to improve low-string detection without an interface, PRs are welcome.

## Tunings

Notes are listed from **string 6 (lowest)** to **string 1 (highest)**.

### Standard

| Tuning | String 6 → String 1 |
|--------|---------------------|
| Standard | E2 A2 D3 G3 B3 E4 |
| Half Step Down | D#2 G#2 C#3 F#3 A#3 D#4 |
| Full Step Down | D2 G2 C3 F3 A3 D4 |

### Drop

| Tuning | String 6 → String 1 |
|--------|---------------------|
| Drop D | D2 A2 D3 G3 B3 E4 |
| Double Drop D | D2 A2 D3 G3 B3 D4 |
| Drop C# | C#2 G#2 C#3 F#3 A#3 D#4 |
| Drop C | C2 G2 C3 F3 A3 D4 |
| Drop B | B1 F#2 B2 E3 G#3 C#4 |
| Drop A | A1 E2 A2 D3 F#3 B3 |

### Modal

| Tuning | String 6 → String 1 |
|--------|---------------------|
| D Modal (DADGAD) | D2 A2 D3 G3 A3 D4 |
| G Modal | D2 G2 D3 G3 C4 D4 |

### Open

| Tuning | String 6 → String 1 |
|--------|---------------------|
| Open C | C2 G2 C3 G3 C4 E4 |
| Open D | D2 A2 D3 F#3 A3 D4 |
| Open E | E2 B2 E3 G#3 B3 E4 |
| Open G | D2 G2 D3 G3 B3 D4 |
| Open A | E2 A2 E3 A3 C#4 E4 |

## Build from source

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
./build.sh             # build build/GuitarTuner.app
./build.sh install     # build and install to /Applications
./build.sh dmg         # build and create build/GuitarTuner.dmg
```

## Release

Releases are published automatically via GitHub Actions. Push a tag like `v1.0.0` — CI builds the DMG, runs a VirusTotal security scan, and attaches the DMG to the release.

```bash
git tag v1.0.0 && git push origin v1.0.0
```
