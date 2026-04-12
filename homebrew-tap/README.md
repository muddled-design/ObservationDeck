# Homebrew Tap for Observation Deck

Floating macOS dashboard that monitors all active Claude Code sessions in real time.

## Install

```bash
brew tap muddled-design/observation-deck
brew install observation-deck
```

This will build from source and:
1. Install the `.app` bundle
2. Automatically configure Claude Code hooks for real-time status

Xcode 15+ is required to build.

## Launch

```bash
open $(brew --prefix)/opt/observation-deck/ClaudeMonitor.app
```

## Upgrade

```bash
brew upgrade observation-deck
```

## Uninstall

```bash
# Remove hooks from Claude Code settings
$(brew --prefix)/share/observation-deck/install-hooks.sh --uninstall

# Uninstall the app
brew uninstall observation-deck
brew untap muddled-design/observation-deck
```
