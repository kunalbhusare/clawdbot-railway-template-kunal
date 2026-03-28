# OpenClaw Railway Template

## Overview

Production wrapper deploying OpenClaw on Railway. Express reverse proxy + setup wizard + PM2-managed Linear webhook receiver.

## Stack

- **Runtime**: Node.js 22+ (ESM)
- **Base image**: `ghcr.io/openclaw/openclaw:latest`
- **Framework**: Express 5.1 with http-proxy
- **Process manager**: PM2 (for Linear webhook)
- **Deployment**: Railway (Dockerfile builder)

## Project Structure

- `src/server.js` — Main wrapper: spawns gateway, reverse proxies, serves setup wizard
- `src/setup-app.js` — Frontend JS for `/setup` onboarding
- `clawlifeos/linear-webhook.js` — Linear event receiver (PM2-managed, port 3100)
- `clawlifeos/ecosystem.config.js` — PM2 process config
- `clawlifeos/skills/` — Baked-in OpenClaw skills
- `entrypoint.sh` — Container startup script
- `Dockerfile` — Based on official OpenClaw image
- `railway.toml` — Healthcheck and deploy config

## Development

```bash
npm run dev         # Start wrapper server
npm run lint        # Syntax check
npm run smoke       # Smoke tests
```

## Key Design Decisions

- Gateway runs on loopback (18789), wrapper proxies from public port (8080)
- `openclaw doctor --fix` runs before every gateway start to prevent crash loops
- `dangerouslyDisableDeviceAuth: true` required for headless Railway (no terminal for pairing)
- `trustedProxies: ["127.0.0.1"]` — only the local wrapper proxy, per official docs
- Official Docker image used as base to avoid build-from-source plugin loading failures

## Configuration

Gateway config at `$OPENCLAW_STATE_DIR/openclaw.json` — managed via `openclaw config set` CLI commands, not direct file edits. The wrapper auto-configures allowedOrigins, trustedProxies, auth token, and device auth on every gateway start.

## References

- [docs.openclaw.ai/install/railway](https://docs.openclaw.ai/install/railway)
- [docs.openclaw.ai/gateway/configuration-reference](https://docs.openclaw.ai/gateway/configuration-reference)
