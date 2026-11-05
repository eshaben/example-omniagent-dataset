#!/usr/bin/env bash
# Creates the Ridgeway knowledge collection, FAQ collection, tools, and Omniagent.
# Requires: curl, jq
#
# Required env vars:
#   NAPSTER_API_KEY      Your Napster API key
#   COMPANION_ID         A companion ID (from GET /public/companions/napster-stock)
#   KNOWLEDGE_BASE_URL   Public base URL where the knowledge/*.md files are hosted
#                        (for example https://raw.githubusercontent.com/you/repo/main/knowledge)
#   TOOL_SERVER_URL      Public URL of mock-tool-server.mjs (no trailing slash)
# Optional:
#   TOOL_SECRET          Shared secret the mock server checks (default: change-me)
#   NAPSTER_API_BASE     Default: https://companion-api.napster.com
set -euo pipefail
cd "$(dirname "$0")"

: "${NAPSTER_API_KEY:?Set NAPSTER_API_KEY}"
: "${COMPANION_ID:?Set COMPANION_ID}"
: "${KNOWLEDGE_BASE_URL:?Set KNOWLEDGE_BASE_URL}"
: "${TOOL_SERVER_URL:?Set TOOL_SERVER_URL}"
TOOL_SECRET="${TOOL_SECRET:-change-me}"
API="${NAPSTER_API_BASE:-https://companion-api.napster.com}"

call() { # call METHOD PATH [JSON_BODY]
  local out
  out=$(curl -sS -X "$1" "$API$2" \
    -H "X-Api-Key: $NAPSTER_API_KEY" \
    -H "Content-Type: application/json" \
    ${3:+-d "$3"} -w $'\n%{http_code}')
  local code="${out##*$'\n'}" body="${out%$'\n'*}"
  if [[ "$code" != 2* ]]; then
    echo "Error: $1 $2 returned $code: $body" >&2
    exit 1
  fi
  printf '%s' "$body"
}

echo "Creating knowledge collection..."
KB_ID=$(call POST /public/knowledge-bases '{"name":"Ridgeway Support Knowledge","provider":"azureOpenAI"}' | jq -r .id)
echo "  $KB_ID"

while IFS='|' read -r f summary; do
  echo "Uploading $f..."
  FILE_ID=$(call POST "/public/knowledge-bases/$KB_ID/files" "$(jq -n --arg u "$KNOWLEDGE_BASE_URL/$f" '{url:$u}')" | jq -r .id)
  call PATCH "/public/knowledge-bases/$KB_ID/files/$FILE_ID/summary" \
    "$(jq -n --arg s "$summary" '{summary:$s}')" >/dev/null
done <<'EOF'
product-catalog.md|Bike models, specs, prices, sizes, colors, batteries, and charge times
warranty-and-returns.md|Warranty coverage by component, exclusions, claims, 30-day returns, refunds, exchanges, and cancellations
maintenance-and-troubleshooting.md|Maintenance schedule, tire pressure, battery care, error codes, and common fixes
shipping-and-stores.md|Shipping costs and times, order statuses, store locations and hours, and service types and prices
EOF

echo "Creating FAQ collection..."
FAQ_ID=$(call POST /public/faqs "$(jq -c .collection faqs.json)" | jq -r .id)
echo "  $FAQ_ID"
jq -c '.items[]' faqs.json | while read -r item; do
  call POST "/public/faqs/$FAQ_ID/items" "$item" >/dev/null
done

FUNCTION_IDS=()
for t in tools/*.json; do
  body=$(jq -c --arg url "$TOOL_SERVER_URL" --arg secret "$TOOL_SECRET" '
    if .url then .url |= sub("\\{\\{TOOL_SERVER_URL\\}\\}"; $url) else . end
    | if .headers then .headers["x-tool-secret"] = $secret else . end' "$t")
  id=$(call POST /public/functions "$body" | jq -r .id)
  echo "Created tool $(jq -r .data.name "$t"): $id"
  FUNCTION_IDS+=("$id")
done

echo "Creating Omniagent..."
AGENT=$(jq -c \
  --arg companion "$COMPANION_ID" --arg kb "$KB_ID" --arg faq "$FAQ_ID" \
  --argjson fns "$(printf '%s\n' "${FUNCTION_IDS[@]}" | jq -R . | jq -sc .)" \
  '.companionId=$companion | .knowledgeBaseId=$kb | .faqCollections=[$faq] | .functions=$fns' agent.json)
AGENT_ID=$(call POST /public/agents "$AGENT" | jq -r .id)

echo
echo "Done."
echo "  Agent:                $AGENT_ID"
echo "  Knowledge collection: $KB_ID"
echo "  FAQ collection:       $FAQ_ID"
echo "  Tools:                ${FUNCTION_IDS[*]}"
