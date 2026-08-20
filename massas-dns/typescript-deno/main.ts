import { Application, Router } from "https://deno.land/x/oak@v13.0.0/mod.ts";

// ── Interfaces ────────────────────────────────────────────────────────────────

interface ParseRequest {
  massas: string;
  dns: string;
}

interface MassaData {
  headers: string[];
  rows: string[][];
}

interface DnsEntry {
  idx: number;
  env: string;
  url: string;
}

interface CombinedData {
  headers: string[];
  rows: string[][];
}

interface ParseResponse {
  massas: MassaData;
  dns: DnsEntry[];
  combined: CombinedData;
}

// ── Parser helpers ────────────────────────────────────────────────────────────

const KNOWN_HEADERS = [
  "cpf",
  "nome",
  "conta",
  "agência",
  "agencia",
  "agency",
  "email",
  "telefone",
];

function detectSep(line: string): string {
  const counts: Record<string, number> = { "\t": 0, ";": 0, ",": 0, "|": 0 };
  for (const ch of line) {
    if (ch in counts) counts[ch]++;
  }
  let best = ",";
  let max = 0;
  for (const [sep, n] of Object.entries(counts)) {
    if (n > max) {
      max = n;
      best = sep;
    }
  }
  return best;
}

function parseMassa(raw: string): MassaData {
  const lines = raw
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.length > 0);

  if (lines.length === 0) return { headers: [], rows: [] };

  // Find the header line — the first line whose tokens overlap with KNOWN_HEADERS
  let headerIdx = 0;
  let sep = detectSep(lines[0]);

  for (let i = 0; i < Math.min(lines.length, 10); i++) {
    const candidate = lines[i];
    sep = detectSep(candidate);
    const tokens = candidate.split(sep).map((t) =>
      t.trim().toLowerCase().replace(/['"]/g, "")
    );
    const match = tokens.filter((t) => KNOWN_HEADERS.includes(t));
    if (match.length > 0) {
      headerIdx = i;
      break;
    }
  }

  const headers = lines[headerIdx]
    .split(sep)
    .map((h) => h.trim().replace(/['"]/g, ""));

  const rows: string[][] = [];
  for (let i = headerIdx + 1; i < lines.length; i++) {
    const cells = lines[i].split(sep).map((c) => c.trim().replace(/['"]/g, ""));
    if (cells.length > 0 && cells.some((c) => c !== "")) {
      rows.push(cells);
    }
  }

  return { headers, rows };
}

function inferEnv(url: string): string {
  const lower = url.toLowerCase();
  if (lower.includes("hom") || lower.includes("homo")) return "HOM";
  if (lower.includes("uat")) return "UAT";
  if (lower.includes("sit")) return "SIT";
  if (lower.includes("dev")) return "DEV";
  if (lower.includes("prod") || lower.includes("prd")) return "PROD";
  return "PROD";
}

function parseDns(raw: string): DnsEntry[] {
  const lines = raw
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.length > 0);

  const entries: DnsEntry[] = [];
  let idx = 1;

  for (const line of lines) {
    // Skip comment-like or empty lines
    if (line.startsWith("#") || line.startsWith("//")) continue;

    // Accept bare URLs or "label <url>" or "label=url" or "label url"
    const urlMatch = line.match(
      /https?:\/\/[^\s,;|"'<>]+/i,
    );

    if (urlMatch) {
      const url = urlMatch[0];
      entries.push({ idx: idx++, env: inferEnv(url), url });
    } else {
      // No HTTP scheme — treat the whole token as a hostname/DNS entry
      const token = line.split(/[\s,;|=]+/).pop()?.trim() ?? "";
      if (token.length > 0) {
        entries.push({ idx: idx++, env: inferEnv(token), url: token });
      }
    }
  }

  return entries;
}

function buildCombined(massas: MassaData, dns: DnsEntry[]): CombinedData {
  if (massas.headers.length === 0 && dns.length === 0) {
    return { headers: [], rows: [] };
  }

  // Combined headers: massa columns + DNS columns
  const dnsHeaders = ["dns_idx", "dns_env", "dns_url"];
  const headers = [...massas.headers, ...dnsHeaders];

  const rows: string[][] = [];
  const maxRows = Math.max(massas.rows.length, dns.length);

  for (let i = 0; i < maxRows; i++) {
    const massaRow = massas.rows[i] ?? Array(massas.headers.length).fill("");
    const dnsEntry = dns[i];

    // Pad massa row if shorter than headers
    const padded = [
      ...massaRow,
      ...Array(Math.max(0, massas.headers.length - massaRow.length)).fill(""),
    ];

    const dnsRow = dnsEntry
      ? [String(dnsEntry.idx), dnsEntry.env, dnsEntry.url]
      : ["", "", ""];

    rows.push([...padded, ...dnsRow]);
  }

  return { headers, rows };
}

function toCsv(headers: string[], rows: string[][]): string {
  const escape = (v: string) =>
    v.includes(",") || v.includes('"') || v.includes("\n")
      ? `"${v.replace(/"/g, '""')}"`
      : v;

  const lines: string[] = [headers.map(escape).join(",")];
  for (const row of rows) {
    lines.push(row.map(escape).join(","));
  }
  return lines.join("\n");
}

// ── Oak application ───────────────────────────────────────────────────────────

const app = new Application();
const router = new Router();

// CORS middleware — allow all origins
app.use(async (ctx, next) => {
  ctx.response.headers.set("Access-Control-Allow-Origin", "*");
  ctx.response.headers.set(
    "Access-Control-Allow-Methods",
    "GET, POST, OPTIONS",
  );
  ctx.response.headers.set(
    "Access-Control-Allow-Headers",
    "Content-Type",
  );
  if (ctx.request.method === "OPTIONS") {
    ctx.response.status = 204;
    return;
  }
  await next();
});

// GET / — serve the frontend HTML
router.get("/", async (ctx) => {
  try {
    const html = await Deno.readTextFile(
      new URL("../automacao-massas-dns.html", import.meta.url),
    );
    ctx.response.type = "text/html";
    ctx.response.body = html;
  } catch {
    ctx.response.status = 404;
    ctx.response.body = "Frontend HTML not found.";
  }
});

// GET /health
router.get("/health", (ctx) => {
  ctx.response.type = "application/json";
  ctx.response.body = {
    status: "ok",
    language: "TypeScript",
    runtime: "Deno",
    framework: "Oak",
  };
});

// POST /api/parse
router.post("/api/parse", async (ctx) => {
  const body = ctx.request.body({ type: "json" });
  const { massas, dns } = (await body.value) as ParseRequest;

  const massaData = parseMassa(massas ?? "");
  const dnsEntries = parseDns(dns ?? "");
  const combined = buildCombined(massaData, dnsEntries);

  const response: ParseResponse = {
    massas: massaData,
    dns: dnsEntries,
    combined,
  };

  ctx.response.type = "application/json";
  ctx.response.body = response;
});

// POST /api/export/csv
router.post("/api/export/csv", async (ctx) => {
  const body = ctx.request.body({ type: "json" });
  const { massas, dns } = (await body.value) as ParseRequest;

  const massaData = parseMassa(massas ?? "");
  const dnsEntries = parseDns(dns ?? "");
  const combined = buildCombined(massaData, dnsEntries);
  const csv = toCsv(combined.headers, combined.rows);

  ctx.response.type = "text/csv";
  ctx.response.headers.set(
    "Content-Disposition",
    'attachment; filename="massas-dns.csv"',
  );
  ctx.response.body = csv;
});

// POST /api/export/json
router.post("/api/export/json", async (ctx) => {
  const body = ctx.request.body({ type: "json" });
  const { massas, dns } = (await body.value) as ParseRequest;

  const massaData = parseMassa(massas ?? "");
  const dnsEntries = parseDns(dns ?? "");
  const combined = buildCombined(massaData, dnsEntries);

  ctx.response.headers.set(
    "Content-Disposition",
    'attachment; filename="massas-dns.json"',
  );
  ctx.response.type = "application/json";
  ctx.response.body = { massas: massaData, dns: dnsEntries, combined };
});

app.use(router.routes());
app.use(router.allowedMethods());

console.log("🦕 Massas & DNS server running on http://localhost:8060");
await app.listen({ port: 8060 });
