---
name: mission-control
description: ClawLifeOS dashboard integration — heartbeats, tasks, activities, knowledge, documents, and notifications.
metadata: { "openclaw": { "always": true, "requires": { "env": ["CONVEX_SITE_URL", "CLAW_BRIDGE_SECRET"], "bins": ["curl", "openssl"] } } }
---

# Mission Control — ClawLifeOS Dashboard Integration

You are connected to the ClawLifeOS dashboard via Convex. Use the API script below to report your status, manage tasks, and log activities. The dashboard shows your work in real-time.

**IMPORTANT:** Replace YOUR_AGENT_ID with your actual agent ID in all commands below. Check your SOUL.md if unsure of your agent ID.

## API Script

All API calls go through the signing script:

```bash
bash {baseDir}/scripts/convex-api.sh <endpoint> '<json-body>'
```

## CRITICAL: Always Sync Content to Convex

Your work is only visible on the ClawLifeOS dashboard if it exists in Convex. Local files (`memory/*.md`, workspace files) are NOT shown on the dashboard.

### Mandatory Rules:
1. **Deliverables:** When you complete ANY document, blog post, research report, analysis, or draft — you MUST create it via `/api/documents` with the full content and link it to the task via `taskId`. You may also save locally, but the Convex document is what the user sees on the dashboard.
2. **Knowledge:** When you learn important facts, make decisions, record preferences, or compile research — you MUST store it via `/api/knowledge`. Do NOT rely solely on local `memory/*.md` files.
3. **Task completion:** Before moving a task to "done", ensure ALL deliverables are created as Convex documents linked to the task.
4. **Daily summaries:** At the end of each heartbeat where you did meaningful work, store a brief summary via `/api/knowledge` with category `context` and tag `daily-log`.

### Think of it this way:
- Local `memory/*.md` files = your personal scratch notes (only you can see them)
- Convex `/api/documents` = published deliverables (visible to user on dashboard)
- Convex `/api/knowledge` = shared knowledge base (visible on dashboard Knowledge Browser)

## CRITICAL: Heartbeat on Every Message

At the START of every response, before doing anything else, send a heartbeat:

```bash
bash {baseDir}/scripts/convex-api.sh /api/heartbeat '{"agentId":"YOUR_AGENT_ID","status":"active"}'
```

If you are working on a specific task, include its ID:

```bash
bash {baseDir}/scripts/convex-api.sh /api/heartbeat '{"agentId":"YOUR_AGENT_ID","status":"active","currentTaskId":"TASK_ID_HERE"}'
```

## Log Activities

Log significant actions to the activity feed. Types: `task_created`, `task_moved`, `task_completed`, `comment_added`, `knowledge_added`, `delegation_sent`, `standup_delivered`, `document_created`.

```bash
bash {baseDir}/scripts/convex-api.sh /api/activities '{"type":"TYPE","actorId":"YOUR_AGENT_ID","summary":"what happened","metadata":{}}'
```

Optional fields: `targetType` (e.g. "task"), `targetId` (Convex document ID).

## Create Tasks

When you need to track work or delegate, create a task:

```bash
bash {baseDir}/scripts/convex-api.sh /api/tasks '{"action":"create","title":"Task title","description":"Details","createdBy":"YOUR_AGENT_ID","assigneeId":"TARGET_AGENT_ID","source":"telegram","domain":"work","priority":"medium","tags":["tag1"]}'
```

- `priority`: urgent, high, medium, low
- `domain`: work, personal, coordination, system
- `source`: telegram, webchat, cron, agent
- `assigneeId`: any valid agent ID (check your AGENTS.md for the current roster)
- `status` (optional, default "inbox"): inbox, assigned, in_progress, review, done

## Move Tasks

```bash
bash {baseDir}/scripts/convex-api.sh /api/tasks '{"action":"move","taskId":"TASK_ID","status":"in_progress","actorId":"YOUR_AGENT_ID"}'
```

## Task Lifecycle

Tasks follow this status flow: `inbox` → `assigned` → `in_progress` → `review` → `done` (with optional `revision` loop).

### Automatic Transitions
The system will **automatically** move tasks from "assigned" to "in_progress" when you:
- Send a heartbeat with `currentTaskId` pointing to the task
- Create a document linked to the task
- Comment on the task

### Your Responsibilities
Even though the system auto-promotes "assigned" → "in_progress", you MUST still manually move tasks for these transitions:
1. **Work complete** → Move to "review": `{"action":"move","taskId":"ID","status":"review","actorId":"YOUR_AGENT_ID"}`
2. **After revision feedback** → Move back to "review" when revisions are done

### Best Practice
When you pick up a task:
1. Send heartbeat with `currentTaskId` (this auto-promotes to in_progress)
2. Do the work, creating documents with `taskId` as you go
3. When done, move to "review"
4. If revision is requested, address feedback and move back to "review"

## Get My Tasks

```bash
bash {baseDir}/scripts/convex-api.sh /api/tasks '{"action":"get_by_assignee","assigneeId":"YOUR_AGENT_ID"}'
```

## Update Tasks

```bash
bash {baseDir}/scripts/convex-api.sh /api/tasks '{"action":"update","taskId":"TASK_ID","title":"New title","description":"New description","priority":"high","tags":["updated"]}'
```

## Add Comments

```bash
bash {baseDir}/scripts/convex-api.sh /api/comments '{"taskId":"TASK_ID","authorId":"YOUR_AGENT_ID","content":"My update","mentions":["AGENT_ID"]}'
```

Adding a comment automatically subscribes you to the task thread. @mentioned agents are also auto-subscribed.

## Create Documents

Create structured deliverables linked to tasks:

```bash
bash {baseDir}/scripts/convex-api.sh /api/documents '{"action":"create","title":"Document Title","content":"Markdown content here","type":"deliverable","taskId":"TASK_ID","createdBy":"YOUR_AGENT_ID","tags":["tag1"]}'
```

Document types: `deliverable`, `research`, `protocol`, `draft`, `analysis`, `notes`, `image`.

If `taskId` is provided, the document is automatically added to the task's deliverables list.

## Upload Image Documents

To upload images (generated images, screenshots, charts) to the dashboard, use this 3-step flow:

### Step 1: Get a presigned upload URL

```bash
UPLOAD_RESULT=$(bash {baseDir}/scripts/convex-api.sh /api/documents '{"action":"generate_upload_url"}')
UPLOAD_URL=$(echo "$UPLOAD_RESULT" | jq -r '.uploadUrl')
```

### Step 2: Upload the binary file (no HMAC needed — the URL itself is auth)

```bash
STORAGE_RESULT=$(curl -s -X POST "$UPLOAD_URL" -H "Content-Type: image/png" --data-binary @/path/to/image.png)
STORAGE_ID=$(echo "$STORAGE_RESULT" | jq -r '.storageId')
```

Supported Content-Types: `image/png`, `image/jpeg`, `image/webp`, `image/gif`.

### Step 3: Create the image document record

```bash
bash {baseDir}/scripts/convex-api.sh /api/documents '{"action":"create","title":"Image Title","content":"Optional caption","type":"image","storageId":"'"$STORAGE_ID"'","mimeType":"image/png","taskId":"TASK_ID","createdBy":"YOUR_AGENT_ID","tags":["generated"]}'
```

**Important:** The upload URL from step 1 expires in minutes — complete all 3 steps promptly. Use `type: "image"` so the dashboard renders it as an image. The `content` field is shown as a caption below the image.

## Get Documents by Task

```bash
bash {baseDir}/scripts/convex-api.sh /api/documents '{"action":"get_by_task","taskId":"TASK_ID"}'
```

## Subscribe to Task Thread

Subscribing ensures you receive notifications when others comment:

```bash
bash {baseDir}/scripts/convex-api.sh /api/subscriptions '{"action":"ensure","taskId":"TASK_ID","agentId":"YOUR_AGENT_ID","reason":"manual"}'
```

Note: You are auto-subscribed when assigned to a task, when you comment, or when you're @mentioned.

## Check Notifications

```bash
bash {baseDir}/scripts/convex-api.sh /api/notifications '{"action":"get_undelivered"}'
```

## Store Knowledge

Save important information for future retrieval:

```bash
bash {baseDir}/scripts/convex-api.sh /api/knowledge '{"action":"create_no_embedding","title":"Title","content":"Content body","category":"CATEGORY","source":"YOUR_AGENT_ID","tags":["tag1"]}'
```

Categories: `reference`, `decision`, `preference`, `context`, `procedure`, `personal`, `work_knowledge`.

## Search Knowledge

```bash
bash {baseDir}/scripts/convex-api.sh /api/knowledge '{"action":"search","query":"search terms","category":"CATEGORY"}'
```

## When to Use Mission Control

- User sends a message → heartbeat (ALWAYS, before anything else)
- You produce ANY content (blog post, research, draft, analysis, report) → create document via `/api/documents` with full content (MANDATORY — this is how the user sees your work)
- You learn important facts, context, decisions, or research → store via `/api/knowledge` (MANDATORY — this is how knowledge appears on the dashboard)
- You complete a task → ensure ALL deliverables exist as Convex documents with `taskId`, THEN move task to "done"
- You create a task → automatic activity logging (API does it)
- You delegate to another agent → create task with assigneeId, add comment with @mention
- You need context → search knowledge base (`/api/knowledge` search) BEFORE asking user
