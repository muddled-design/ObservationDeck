#!/bin/bash
# Claude Code hook script for ClaudeMonitor
# Reads hook event JSON from stdin and writes a status signal file.
# Uses python3 to parse all fields in one call for efficiency.

INPUT=$(cat)

eval "$(echo "$INPUT" | /usr/bin/python3 -c "
import sys, json, os
d = json.load(sys.stdin)
sid = d.get('session_id', '')
event = d.get('hook_event_name', '')
ntype = d.get('notification_type', '')
cwd = d.get('cwd', '')
# Extract session ID from transcript path (most reliable identifier)
tp = d.get('transcript_path', '')
# transcript_path looks like: ~/.claude/projects/{encoded-path}/{sessionId}.jsonl
tsid = os.path.splitext(os.path.basename(tp))[0] if tp else sid
print(f'SESSION_ID=\"{sid}\"')
print(f'HOOK_EVENT=\"{event}\"')
print(f'NOTIF_TYPE=\"{ntype}\"')
print(f'CWD=\"{cwd}\"')
print(f'TRANSCRIPT_SESSION_ID=\"{tsid}\"')
" 2>/dev/null)"

[ -z "$SESSION_ID" ] && exit 0

STATUS_DIR="$HOME/.claude/monitor-status"
mkdir -p "$STATUS_DIR"

case "$HOOK_EVENT" in
  Stop)
    STATUS="idle"
    ;;
  Notification)
    case "$NOTIF_TYPE" in
      permission_prompt|elicitation_dialog)
        STATUS="needs_input"
        ;;
      *)
        STATUS="idle"
        ;;
    esac
    ;;
  PreToolUse|SubagentStart|PostToolUse|SubagentStop)
    STATUS="running"
    ;;
  *)
    STATUS="running"
    ;;
esac

# Write signal using BOTH the hook session ID and the transcript session ID
# so the monitor can match by either
echo "{\"session_id\":\"$SESSION_ID\",\"transcript_session_id\":\"$TRANSCRIPT_SESSION_ID\",\"status\":\"$STATUS\",\"event\":\"$HOOK_EVENT\",\"notification_type\":\"$NOTIF_TYPE\",\"cwd\":\"$CWD\",\"timestamp\":$(date +%s)}" > "$STATUS_DIR/$SESSION_ID.json"

# Also write a symlink/copy by transcript session ID if different
if [ "$TRANSCRIPT_SESSION_ID" != "$SESSION_ID" ] && [ -n "$TRANSCRIPT_SESSION_ID" ]; then
    cp "$STATUS_DIR/$SESSION_ID.json" "$STATUS_DIR/$TRANSCRIPT_SESSION_ID.json"
fi
