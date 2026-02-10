---
name: mission-control
description: ClawLifeOS task management via Linear + local knowledge base.
metadata: { "openclaw": { "always": true, "requires": { "bins": ["curl", "jq"] } } }
---

# Mission Control — Linear + Local Knowledge

You are connected to ClawLifeOS via Linear (task management) and a shared local knowledge base.

**IMPORTANT:** Replace YOUR_AGENT_ID with your actual agent ID in all commands. Check your SOUL.md if unsure.

## Linear API Script

All task operations go through:

```bash
bash {baseDir}/scripts/linear-api.sh <command> [args...]
```

Your agent ID is set via `CLAW_AGENT_ID` environment variable.

## Task Management (Linear Issues)

### View your assigned issues

```bash
bash {baseDir}/scripts/linear-api.sh get-my-issues
```

### View all active issues

```bash
bash {baseDir}/scripts/linear-api.sh get-all-issues
```

### Get issue details + comments

```bash
bash {baseDir}/scripts/linear-api.sh get-issue CLO-123
```

### Move issue status

```bash
bash {baseDir}/scripts/linear-api.sh move-issue CLO-123 "In Progress"
```

Valid statuses you can set: `Assigned`, `In Progress`, `Review`, `Revision`
**NEVER move to Done** — only Kunal can do that.

### Comment on an issue

```bash
bash {baseDir}/scripts/linear-api.sh comment CLO-123 "Your markdown comment here"
```

### Create a new issue

```bash
bash {baseDir}/scripts/linear-api.sh create-issue "Title" "Description" --priority high --label work --status "Assigned"
```

Options:
- `--priority`: urgent, high, medium, low (default: medium)
- `--label`: any label name (work, personal, research, content, etc.)
- `--assignee`: agent ID to assign to
- `--status`: initial status (default: Inbox)

### Search issues

```bash
bash {baseDir}/scripts/linear-api.sh search "search terms"
```

### Mention another agent in a comment

Use @Nova, @Sage, @Work, @Researcher, or @ContentCreator in your comment text.

## Task Lifecycle

Issues follow this status flow:

```
Inbox → Assigned → In Progress → Review → Done
                                    ↓        ↑
                                 Revision ───┘
```

### Your Responsibilities

1. **Pick up a task** → Move to "In Progress"
2. **Do the work** → Post updates as comments on the issue
3. **Work complete** → Move to "Review" (NEVER to Done)
4. **Revision requested** → Move to "In Progress", address feedback, then back to "Review"

### Status Transitions You Can Make

- Assigned → In Progress (when you start)
- In Progress → Review (when deliverable is ready)
- Revision → In Progress (when you start revisions)
- In Progress → Review (after revisions)

### Status Transitions Only Kunal Makes

- Review → Done (approval)
- Review → Revision (with feedback in comments)
- Inbox → Assigned (initial triage)

## Posting Deliverables

Post all deliverables as **comments on the issue** with clear markdown formatting:

```bash
bash {baseDir}/scripts/linear-api.sh comment CLO-123 "## Research Report: Topic

### Key Findings
1. Finding one...
2. Finding two...

### Recommendation
..."
```

For large outputs, write to a file in your workspace and reference it in the comment.

## Knowledge Base (Local Filesystem)

Knowledge lives in `/data/knowledge/` — shared across all agents.

### Read the knowledge index

```bash
cat /data/knowledge/README.md
```

### Read a specific entry

```bash
cat /data/knowledge/reference/tools-and-services.md
```

### List entries by category

```bash
ls /data/knowledge/decisions/
ls /data/knowledge/reference/
ls /data/knowledge/preferences/
ls /data/knowledge/procedures/
ls /data/knowledge/context/
```

### Search knowledge

```bash
grep -r "search term" /data/knowledge/ --include="*.md" -l
```

### Create a knowledge entry

```bash
cat > /data/knowledge/{category}/{filename}.md << 'EOF'
# Title

**Category**: category
**Tags**: tag1, tag2
**Created**: $(date +%Y-%m-%d)
**Source**: YOUR_AGENT_ID

---

Content here.
EOF
```

After creating, update `/data/knowledge/README.md` with a link to the new entry.

### Update knowledge

Edit files in place. Update the "Last updated" line in README.md.

## Memory (Per-Agent Workspace)

Your workspace is at `/data/workspace/YOUR_AGENT_ID/`.

### Update your working state

```bash
cat > /data/workspace/YOUR_AGENT_ID/WORKING.md << 'EOF'
# Current State
- Task: CLO-123 — Task title
- Status: In Progress
- Next: What you plan to do next
EOF
```

### Read your identity

```bash
cat /data/workspace/YOUR_AGENT_ID/SOUL.md
```

### Update heartbeat

```bash
cat > /data/workspace/YOUR_AGENT_ID/HEARTBEAT.md << 'EOF'
# Heartbeat
- Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Status: active
- Current Task: CLO-123
EOF
```

## Rules

1. **Always move issues to "In Progress" when you start working**
2. **Post deliverables as comments** on the issue with clear markdown formatting
3. **Move to "Review" when done** — NEVER to "Done"
4. **Update WORKING.md** after each task state change
5. **When mentioning other agents**, use their @-handle in comments
6. **Keep knowledge entries concise** and well-tagged
7. **Search knowledge BEFORE asking the user** — check if the answer already exists
8. **Update HEARTBEAT.md** at the start of every response

## When to Use What

| Action | Where |
|--------|-------|
| Create/manage tasks | Linear (via linear-api.sh) |
| Post deliverables | Linear comments on the issue |
| Store reusable knowledge | `/data/knowledge/` filesystem |
| Track your current state | `/data/workspace/YOUR_AGENT_ID/WORKING.md` |
| Record your identity | `/data/workspace/YOUR_AGENT_ID/SOUL.md` |
| Signal you're alive | `/data/workspace/YOUR_AGENT_ID/HEARTBEAT.md` |
