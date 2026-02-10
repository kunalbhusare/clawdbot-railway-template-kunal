#!/bin/bash
# ClawLifeOS Linear API wrapper
# Usage: linear-api.sh <command> [args...]
#
# Auth priority:
#   1. Per-agent token file: /data/clawlifeos/linear-tokens/${CLAW_AGENT_ID}.json
#   2. Environment variable: LINEAR_API_KEY
#
# Team key: CLO (hardcoded, single-team setup)

set -euo pipefail

AGENT_ID="${CLAW_AGENT_ID:-nova}"
TOKEN_FILE="/data/clawlifeos/linear-tokens/${AGENT_ID}.json"
TEAM_ID="8f7f1c60-f34f-4f11-b8fe-8c1dcdc61a65"

# ─── Workflow State IDs ───
declare -A STATE_IDS=(
  ["Inbox"]="dc93527f-215b-4378-b25f-caa5e93dec05"
  ["Assigned"]="3326473e-6f42-44b2-890d-904398f40fbe"
  ["In Progress"]="75e39b83-91a8-4abc-851f-051d7d923fe3"
  ["Review"]="05e31dd8-2528-4a39-a4c6-f25e44fadb68"
  ["Revision"]="9ec0de18-f7da-48fe-9aba-26f0995303aa"
  ["Done"]="1ac5c902-611d-4b16-86b3-19d5c1f840b2"
  ["Canceled"]="d53d091e-38ab-4435-a1f6-f084bc49545b"
)

# ─── Auth ───
get_token() {
  if [ -f "$TOKEN_FILE" ]; then
    local token_data access_token expires_at now exp
    token_data=$(cat "$TOKEN_FILE")
    access_token=$(echo "$token_data" | jq -r '.accessToken')
    expires_at=$(echo "$token_data" | jq -r '.expiresAt // "2099-01-01T00:00:00Z"')

    # Check expiry (refresh if within 5 min)
    now=$(date -u +%s)
    exp=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${expires_at%%Z*}" +%s 2>/dev/null || echo "9999999999")

    if [ "$now" -gt "$((exp - 300))" ]; then
      refresh_token
      token_data=$(cat "$TOKEN_FILE")
      access_token=$(echo "$token_data" | jq -r '.accessToken')
    fi

    echo "$access_token"
  elif [ -n "${LINEAR_API_KEY:-}" ]; then
    echo "$LINEAR_API_KEY"
  else
    echo "ERROR: No token file ($TOKEN_FILE) and no LINEAR_API_KEY set" >&2
    exit 1
  fi
}

refresh_token() {
  local token_data client_id client_secret refresh_tok response
  token_data=$(cat "$TOKEN_FILE")
  client_id=$(echo "$token_data" | jq -r '.clientId')
  client_secret=$(echo "$token_data" | jq -r '.clientSecret')
  refresh_tok=$(echo "$token_data" | jq -r '.refreshToken')

  response=$(curl -s -X POST https://api.linear.app/oauth/token \
    -d "grant_type=refresh_token" \
    -d "client_id=${client_id}" \
    -d "client_secret=${client_secret}" \
    -d "refresh_token=${refresh_tok}")

  local new_access new_refresh new_expires
  new_access=$(echo "$response" | jq -r '.access_token')
  new_refresh=$(echo "$response" | jq -r '.refresh_token // empty')
  new_expires=$(echo "$response" | jq -r '.expires_in // 2592000')

  if [ "$new_access" = "null" ] || [ -z "$new_access" ]; then
    echo "ERROR: Token refresh failed: $response" >&2
    return 1
  fi

  local new_expiry
  new_expiry=$(date -u -v+"${new_expires}S" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
    date -u -d "+${new_expires} seconds" +%Y-%m-%dT%H:%M:%SZ)

  echo "$token_data" | jq \
    --arg at "$new_access" \
    --arg rt "${new_refresh:-$(echo "$token_data" | jq -r '.refreshToken')}" \
    --arg exp "$new_expiry" \
    '.accessToken=$at | .refreshToken=$rt | .expiresAt=$exp' > "$TOKEN_FILE"
}

# ─── GraphQL Helper ───
gql() {
  local token query variables
  token=$(get_token)
  query="$1"
  variables="${2:-{\}}"

  curl -s -X POST https://api.linear.app/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${token}" \
    -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')"
}

# ─── COMMANDS ───

case "${1:-help}" in

  get-my-issues)
    gql '
      query($teamId: String!) {
        team(id: $teamId) {
          issues(filter: {
            assignee: { isMe: { eq: true } }
            state: { type: { nin: ["completed", "canceled"] } }
          }) {
            nodes {
              identifier
              title
              state { name }
              priority
              labels { nodes { name } }
              updatedAt
            }
          }
        }
      }
    ' "{\"teamId\": \"${TEAM_ID}\"}" | jq -r '
      .data.team.issues.nodes[] |
      "\(.identifier) [\(.state.name)] P\(.priority) — \(.title)"
    '
    ;;

  get-all-issues)
    gql '
      query($teamId: String!) {
        team(id: $teamId) {
          issues(filter: {
            state: { type: { nin: ["completed", "canceled"] } }
          }, first: 50) {
            nodes {
              identifier
              title
              state { name }
              priority
              assignee { name }
              labels { nodes { name } }
              updatedAt
            }
          }
        }
      }
    ' "{\"teamId\": \"${TEAM_ID}\"}" | jq -r '
      .data.team.issues.nodes[] |
      "\(.identifier) [\(.state.name)] P\(.priority) @\(.assignee.name // "unassigned") — \(.title)"
    '
    ;;

  get-issue)
    ISSUE_ID="${2:?Usage: linear-api.sh get-issue CLO-123}"
    gql '
      query($id: String!) {
        issueVcsBranchSearch(branchName: $id) {
          identifier
          title
          description
          state { name }
          priority
          labels { nodes { name } }
          assignee { name }
          comments(first: 20) {
            nodes {
              body
              user { name }
              createdAt
            }
          }
          attachments {
            nodes {
              title
              url
            }
          }
        }
      }
    ' "{\"id\": \"${ISSUE_ID}\"}" | jq '
      if .data.issueVcsBranchSearch then .data.issueVcsBranchSearch
      else .errors[0].message // "Issue not found"
      end
    '
    ;;

  move-issue)
    ISSUE_ID="${2:?Usage: linear-api.sh move-issue CLO-123 'In Progress'}"
    TARGET_STATUS="${3:?Specify target status: Assigned, In Progress, Review, Revision}"

    # Safety: never allow Done
    if [ "$TARGET_STATUS" = "Done" ]; then
      echo "ERROR: Agents cannot move issues to Done. Only Kunal can do that." >&2
      exit 1
    fi

    STATE_ID="${STATE_IDS[$TARGET_STATUS]:-}"
    if [ -z "$STATE_ID" ]; then
      echo "ERROR: Unknown status '${TARGET_STATUS}'. Valid: Assigned, In Progress, Review, Revision" >&2
      exit 1
    fi

    # Look up issue UUID from identifier
    ISSUE_UUID=$(gql '
      query($id: String!) {
        issueVcsBranchSearch(branchName: $id) { id identifier }
      }
    ' "{\"id\": \"${ISSUE_ID}\"}" | jq -r '.data.issueVcsBranchSearch.id // empty')

    if [ -z "$ISSUE_UUID" ]; then
      echo "ERROR: Issue ${ISSUE_ID} not found" >&2
      exit 1
    fi

    gql '
      mutation($issueId: String!, $stateId: String!) {
        issueUpdate(id: $issueId, input: { stateId: $stateId }) {
          success
          issue { identifier state { name } }
        }
      }
    ' "{\"issueId\": \"${ISSUE_UUID}\", \"stateId\": \"${STATE_ID}\"}" | jq '.data.issueUpdate'
    ;;

  comment)
    ISSUE_ID="${2:?Usage: linear-api.sh comment CLO-123 'message'}"
    BODY="${3:?Specify comment body}"

    # Look up issue UUID
    ISSUE_UUID=$(gql '
      query($id: String!) {
        issueVcsBranchSearch(branchName: $id) { id }
      }
    ' "{\"id\": \"${ISSUE_ID}\"}" | jq -r '.data.issueVcsBranchSearch.id // empty')

    if [ -z "$ISSUE_UUID" ]; then
      echo "ERROR: Issue ${ISSUE_ID} not found" >&2
      exit 1
    fi

    gql '
      mutation($issueId: String!, $body: String!) {
        commentCreate(input: { issueId: $issueId, body: $body }) {
          success
          comment { id }
        }
      }
    ' "$(jq -n --arg id "$ISSUE_UUID" --arg body "$BODY" '{issueId: $id, body: $body}')" | jq '.data.commentCreate'
    ;;

  create-issue)
    TITLE="${2:?Usage: linear-api.sh create-issue 'Title' 'Description' [--priority high] [--label work] [--assignee AGENT_ID]}"
    DESCRIPTION="${3:-}"
    PRIORITY=3  # default: Normal
    LABELS=""
    ASSIGNEE=""

    # Parse optional flags
    shift 3 2>/dev/null || shift $#
    while [ $# -gt 0 ]; do
      case "$1" in
        --priority)
          case "${2:-medium}" in
            urgent) PRIORITY=1 ;;
            high)   PRIORITY=2 ;;
            medium|normal) PRIORITY=3 ;;
            low)    PRIORITY=4 ;;
          esac
          shift 2 ;;
        --label) LABELS="${LABELS:+${LABELS},}${2}" ; shift 2 ;;
        --assignee) ASSIGNEE="$2" ; shift 2 ;;
        --status)
          # Set initial status
          INIT_STATUS="${2}"
          shift 2 ;;
        *) shift ;;
      esac
    done

    # Build mutation variables
    VARS=$(jq -n \
      --arg teamId "$TEAM_ID" \
      --arg title "$TITLE" \
      --arg desc "$DESCRIPTION" \
      --argjson priority "$PRIORITY" \
      '{teamId: $teamId, title: $title, description: $desc, priority: $priority}')

    # Add state if specified
    if [ -n "${INIT_STATUS:-}" ]; then
      STATE_ID="${STATE_IDS[$INIT_STATUS]:-}"
      if [ -n "$STATE_ID" ]; then
        VARS=$(echo "$VARS" | jq --arg sid "$STATE_ID" '. + {stateId: $sid}')
      fi
    fi

    gql '
      mutation($teamId: String!, $title: String!, $description: String, $priority: Int, $stateId: String) {
        issueCreate(input: {
          teamId: $teamId
          title: $title
          description: $description
          priority: $priority
          stateId: $stateId
        }) {
          success
          issue { identifier title url state { name } }
        }
      }
    ' "$VARS" | jq '.data.issueCreate'
    ;;

  search)
    QUERY="${2:?Usage: linear-api.sh search 'search terms'}"
    gql '
      query($teamId: String!, $query: String!) {
        searchIssues(filter: {
          team: { id: { eq: $teamId } }
        }, term: $query, first: 10) {
          nodes {
            identifier
            title
            state { name }
            priority
            assignee { name }
          }
        }
      }
    ' "$(jq -n --arg tid "$TEAM_ID" --arg q "$QUERY" '{teamId: $tid, query: $q}')" | jq -r '
      .data.searchIssues.nodes[] //
      "No results" |
      if type == "string" then . else
      "\(.identifier) [\(.state.name)] P\(.priority) @\(.assignee.name // "unassigned") — \(.title)"
      end
    '
    ;;

  help|*)
    cat << 'HELP'
ClawLifeOS Linear API — Agent Task Management

Commands:
  get-my-issues                        List active issues assigned to you
  get-all-issues                       List all active issues in the team
  get-issue CLO-123                    Get issue details + comments
  move-issue CLO-123 'In Progress'     Change issue status
  comment CLO-123 'text'               Post a comment on an issue
  create-issue 'Title' 'Desc' [opts]   Create a new issue
    --priority urgent|high|medium|low
    --label LABEL_NAME
    --assignee AGENT_ID
    --status 'Inbox'|'Assigned'|etc
  search 'query'                       Search issues by text

Status Flow: Inbox → Assigned → In Progress → Review → (Revision →) Done
IMPORTANT: Agents may NEVER move issues to Done. Only Kunal does that.
HELP
    ;;
esac
