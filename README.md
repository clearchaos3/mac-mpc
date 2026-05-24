# mac-mpc

A native macOS sampler / sequencer that recreates the Akai MPC Sample workflow,
driven by a **DJ TechTools Midi Fighter 64** + **Korg nanoKONTROL** (original).

The goal is full feature parity with the MPC Sample: sample editing,
16 sequences × 8 banks, Pad FX / Knob FX / Flex Beat, Chop mode, 16 Levels,
Warp time-stretch, Song mode, Color Compressor — all driven by your existing
controllers.

## Stack

| Layer | Choice |
| --- | --- |
| Language | Swift 6.0+ |
| UI | SwiftUI + AppKit |
| Audio | AVAudioEngine + custom AVAudioUnit nodes |
| MIDI | Core MIDI (notes + CC + SysEx for MF64 LEDs) |
| Decoding | AVAudioFile / AVAudioPCMBuffer |
| Time-stretch | Rubber Band (planned) |

## Module layout

| Module | Role |
| --- | --- |
| `App` | SwiftUI shell, app entry, view wiring |
| `MMAudio` | AVAudioEngine graph: per-pad sampler, FX, sequencer, master bus |
| `MMMidi` | CoreMIDI client + device wrappers (MF64, nanoKONTROL) |
| `MMModels` | Pure value types: Project / Pad / Sample / Sequence |

## Build

```sh
# Library + tests (no Xcode needed)
swift build
swift test

# Bundled .app for normal launch (needed for AppKit/menu-bar features)
./make-app.sh             # debug build
./make-app.sh release     # optimized build
open ./mac-mpc.app
```

## Hardware

- **MIDI Fighter 64** (DJ TechTools): 8×8 arcade-button grid →
  pad triggers + bank scenes; SysEx-driven RGB LED feedback.
- **Korg nanoKONTROL** (original — 9 sliders, 9 knobs, transport, scene buttons):
  K1/K2/K3 + fader + transport + mode buttons.

Plug both in over USB before launching — devices are auto-detected by name.
