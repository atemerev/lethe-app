# lethe-app

Starter macOS menu bar project for Lethe installer/service management.

## What is implemented

- Menu bar app (`Sources/LetheApp/main.swift`)
- Core module for Lethe paths and status probing (`Sources/LetheCore`)
- Native non-TTY onboarding/install flow:
  - dedicated AppKit setup window (not `NSAlert`) with tabs:
    - Anthropic
    - OpenRouter
    - OpenAI
  - provider-specific configuration fields in each tab panel
  - model policy:
    - Anthropic + subscription token: fixed defaults, no model prompt
    - Anthropic + API key: main+aux editable together in one dialog
    - OpenRouter: defaults to `openrouter/moonshotai/kimi-k2.5-0127` (main) and `openrouter/google/gemini-3-flash-preview` (aux)
  - auto-installs missing prerequisites via Homebrew (`git`, `uv`, `node`/`npm`)
  - clone/update Lethe repo into `~/.lethe`
  - `uv sync` dependency install
  - `.env` generation in `~/.config/lethe/.env`
  - launchd service setup/load (`com.lethe.agent`)
- LaunchAgent controls (`start`, `stop`) with running/stopped highlighting
- Native uninstall flow for launch agent + install dir
- On first launch, if Lethe is not installed, onboarding starts immediately

Installed-state menu is intentionally minimal: `Start`, `Stop`, `Uninstall`.

## Development

```bash
cd /Users/atemerev/devel/lethe-app
swift build
swift test
swift run LetheApp
```

You can open the package directly in Xcode:

```bash
open /Users/atemerev/devel/lethe-app/Package.swift
```

## Next porting steps

1. Replace dialog-based wizard with a single settings window and validation.
2. Add update flow to native menu when needed.
3. Add install mode controls (container vs native) in app settings.
4. Add code signing/notarization pipeline for distributable `.app`.
