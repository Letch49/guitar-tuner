# Guitar Tuner

[![CI](https://github.com/Letch49/guitar-tuner/actions/workflows/ci.yml/badge.svg)](https://github.com/Letch49/guitar-tuner/actions/workflows/ci.yml)
[![Security Scan](https://github.com/Letch49/guitar-tuner/actions/workflows/security.yml/badge.svg)](https://github.com/Letch49/guitar-tuner/actions/workflows/security.yml)

A free, open-source guitar tuner for macOS — everything you'd expect from a paid tuner app, without the price tag. Pluck a string, the app detects the note and shows a needle with how far off you are in cents.

Built with Swift + SwiftUI. 

> iOS support is planned.

## Features

- **16 tunings** — Standard, Drop, Modal, and Open
- **Visual needle** — ±5 cent green zone; hold steady and the string is marked as in tune
- **Menu bar mode** — compact popover in the macOS menu bar with real-time note detection
- **Pin a string** — lock detection to one string and hear a reference tone for more precise tuning
- **Reference pitch** — choose A4 from 432 / 440 / 441 / 442 / 443 Hz
- **Audio interface support** — tested with Focusrite Scarlett Solo (4th Gen)

## Demo

**Start screen** — pick a tuning and input device, then play a string.

![Start screen](.github/demos/demo-start.png)

**Tuning** — the needle shows how many cents off you are; the active string is highlighted and the app tells you which way to turn the peg.

![Tuning](.github/demos/demo-tune-it.png)

**In tune** — hold the note steady and the string is marked with a checkmark.

![In tune](.github/demos/demo-tuned.png)

**Settings** — reference pitch, headstock layout, and detection algorithm.

![Settings](.github/demos/demo-settings.png)

## Download

Pre-built DMG on the releases page:

**[github.com/Letch49/guitar-tuner/releases](https://github.com/Letch49/guitar-tuner/releases)**

Open the DMG and drag Guitar Tuner into Applications. The app is ad-hoc signed, so on first launch use **Right click → Open**. Allow microphone access when prompted — macOS requires it for any audio input, including audio interfaces.

## Input devices

| Source | Notes | Test result |
|--------|-------|-------------|
| **Audio interface (Focusrite Scarlett Solo 4th Gen)** | Direct guitar → interface connection. Only this model was tested — other interfaces are untested. | ✅ All strings |
| **Built-in Mac microphone** | Pin a string on the headstock to improve detection of low strings. | ✅ Strings 1–5 · ⚠️ String 6 (weak acoustic output) |
| **Bluetooth / Continuity mic (e.g. iPhone)** | Electric guitar → amplifier → mic. | ✅ All strings |
| **Electric guitar unplugged** | Acoustic output only, no amp. | ✅ Strings 1–5 · ⚠️ String 6 — expected, PRs welcome |

For serious tuning, a direct guitar interface connection is strongly recommended.

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
