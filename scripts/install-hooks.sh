#!/bin/bash
set -euo pipefail

# Install ClaudeMonitor hooks into Claude Code settings.
# This script is used by Homebrew post_install and can be run standalone.
# Usage: ./install-hooks.sh [--uninstall]

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
HOOK_SCRIPT="$CLAUDE_DIR/monitor-hook.sh"
HOOK_COMMAND="bash ~/.claude/monitor-hook.sh"
STATUS_DIR="$CLAUDE_DIR/monitor-status"

EVENTS=("Stop" "Notification" "PreToolUse" "PostToolUse" "SubagentStart" "SubagentStop")

# Locate the bundled hook script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLED_HOOK="$SCRIPT_DIR/../monitor-hook.sh"

# When installed via Homebrew, the hook is at the share path
if [ ! -f "$BUNDLED_HOOK" ]; then
    BUNDLED_HOOK="$(brew --prefix 2>/dev/null)/share/claude-monitor/monitor-hook.sh" || true
fi

uninstall() {
    echo "==> Removing ClaudeMonitor hooks..."

    if [ ! -f "$SETTINGS_FILE" ]; then
        echo "    No settings.json found, nothing to remove."
        return
    fi

    # Remove the hook command from settings.json using python3
    /usr/bin/python3 -c "
import json, sys

with open('$SETTINGS_FILE', 'r') as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})
events = $( printf '%s\n' "${EVENTS[@]}" | /usr/bin/python3 -c "import sys; print([l.strip() for l in sys.stdin])" )
changed = False

for event in events:
    rules = hooks.get(event, [])
    for rule in rules:
        hook_list = rule.get('hooks', [])
        filtered = [h for h in hook_list if h.get('command') != '$HOOK_COMMAND']
        if len(filtered) != len(hook_list):
            changed = True
            rule['hooks'] = filtered
    # Remove empty rules
    hooks[event] = [r for r in rules if r.get('hooks')]
    if not hooks[event]:
        del hooks[event]

if changed:
    settings['hooks'] = hooks
    with open('$SETTINGS_FILE', 'w') as f:
        json.dump(settings, f, indent=2)
    print('    Hooks removed from settings.json')
else:
    print('    No ClaudeMonitor hooks found in settings.json')
"

    # Remove hook script
    if [ -f "$HOOK_SCRIPT" ]; then
        rm "$HOOK_SCRIPT"
        echo "    Removed $HOOK_SCRIPT"
    fi

    echo "==> Uninstall complete."
}

install() {
    echo "==> Installing ClaudeMonitor hooks..."

    # Create directories
    mkdir -p "$CLAUDE_DIR"
    mkdir -p "$STATUS_DIR"

    # Copy hook script
    if [ -f "$BUNDLED_HOOK" ]; then
        cp "$BUNDLED_HOOK" "$HOOK_SCRIPT"
        chmod +x "$HOOK_SCRIPT"
        echo "    Installed hook script to $HOOK_SCRIPT"
    else
        echo "    ERROR: Could not find monitor-hook.sh"
        echo "    Looked at: $SCRIPT_DIR/../monitor-hook.sh"
        exit 1
    fi

    # Create or update settings.json
    if [ ! -f "$SETTINGS_FILE" ]; then
        echo '{}' > "$SETTINGS_FILE"
    fi

    /usr/bin/python3 -c "
import json

with open('$SETTINGS_FILE', 'r') as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})
events = ['Stop', 'Notification', 'PreToolUse', 'PostToolUse', 'SubagentStart', 'SubagentStop']
hook_entry = {'type': 'command', 'command': '$HOOK_COMMAND', 'async': True}
changed = False

for event in events:
    rules = hooks.get(event, [])

    # Check if already present
    found = False
    for rule in rules:
        for h in rule.get('hooks', []):
            if h.get('command') == '$HOOK_COMMAND':
                found = True
                break
        if found:
            break

    if not found:
        if rules:
            # Append to existing first rule
            rules[0].setdefault('hooks', []).append(hook_entry)
        else:
            rules.append({'hooks': [hook_entry]})
        hooks[event] = rules
        changed = True

if changed:
    settings['hooks'] = hooks
    with open('$SETTINGS_FILE', 'w') as f:
        json.dump(settings, f, indent=2)
    print('    Registered hooks in settings.json')
else:
    print('    Hooks already registered in settings.json')

print('    Done! Hooks will activate on your next Claude Code session.')
"
}

# Main
case "${1:-}" in
    --uninstall)
        uninstall
        ;;
    *)
        install
        ;;
esac
