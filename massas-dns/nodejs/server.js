'use strict';

const express = require('express');
const cors    = require('cors');
const path    = require('path');
const fs      = require('fs');

const app  = express();
const PORT = 8080;

app.use(cors());
app.use(express.json({ limit: '10mb' }));

// ══════════════════════════════════════════════════
//  PARSER HELPERS
// ══════════════════════════════════════════════════

/**
 * Detect CSV separator from a single line.
 * Priority: tab → semicolon → comma
 */
function detectSep(line) {
  if (line.includes('\t')) return '\t';
  if (line.includes(';'))  return ';';
  return ',';
}

/**
 * Infer environment label from a URL string.
 */
function inferEnv(url) {
  const u = url.toLowerCase();
  if (u.includes('hml') || u.includes('homolog')) return 'HML';
  if (u.includes('prd') || u.includes('prod'))    return 'PROD';
  if (u.includes('dev'))                           return 'DEV';
  if (u.includes('sit'))                           return 'SIT';
  if (u.includes('uat'))                           return 'UAT';
  if (u.includes('qas'))                           return 'QAS';
  return 'UNKNOWN';
}

const KNOWN_HEADERS = new Set([
  'cpf', 'nome', 'conta', 'agência', 'agencia', 'agency',
  'email', 'telefone', 'phone', 'senha', 'password', 'id'
]);

/**
 * Parse raw massa text (CSV / TSV / semicolon-separated).
 * Auto-detects header row and separator.
 * @returns {{ headers: string[], rows: string[][] }}
 */
function parseMassa(raw) {
  const lines = raw.trim().split('\n').filter(l => l.trim());
  if (!lines.length) return { headers: [], rows: [] };

  const sep   = detectSep(lines[0]);
  const first = lines[0].split(sep).map(c => c.trim().toLowerCase());
  const isHeader = first.some(c => KNOWN_HEADERS.has(c));

  let headers, dataLines;
  if (isHeader) {
    headers   = lines[0].split(sep).map(c => c.trim());
    dataLines = lines.slice(1);
  } else {
    const cols = lines[0].split(sep).length;
    headers    = ['CPF', 'Nome', 'Conta', 'Agência'].slice(0, cols);
    dataLines  = lines;
  }

  const rows = dataLines
    .filter(l => l.trim())
    .map(l => l.split(sep).map(c => c.trim()));

  return { headers, rows };
}

/**
 * Parse raw DNS text — one entry per line, optional env prefix.
 * @returns {{ idx: number, env: string, url: string }[]}
 */
function parseDNS(raw) {
  const lines = raw.trim().split('\n').filter(l => l.trim());
  return lines.map((line, i) => {
    const parts = line.trim().split(/\s+/);
    if (parts.length >= 2) {
      return { idx: i + 1, env: parts[0].toUpperCase(), url: parts.slice(1).join(' ') };
    }
    return { idx: i + 1, env: inferEnv(parts[0]), url: parts[0] };
  });
}

/**
 * Build cartesian product of massa rows × DNS entries.
 * @returns {{ headers: string[], rows: string[][] }}
 */
function buildCombined(massas, dnsList) {
  if (!massas.rows.length || !dnsList.length) {
    return { headers: [], rows: [] };
  }
  const headers = [...massas.headers, 'Ambiente', 'URL / DNS'];
  const rows = [];
  for (const mr of massas.rows) {
    for (const dns of dnsList) {
      rows.push([...mr, dns.env, dns.url]);
    }
  }
  return { headers, rows };
}

/**
 * Serialize to RFC-4180 CSV with UTF-8 BOM for Excel compatibility.
 */
function toCSV(headers, rows) {
  const quote = v => {
    const s = String(v ?? '');
    return (s.includes(',') || s.includes('"') || s.includes('\n'))
      ? `"${s.replace(/"/g, '""')}"`
      : s;
  };
  const lines = [headers, ...rows].map(r => r.map(quote).join(','));
  return '\uFEFF' + lines.join('\n');
}

// ══════════════════════════════════════════════════
//  ROUTES
// ══════════════════════════════════════════════════

/** Serve the shared frontend */
app.get('/', (req, res) => {
  const htmlPath = path.resolve(__dirname, '..', 'automacao-massas-dns.html');
  if (fs.existsSync(htmlPath)) {
    res.sendFile(htmlPath);
  } else {
    res.status(404).send('Frontend HTML not found. Place automacao-massas-dns.html one level above this folder.');
  }
});

/** Health check */
app.get('/health', (req, res) => {
  res.json({
    status:    'ok',
    language:  'Node.js',
    framework: 'Express',
    port:      PORT,
    node:      process.version,
  });
});

/** Parse massas + DNS and return structured data + combined view */
app.post('/api/parse', (req, res) => {
  const { massas: massasRaw = '', dns: dnsRaw = '' } = req.body;
  const massas   = parseMassa(massasRaw);
  const dns      = parseDNS(dnsRaw);
  const combined = buildCombined(massas, dns);
  res.json({ massas, dns, combined });
});

/**
 * Export as CSV download.
 * Body: { type: 'massas'|'dns'|'combinado', massasData?, dnsData?, combinedData? }
 */
app.post('/api/export/csv', (req, res) => {
  const { type, massasData, dnsData, combinedData } = req.body;

  let headers, rows, filename;

  if (type === 'massas' && massasData) {
    headers  = ['#', ...massasData.headers];
    rows     = massasData.rows.map((r, i) => [(i + 1).toString(), ...r]);
    filename = 'massas.csv';
  } else if (type === 'dns' && dnsData) {
    headers  = ['#', 'Ambiente', 'URL / DNS'];
    rows     = dnsData.map(d => [String(d.idx), d.env, d.url]);
    filename = 'dns.csv';
  } else if (type === 'combinado' && combinedData) {
    headers  = ['#', ...combinedData.headers];
    rows     = combinedData.rows.map((r, i) => [(i + 1).toString(), ...r]);
    filename = 'combinado.csv';
  } else {
    return res.status(400).json({ error: 'Invalid type or missing data.' });
  }

  const csv = toCSV(headers, rows);
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  res.send(csv);
});

/** Export full payload as JSON download */
app.post('/api/export/json', (req, res) => {
  const { massas: massasRaw = '', dns: dnsRaw = '' } = req.body;
  const massas   = parseMassa(massasRaw);
  const dns      = parseDNS(dnsRaw);
  const combined = buildCombined(massas, dns);

  const payload = {
    geradoEm:  new Date().toISOString(),
    massas:    {
      colunas: massas.headers,
      dados:   massas.rows.map(r => Object.fromEntries(massas.headers.map((h, i) => [h, r[i] ?? '']))),
    },
    dns,
    combinado: combined.rows.map(r => Object.fromEntries(combined.headers.map((h, i) => [h, r[i] ?? '']))),
  };

  const json = JSON.stringify(payload, null, 2);
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Content-Disposition', 'attachment; filename="massas-dns.json"');
  res.send(json);
});

// ══════════════════════════════════════════════════
//  START
// ══════════════════════════════════════════════════
app.listen(PORT, () => {
  console.log(`\n  Massas & DNS — Node.js / Express`);
  console.log(`  ► http://localhost:${PORT}\n`);
});
