#!/bin/bash
# Refresh all agent Linear OAuth tokens proactively
# Run daily via cron to prevent token expiry
# Usage: token-refresh.sh

set -euo pipefail

TOKEN_DIR="/data/clawlifeos/linear-tokens"
SCRIPT_DIR="$(dirname "$0")"

if [ ! -d "$TOKEN_DIR" ]; then
  echo "No token directory at $TOKEN_DIR"
  exit 0
fi

for token_file in "$TOKEN_DIR"/*.json; do
  [ -f "$token_file" ] || continue
  agent_id=$(basename "$token_file" .json)

  # Try a simple API call to trigger token refresh if needed
  CLAW_AGENT_ID="$agent_id" bash "$SCRIPT_DIR/linear-api.sh" get-my-issues > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Refreshed token for $agent_id — OK"
  else
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Token refresh FAILED for $agent_id"
  fi
done
