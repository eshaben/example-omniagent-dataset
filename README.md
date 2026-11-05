# Ridgeway Cycles: example Omniagent dataset

A support agent for a fictional e-bike company. It includes:

| Piece | Files |
|---|---|
| Knowledge collection (4 docs) | `knowledge/*.md` |
| FAQ collection (5 Q&As) | `faqs.json` |
| Tools: 3 explicit, 1 implicit | `tools/*.json` |
| Agent definition | `agent.json` |
| Mock backend for the explicit tools | `mock-tool-server.mjs` |
| One-shot setup | `setup.sh` |

## Setup

1. **Host the knowledge files.** Uploads take a public URL, so put `knowledge/` somewhere public, such as a GitHub repo (use the raw URL) or a public bucket.
2. **Run the mock tool server and expose it:**
   ```bash
   TOOL_SECRET=change-me node mock-tool-server.mjs
   cloudflared tunnel --url http://localhost:8787   # or: ngrok http 8787
   ```
3. **Pick a companion:** `curl "https://companion-api.napster.com/public/companions/napster-stock?pageSize=10" -H "X-Api-Key: $NAPSTER_API_KEY"`
4. **Create everything:**
   ```bash
   export NAPSTER_API_KEY=...
   export COMPANION_ID=...
   export KNOWLEDGE_BASE_URL=https://raw.githubusercontent.com/you/repo/main/knowledge
   export TOOL_SERVER_URL=https://your-tunnel.trycloudflare.com
   export TOOL_SECRET=change-me
   ./setup.sh
   ```

Use a Realtime API key (Azure OpenAI or OpenAI). The agent sets `temperature`, which a Cascade key ignores.

## Things to say to the agent

| Prompt | Exercises |
|---|---|
| "Which bike should I get for a 10-mile commute?" | Knowledge (catalog) + `show_product` |
| "How long does the Haul battery take to charge with the fast charger?" | Knowledge (catalog table: 4.5 hours) |
| "My display shows E10. What does that mean?" | Knowledge (troubleshooting) |
| "Can I return my bike if I've ridden it 120 miles?" | Knowledge (returns: no, 100-mile limit) |
| "Can I ride in the rain?" | FAQ |
| "Where's my order? It's RW-10482." | `get_order_status` (shipped, UPS tracking) |
| "Is order RW-10533 ready?" | `get_order_status` (ready for pickup in Denver) |
| "I want a tune-up at the Denver store." | `check_service_availability` → `book_service_appointment` (asks to confirm first) |

Mock orders: `RW-10482` (shipped), `RW-10517` (processing), `RW-10533` (ready for pickup), `RW-10560` (delivered). Any other number returns "not found".

`show_product` is implicit, so your client receives a `function_implicitly_called` event with a `sku`. Return any result, such as `{"shown": true}`.
