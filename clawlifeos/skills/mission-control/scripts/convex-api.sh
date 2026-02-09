#!/bin/bash
# ClawLifeOS Convex API caller with HMAC-SHA256 signing
# Usage: convex-api.sh <endpoint> <json-body>
# Example: convex-api.sh /api/heartbeat '{"agentId":"nova","status":"active"}'

set -euo pipefail

ENDPOINT="$1"
BODY="$2"

if [ -z "$CONVEX_SITE_URL" ] || [ -z "$CLAW_BRIDGE_SECRET" ]; then
  echo "ERROR: CONVEX_SITE_URL and CLAW_BRIDGE_SECRET must be set" >&2
  exit 1
fi

SIGNATURE=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$CLAW_BRIDGE_SECRET" -hex 2>/dev/null | sed 's/^.* //')

curl -s -X POST "${CONVEX_SITE_URL}${ENDPOINT}" \
  -H "Content-Type: application/json" \
  -H "x-bridge-signature: ${SIGNATURE}" \
  -d "$BODY"