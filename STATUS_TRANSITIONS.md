# Status Transition State Machine

## States
- **Running** (green) — Claude is actively working
- **Idle** (blue) — Claude finished, session sitting idle
- **Needs Input** (orange) — Claude waiting for permission/user action
- **Finished** (gray) — Process is dead

## Critical Rule
**Running is STICKY when we have hook data.** Once a hook signal says "running",
the session stays Running until a Stop or Notification hook explicitly ends it.
Heuristic timeouts NEVER override a hook-sourced Running state.

## Test Cases

### TC1: Claude starts working after user sends message
- **Trigger**: User sends a message in Claude Code
- **Signals**: JSONL write (user message logged), then PreToolUse hook fires
- **Expected**: Status transitions from Idle → Running immediately on JSONL write
- **Previous bug**: Stale "idle" hook signal overrode the JSONL write

### TC2: Claude thinking / waiting for API response
- **Trigger**: Claude makes an API call (no local activity)
- **Signals**: NONE — no hooks fire, no JSONL writes, no CPU activity
- **Expected**: Status STAYS Running (no change)
- **Previous bug**: Heuristic timeout (3s) flipped status to Idle, then back
  to Running when streaming resumed — causing visible flickering

### TC3: Claude streaming response
- **Trigger**: Claude streams text back to terminal
- **Signals**: JSONL writes (assistant message chunks)
- **Expected**: Status stays Running

### TC4: Claude uses a tool
- **Trigger**: Claude calls Read, Edit, Bash, etc.
- **Signals**: PreToolUse hook → tool executes → PostToolUse hook, JSONL writes
- **Expected**: Status stays Running throughout

### TC5: Claude finishes responding (task complete)
- **Trigger**: Claude's turn ends
- **Signals**: Stop hook fires, then Notification(idle_prompt) after delay
- **Expected**: Status transitions Running → Idle
- **Timing**: Should happen within 1s of Stop hook firing

### TC6: Claude needs permission
- **Trigger**: Claude wants to run a tool that needs approval
- **Signals**: Notification(permission_prompt) hook fires
- **Expected**: Status transitions Running → Needs Input

### TC7: User grants permission, Claude resumes
- **Trigger**: User approves the permission prompt
- **Signals**: PreToolUse hook fires, JSONL writes resume
- **Expected**: Status transitions Needs Input → Running

### TC8: Session between tool calls (gap)
- **Trigger**: Claude finishes one tool, thinks about next step (API call)
- **Signals**: PostToolUse hook fires, then silence for several seconds
- **Expected**: Status STAYS Running — PostToolUse is NOT a stop signal
- **Previous bug**: Heuristic timeout kicked in during the gap

### TC9: Subagent working
- **Trigger**: Claude spawns a subagent (Agent tool)
- **Signals**: SubagentStart hook, subagent JSONL writes, SubagentStop hook
- **Expected**: Status stays Running throughout subagent execution

### TC10: Process exits
- **Trigger**: User types /exit or closes terminal
- **Signals**: PID no longer alive (kill -0 fails)
- **Expected**: Status transitions → Finished regardless of last hook signal

### TC11: Session with no hook data (legacy/pre-hooks)
- **Trigger**: Session started before hooks were configured
- **Signals**: No hook signal files exist for this session
- **Expected**: Falls back to heuristic (file activity + CPU time)
- **Heuristic behavior**: Running if file activity < 3s or CPU active, else Idle

### TC12: New session reuses same cwd as old session
- **Trigger**: User /exit and starts new session in same directory
- **Signals**: New session file with different sessionId, new hook signals
- **Expected**: Hook signals from OLD session don't bleed into new session
- **Key**: Match by most recent hook signal for the cwd, not stale ones

## State Transition Diagram

```
                    ┌──────────────────────────────┐
                    │                              │
                    ▼                              │
    ┌─────────┐  file write /   ┌──────────┐     │
    │  Idle   │──hook "running"─▶│ Running  │     │
    └─────────┘                 └──────────┘     │
         ▲                      │    │    │      │
         │               Stop   │    │    │      │
         │               hook   │    │    │      │
         │                      │    │    │      │
         └──────────────────────┘    │    │      │
                                     │    │      │
                   Notification      │    │ PID  │
                   (permission)      │    │ dead │
                                     │    │      │
                              ┌──────▼─┐  │      │
                              │ Needs  │  │      │
                              │ Input  │──┘      │
                              └────────┘         │
                                   │             │
                           file write /          │
                           hook "running"        │
                                   │             │
                                   └─────────────┘
                                                 │
                              PID dead anywhere  │
                                                 ▼
                                          ┌──────────┐
                                          │ Finished │
                                          └──────────┘
```
