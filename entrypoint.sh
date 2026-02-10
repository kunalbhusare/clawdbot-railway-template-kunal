#!/bin/bash
set -e

# --- ClawLifeOS Startup Script ---
# Runs on every container start to restore ephemeral files that live outside /data/.

# 1. Install baked-in skills to the OpenClaw skills directory
if [ -d /app/clawlifeos/skills ]; then
  mkdir -p /root/.openclaw/skills
  cp -r /app/clawlifeos/skills/* /root/.openclaw/skills/
  echo "[entrypoint] Skills installed to /root/.openclaw/skills/"
fi

# 2. Start Linear webhook receiver via pm2
#    Uses baked-in ecosystem config (from /app/clawlifeos/) or persistent one (from /data/clawlifeos/)
if [ -f /app/clawlifeos/ecosystem.config.js ]; then
  pm2 start /app/clawlifeos/ecosystem.config.js --silent
  echo "[entrypoint] Linear webhook receiver started via pm2 (baked-in config)"
elif [ -f /data/clawlifeos/ecosystem.config.js ]; then
  pm2 start /data/clawlifeos/ecosystem.config.js --silent
  echo "[entrypoint] Linear webhook receiver started via pm2 (persistent config)"
else
  echo "[entrypoint] No ecosystem.config.js found, skipping pm2"
fi

# 3. Start the main OpenClaw wrapper server
exec node src/server.js
