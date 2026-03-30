# Homebrew Tap for ClaudeMonitor

Floating macOS dashboard that monitors all active Claude Code sessions in real time.

## Install

```bash
brew tap muddled-design/observation-deck https://github.com/muddled-design/homebrew-observation-deck
brew install claude-monitor
```

This will:
1. Build ClaudeMonitor from source
2. Install the `.app` bundle
3. Automatically configure Claude Code hooks for real-time status

## Launch

```bash
open $(brew --prefix)/opt/claude-monitor/ClaudeMonitor.app
```

## Uninstall

```bash
# Remove hooks from Claude Code settings
$(brew --prefix)/share/claude-monitor/install-hooks.sh --uninstall

# Uninstall the app
brew uninstall claude-monitor
brew untap muddled-design/observation-deck
```
