# Wispr Flow (macOS)

A system-wide, hold-to-talk voice dictation app for your Mac. Hold **⌥Space**,
speak, release — cleaned-up text appears at your cursor in whatever app is
focused. Fully local speech recognition (unlimited, private, offline) with an
optional AI cleanup pass.

Built native (Swift + AppKit menu-bar agent) for Apple Silicon.

## How it works

```
Hold ⌥Space → mic capture (16kHz) → whisper.cpp (local, Metal) → raw transcript
   → cleanup (local filler/format + optional Claude, app-aware) → paste at cursor
```

- **Speech → text:** local `whisper.cpp` server (model stays resident for low
  latency). No audio ever leaves your machine. No caps, no cost.
- **Cleanup:** always a fast local pass (trims fillers, fixes spacing/caps,
  applies your custom dictionary). Optionally a Claude API pass for
  grammar/tone/formatting adapted to the focused app — toggle in the menu bar;
  falls back to the local result on any error so dictation never breaks.
- **Insertion:** clipboard-paste at the cursor, with your clipboard restored.

## Setup (one time)

```bash
cd app
./scripts/setup.sh        # installs whisper.cpp via Homebrew + downloads the model (~148 MB)
./scripts/build-app.sh    # builds WisprFlow.app (unsigned, ad-hoc signed)
```

Then launch and grant two permissions (once):

```bash
open WisprFlow.app
```

1. **Microphone** — prompted on first dictation.
2. **Accessibility** — System Settings ▸ Privacy & Security ▸ **Accessibility** ▸
   add/enable **Wispr Flow**. Needed for the global hotkey and to paste at your
   cursor. Relaunch after granting.

A 🎙 icon appears in the menu bar. **Hold ⌥Space, speak, release.**

## Optional: AI cleanup with Claude

Turn on **AI Cleanup (Claude)** in the menu-bar menu. It needs an API key in the
app's environment, so launch it with the key set:

```bash
ANTHROPIC_API_KEY=sk-ant-... open WisprFlow.app
```

Default cleanup model is `claude-opus-4-8`. For a snappier feel, edit
`cleanupModel` to `claude-haiku-4-5` in the config file (below) — much
faster/cheaper and plenty for cleanup.

## Configuration

`~/Library/Application Support/WisprFlow/config.json`:

| Key | Meaning |
|---|---|
| `modelPath` | ggml Whisper model. Swap for `ggml-small.en.bin` for higher accuracy (slower). |
| `whisperServerPath` | Path to `whisper-server` (default `/opt/homebrew/bin/whisper-server`). |
| `whisperPort` | Localhost port for the resident engine. |
| `aiCleanupEnabled` | Mirror of the menu toggle. |
| `cleanupModel` | Claude model for AI cleanup. |
| `dictionary` | `{ "misheard": "correct" }` — case-insensitive whole-word fixes (names, jargon, acronyms). |

## Project layout

```
app/
├── Package.swift
├── Sources/WisprFlow/
│   ├── main.swift          entry point (menu-bar agent)
│   ├── AppDelegate.swift    pipeline + menu-bar UI + permissions
│   ├── HotkeyMonitor.swift  global ⌥Space hold-to-talk (CGEventTap)
│   ├── AudioRecorder.swift  mic capture, resample to 16kHz mono
│   ├── WavWriter.swift      Float32 → 16-bit PCM WAV
│   ├── WhisperEngine.swift  manages whisper-server, POSTs /inference
│   ├── Cleanup.swift        local cleanup + optional Claude (raw HTTPS)
│   ├── TextInjector.swift   paste at cursor, restore clipboard
│   ├── AppContext.swift     frontmost app name (for cleanup context)
│   └── Settings.swift       config load/save
├── Resources/Info.plist     LSUIElement agent + mic usage string
└── scripts/{setup,build-app}.sh
```

## Notes & limits

- Apple Silicon (M-series). Tested build target macOS 13+.
- Unsigned/ad-hoc — for personal use. Gatekeeper may ask you to confirm the
  first launch (right-click ▸ Open).
- Push-to-talk (hold) is the trigger. Toggle mode is easy to add if you prefer.
- Password fields block synthetic paste (macOS secure input) — by design.
