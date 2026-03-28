# OpenClaw Railway Template

A production wrapper that deploys OpenClaw (AI agent framework) on Railway with a setup wizard, reverse proxy, and ClawLifeOS integrations.

## Commands

```bash
npm run dev         # Start the wrapper server locally
npm run start       # Same as dev (production)
npm run lint        # Syntax check server.js
npm run smoke       # Run smoke tests
```

## Architecture

```
entrypoint.sh           # Container startup: install skills, start pm2, then server
src/server.js           # Express wrapper: reverse proxy + setup wizard + config management
src/setup-app.js        # Frontend JS for the /setup onboarding wizard
clawlifeos/
  ecosystem.config.js   # PM2 config for Linear webhook receiver (port 3100)
  linear-webhook.js     # Receives Linear events, notifies agents via OpenClaw CLI
  skills/               # Baked-in OpenClaw skills (copied to ~/.openclaw/skills/ on start)
Dockerfile              # Based on ghcr.io/openclaw/openclaw:latest
railway.toml            # Railway healthcheck + deployment settings
```

### How the wrapper works

1. `entrypoint.sh` copies skills, starts pm2 (Linear webhook), then runs `node src/server.js`
2. `server.js` spawns the OpenClaw gateway (`openclaw gateway run --bind loopback --port 18789`)
3. Express serves `/setup` (password-protected wizard) and proxies everything else to the gateway
4. WebSocket upgrades are proxied to the gateway for the Control UI

### Key internal ports

| Port | Service | Visibility |
|------|---------|------------|
| 8080 | Express wrapper | Public (Railway) |
| 18789 | OpenClaw gateway | Loopback only |
| 3100 | Linear webhook receiver | Internal |

## Gateway Configuration (per docs.openclaw.ai)

Config file: `$OPENCLAW_STATE_DIR/openclaw.json` (JSON5, hot-reloaded)

The wrapper auto-configures these before every gateway start:
- `gateway.controlUi.allowedOrigins` — set to `["https://<RAILWAY_PUBLIC_DOMAIN>"]`
- `gateway.trustedProxies` — set to `["127.0.0.1"]` (the local wrapper proxy)
- `gateway.controlUi.dangerouslyDisableDeviceAuth` — `true` (headless deploy, no terminal for `openclaw devices approve`)
- `gateway.auth.token` — synced from `OPENCLAW_GATEWAY_TOKEN` env var
- `openclaw doctor --fix` — runs before start to auto-repair config issues

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `OPENCLAW_GATEWAY_TOKEN` | Admin token for gateway auth (treat as secret) |
| `OPENCLAW_STATE_DIR` | Persistent state (`/data/.openclaw` recommended) |
| `OPENCLAW_WORKSPACE_DIR` | Agent workspace directory |
| `SETUP_PASSWORD` | Protects the `/setup` wizard |
| `ANTHROPIC_API_KEY` | Claude API key for the agent |
| `RAILWAY_PUBLIC_DOMAIN` | Auto-set by Railway; used for allowedOrigins |
| `LINEAR_API_KEY` | For Linear webhook integration |

## Common Issues

- **"Multiple matrix-js-sdk entrypoints detected!"** — Use the official Docker image (`ghcr.io/openclaw/openclaw:latest`), do not build from source.
- **"pairing required"** — Expected on headless deploys. The wrapper sets `dangerouslyDisableDeviceAuth: true` automatically.
- **"origin not allowed"** — `allowedOrigins` must include the Railway public domain. The wrapper sets this on every start.
- **"untrusted proxy"** — `trustedProxies` must include `127.0.0.1` for the local wrapper proxy.
- **Config invalid / crash loop** — `openclaw doctor --fix` runs automatically before gateway start.
- **Telegram 404** — Plugins failed to load. Check deploy logs for plugin errors.

## Code Conventions

- ESM modules (`"type": "module"` in package.json)
- Express 5.1 (async route handler support)
- `getEnvWithShim()` provides backward compat for deprecated `CLAWDBOT_*` env vars
- Config commands use `openclaw config set` CLI, not direct file writes
- All config set results are logged for debugging

## Official References

- [OpenClaw Docs](https://docs.openclaw.ai)
- [Railway Deploy Guide](https://docs.openclaw.ai/install/railway)
- [Gateway Configuration](https://docs.openclaw.ai/gateway/configuration-reference)
- [Trusted Proxy Auth](https://docs.openclaw.ai/gateway/trusted-proxy-auth)
- [Control UI](https://docs.openclaw.ai/web/control-ui)
- [Doctor Command](https://docs.openclaw.ai/gateway/doctor)
