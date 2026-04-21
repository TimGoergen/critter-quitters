#!/bin/bash
# Fires on every Claude Stop event. Throttled to once per 30 minutes via a
# temp file timestamp. Reminds the user to commit and push, and warns if no
# feature branch is active.

REPO="D:/Claude/Critter Quitters"
THROTTLE_FILE="/tmp/cq_last_commit_reminder"
INTERVAL_SECONDS=1800   # 30 minutes
CURRENT_TIME=$(date +%s)

# --- Throttle check ---
if [ -f "$THROTTLE_FILE" ]; then
  LAST_REMINDER=$(cat "$THROTTLE_FILE")
  ELAPSED=$(( CURRENT_TIME - LAST_REMINDER ))
  if [ "$ELAPSED" -lt "$INTERVAL_SECONDS" ]; then
    exit 0
  fi
fi

# --- Branch check ---
BRANCH=$(git -C "$REPO" branch --show-current 2>/dev/null)

if [ -z "$BRANCH" ] || [ "$BRANCH" = "main" ]; then
  echo "$CURRENT_TIME" > "$THROTTLE_FILE"
  echo '{"systemMessage": "Commit reminder: No feature branch is active. Create or switch to a feature branch before continuing work."}'
  exit 0
fi

# --- Dirty / unpushed check ---
UNCOMMITTED=$(git -C "$REPO" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
UNPUSHED=$(git -C "$REPO" log "@{u}.." --oneline 2>/dev/null | wc -l | tr -d ' ')

echo "$CURRENT_TIME" > "$THROTTLE_FILE"

if [ "$UNCOMMITTED" -gt 0 ] || [ "$UNPUSHED" -gt 0 ]; then
  PARTS=()
  [ "$UNCOMMITTED" -gt 0 ] && PARTS+=("$UNCOMMITTED uncommitted change(s)")
  [ "$UNPUSHED"    -gt 0 ] && PARTS+=("$UNPUSHED unpushed commit(s)")
  DETAIL=$(IFS=" and "; echo "${PARTS[*]}")
  echo "{\"systemMessage\": \"Commit reminder (30 min): You have $DETAIL on branch '$BRANCH'. Consider committing and pushing.\"}"
fi
