// Mock backend for the three explicit Ridgeway tools. No dependencies.
// Run: TOOL_SECRET=change-me node mock-tool-server.mjs   (listens on PORT, default 8787)
// Expose it publicly (for example `cloudflared tunnel --url http://localhost:8787`
// or `ngrok http 8787`) and use that URL as TOOL_SERVER_URL in setup.sh.
import http from "node:http";
import { randomUUID } from "node:crypto";

const PORT = Number(process.env.PORT ?? 8787);
const SECRET = process.env.TOOL_SECRET ?? "change-me";

const orders = {
  "RW-10482": { status: "shipped", items: ["Ridgeway Metro 2, M, Sage"], carrier: "UPS", tracking: "1Z999AA10123456784", estimatedDelivery: "2026-11-07" },
  "RW-10517": { status: "processing", items: ["Ridgeway Haul", "R-Series 720 second battery"], estimatedShipDate: "2026-11-06" },
  "RW-10533": { status: "ready_for_pickup", items: ["Ridgeway Summit, L, Moss"], store: "store_den" },
  "RW-10560": { status: "delivered", items: ["Fast charger (6A)"], deliveredOn: "2026-10-30" },
};

const stores = {
  store_pdx: "Portland", store_den: "Denver", store_aus: "Austin", store_bkn: "Brooklyn", store_tor: "Toronto",
};

const slots = new Map(); // slot_id -> slot, filled by check_service_availability

function availability({ store_id, service_type }) {
  if (!stores[store_id]) return { error: `Unknown store_id ${store_id}` };
  const out = [];
  const start = new Date();
  for (let day = 1; out.length < 5 && day <= 7; day++) {
    const d = new Date(start);
    d.setDate(d.getDate() + day);
    for (const hour of [10, 14]) {
      if ((day + hour) % 3 === 0) continue; // make some slots look taken
      const slot = {
        slot_id: `slot_${store_id.slice(6)}_${d.toISOString().slice(0, 10)}_${hour}`,
        store: stores[store_id],
        service_type,
        date: d.toISOString().slice(0, 10),
        time: `${hour}:00`,
      };
      slots.set(slot.slot_id, slot);
      out.push(slot);
    }
  }
  return { slots: out.slice(0, 5) };
}

function book({ slot_id, customer_name, customer_phone, notes }) {
  const slot = slots.get(slot_id);
  if (!slot) return { error: "That slot isn't available. Check availability again." };
  slots.delete(slot_id);
  return {
    confirmation_id: `appt_${randomUUID().slice(0, 8)}`,
    ...slot,
    customer_name,
    customer_phone,
    notes: notes ?? null,
    message: "Booked. A reminder text goes out the day before.",
  };
}

const routes = {
  "/tools/get-order-status": ({ order_id }) =>
    orders[order_id?.toUpperCase()] ? { order_id, ...orders[order_id.toUpperCase()] } : { error: `No order found with number ${order_id}` },
  "/tools/check-service-availability": availability,
  "/tools/book-service-appointment": book,
};

http
  .createServer((req, res) => {
    const handler = routes[req.url];
    if (req.method !== "POST" || !handler) return res.writeHead(404).end();
    if (req.headers["x-tool-secret"] !== SECRET) return res.writeHead(401).end();
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      let call;
      try {
        call = JSON.parse(body);
      } catch {
        return res.writeHead(400).end();
      }
      const args = typeof call.arguments === "string" ? JSON.parse(call.arguments) : call.arguments ?? {};
      const result = handler(args);
      console.log(call.name, args, "->", result);
      res.writeHead(200, { "Content-Type": "application/json" }).end(JSON.stringify(result));
    });
  })
  .listen(PORT, () => console.log(`Ridgeway mock tools on http://localhost:${PORT}`));
