# hood wisprflow

A free, **fully-local, unlimited** voice-dictation app for macOS. Hold **⌥Space**,
speak, release → cleaned-up text appears at your cursor in *any* app. On-device
speech recognition (whisper.cpp, Metal) with a live waveform HUD and an optional
Claude cleanup pass. No subscription, no cloud, no caps.

> A hood-built take on Wispr Flow. Native Swift menu-bar app for Apple Silicon.

![status](https://img.shields.io/badge/platform-macOS%2013%2B%20(Apple%20Silicon)-black)

## What it does

```
Hold ⌥Space → mic (16kHz) → whisper.cpp large-v3-turbo (local, Metal)
   → cleanup (local + optional Claude, app-aware) → paste at your cursor
```

- **Unlimited & private** — speech never leaves your Mac. No API needed for the core.
- **Accurate** — runs `large-v3-turbo` (nails technical terms, names, punctuation).
- **Live HUD** — a dark-glass pill with a center-mirrored waveform that reacts to
  your voice, a scanning pulse while transcribing, and a checkmark on success.
- **App-aware cleanup** — optional Claude pass adapts tone to the focused app
  (formal for Mail, casual for Slack, code for a terminal). Falls back to local.
- **Custom dictionary** — force-correct names/jargon the model guesses at.

## Quick start

```bash
git clone https://github.com/nueramator/hood-wisprflow.git
cd hood-wisprflow/app
./scripts/setup.sh        # installs whisper.cpp + downloads a model (Homebrew)
./scripts/build-app.sh    # builds WisprFlow.app (ad-hoc signed)
open WisprFlow.app
```

Grant **Microphone** (prompted) and **Accessibility** (System Settings ▸ Privacy &
Security ▸ Accessibility ▸ enable *Wispr Flow*), relaunch, then **hold ⌥Space**.

Full setup, config, and troubleshooting: **[`app/README.md`](app/README.md)**.
Design deep-dive: **[`docs/wispr-flow-end-to-end.md`](docs/wispr-flow-end-to-end.md)**.

## Optional: AI cleanup

Launch with a key and toggle **AI Cleanup (Claude)** in the menu:

```bash
ANTHROPIC_API_KEY=sk-ant-... open WisprFlow.app
```

## Repo layout

```
app/    the macOS app (Swift/AppKit, SwiftPM) — this is the product
docs/   design research (how Wispr Flow works end to end)
.claude/, .github/, …   the Claude Code dev setup this was built with
```

## Notes & limits

- Apple Silicon, macOS 13+. Unsigned/ad-hoc — Gatekeeper may need a right-click ▸ Open.
- The engine (`large-v3-turbo`) uses ~1.5 GB RAM while transcribing.
- Password fields block synthetic paste (macOS secure input) — by design.

## License

MIT — see [LICENSE](LICENSE).
