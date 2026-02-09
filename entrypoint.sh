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

# 2. Start notification daemon via pm2 (if ecosystem config exists on persistent volume)
if [ -f /data/clawlifeos/ecosystem.config.js ]; then
  pm2 start /data/clawlifeos/ecosystem.config.js --silent
  echo "[entrypoint] Notification daemon started via pm2"
else
  echo "[entrypoint] No /data/clawlifeos/ecosystem.config.js found, skipping pm2"
fi

# 3. Start the main OpenClaw wrapper server
exec node src/server.js
