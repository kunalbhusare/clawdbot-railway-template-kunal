#!/usr/bin/env node
// ClawLifeOS Linear Webhook Receiver
// Listens for Linear webhook events and triggers agents via OpenClaw
//
// Events handled:
//   - AgentSessionEvent: Agent delegated an issue or @mentioned
//   - Issue update: Status changed to Revision → notify assigned agent
//   - Comment create: @mention detection → notify mentioned agents
//
// Runs as a pm2 process alongside the OpenClaw gateway.

const http = require('http');
const crypto = require('crypto');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const PORT = parseInt(process.env.LINEAR_WEBHOOK_PORT || '3100', 10);
const TOKEN_DIR = '/data/clawlifeos/linear-tokens';

// ── Load agent config from token files ──
const AGENT_MAP = {};     // linearUserId → agentId
const WEBHOOK_SECRETS = {}; // agentId → webhookSecret

function loadAgentConfig() {
  if (!fs.existsSync(TOKEN_DIR)) return;
  for (const file of fs.readdirSync(TOKEN_DIR)) {
    if (!file.endsWith('.json')) continue;
    try {
      const data = JSON.parse(fs.readFileSync(path.join(TOKEN_DIR, file), 'utf8'));
      if (data.linearUserId && data.agentId) {
        AGENT_MAP[data.linearUserId] = data.agentId;
      }
      if (data.webhookSecret && data.agentId) {
        WEBHOOK_SECRETS[data.agentId] = data.webhookSecret;
      }
    } catch (err) {
      console.error(`Failed to load ${file}:`, err.message);
    }
  }
  console.log(`Loaded ${Object.keys(AGENT_MAP).length} agent mappings, ${Object.keys(WEBHOOK_SECRETS).length} webhook secrets`);
}

loadAgentConfig();

// ── Signature verification ──
function verifySignature(body, signature, secret) {
  if (!signature || !secret) return false;
  const computed = crypto.createHmac('sha256', secret).update(body).digest('hex');
  try {
    return crypto.timingSafeEqual(Buffer.from(computed), Buffer.from(signature));
  } catch {
    return false;
  }
}

// ── Notify agent via OpenClaw CLI ──
function notifyAgent(agentId, message) {
  const ts = new Date().toISOString();
  try {
    // Use openclaw agent command to deliver the message
    const escapedMessage = message.replace(/'/g, "'\\''");
    execSync(
      `openclaw agent --agent ${agentId} -m '${escapedMessage}'`,
      { timeout: 60000, stdio: 'pipe' }
    );
    console.log(`[${ts}] Notified ${agentId} — OK`);
  } catch (err) {
    console.error(`[${ts}] Failed to notify ${agentId}:`, err.message);
  }
}

// ── Map Linear user to agent ──
function mapToAgent(linearUserId) {
  return AGENT_MAP[linearUserId] || null;
}

// ── HTTP server ──
const server = http.createServer((req, res) => {
  if (req.method !== 'POST' || req.url !== '/hooks/linear') {
    res.writeHead(404);
    return res.end('Not found');
  }

  let body = '';
  req.on('data', chunk => { body += chunk; });
  req.on('end', () => {
    const ts = new Date().toISOString();

    try {
      const payload = JSON.parse(body);
      const event = req.headers['linear-event'] || payload.type;
      const signature = req.headers['linear-signature'];

      console.log(`[${ts}] Received event: ${event}, action: ${payload.action || 'n/a'}`);

      // Respond immediately (Linear requires < 5s)
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true }));

      // Process asynchronously
      setImmediate(() => handleEvent(event, payload, body, signature));
    } catch (err) {
      console.error(`[${ts}] Parse error:`, err.message);
      if (!res.headersSent) {
        res.writeHead(400);
        res.end('Bad request');
      }
    }
  });
});

function handleEvent(event, payload, rawBody, signature) {
  switch (event) {
    case 'AgentSessionEvent': {
      // Agent was delegated an issue
      const session = payload.data;
      const agentId = mapToAgent(session?.appUserId);
      if (!agentId) {
        console.log('Unknown app user for AgentSessionEvent, ignoring');
        return;
      }

      const issue = session.issue || {};
      const message = payload.action === 'created'
        ? `New task delegated to you in Linear:\n\n` +
          `**${issue.identifier || 'Unknown'}: ${issue.title || 'Untitled'}**\n\n` +
          `${issue.description || 'No description'}\n\n` +
          `Priority: ${issue.priority || 'none'}\n` +
          `Use \`linear-api.sh get-issue ${issue.identifier}\` to see full details.`
        : `Follow-up on ${issue.identifier || 'issue'}:\n\n` +
          `${session.promptContext || 'Check the issue for new activity.'}`;

      notifyAgent(agentId, message);
      break;
    }

    case 'Issue': {
      if (payload.action !== 'update' || !payload.updatedFrom) return;

      const issue = payload.data;
      // If moved to "Revision", notify the assigned agent
      if (payload.updatedFrom.stateId && issue.state?.name === 'Revision') {
        const agentId = mapToAgent(issue.assignee?.id);
        if (agentId) {
          notifyAgent(agentId,
            `Issue ${issue.identifier} has been sent back for revision.\n` +
            `Check the latest comments for feedback.\n` +
            `Use \`linear-api.sh get-issue ${issue.identifier}\` to see details.`
          );
        }
      }

      // If newly assigned to an agent, notify them
      if (payload.updatedFrom.assigneeId && issue.assignee?.id) {
        const agentId = mapToAgent(issue.assignee.id);
        if (agentId) {
          notifyAgent(agentId,
            `Issue ${issue.identifier} has been assigned to you: "${issue.title}"\n` +
            `Use \`linear-api.sh get-issue ${issue.identifier}\` to see details.`
          );
        }
      }
      break;
    }

    case 'Comment': {
      if (payload.action !== 'create') return;
      const comment = payload.data;
      if (!comment.body) return;

      // Check for @mentions in comment body
      const mentionMap = {
        '@Nova': 'nova',
        '@Sage': 'sage',
        '@Work': 'work',
        '@Researcher': 'researcher',
        '@ContentCreator': 'content-creator',
        '@Content': 'content-creator',
      };

      for (const [mention, agentId] of Object.entries(mentionMap)) {
        if (comment.body.includes(mention)) {
          notifyAgent(agentId,
            `You were mentioned in a comment:\n\n` +
            `${comment.body.slice(0, 200)}${comment.body.length > 200 ? '...' : ''}\n\n` +
            `Check the issue in Linear for full context.`
          );
        }
      }
      break;
    }

    default:
      console.log(`Unhandled event type: ${event}`);
  }
}

server.listen(PORT, () => {
  console.log(`[${new Date().toISOString()}] Linear webhook receiver listening on port ${PORT}`);
  console.log(`Agent mappings: ${JSON.stringify(AGENT_MAP)}`);
});
