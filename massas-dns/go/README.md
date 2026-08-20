# Massas & DNS — Go backend (`net/http`)

Pure-Go HTTP server for the **Massas & DNS** automation tool.  
No external dependencies — only the Go standard library (`net/http`, `encoding/json`, `encoding/csv`).

---

## Requirements

| Tool | Minimum version |
|------|----------------|
| Go   | 1.21            |

---

## Running

```bash
# from massas-dns/go/
go run main.go
```

The server starts on **http://localhost:8080**.

---

## Endpoints

| Method | Path               | Description                                                   |
|--------|--------------------|---------------------------------------------------------------|
| `GET`  | `/`                | Serves `../automacao-massas-dns.html`                         |
| `GET`  | `/health`          | Liveness check — returns `{"status":"ok","language":"Go",…}`  |
| `POST` | `/api/parse`       | Parses massa + DNS text, returns structured JSON              |
| `POST` | `/api/export/csv`  | Returns a `.csv` download for `massas`, `dns`, or `combined`  |
| `POST` | `/api/export/json` | Returns a full `.json` export as a downloadable file          |

---

## Request / Response shapes

### `POST /api/parse`

**Request body**
```json
{
  "massas": "cpf\tnome\n12345678901\tJoão Silva",
  "dns":    "HML https://hml.example.com\nPRD https://prd.example.com"
}
```

**Response body**
```json
{
  "massas": {
    "headers": ["cpf", "nome"],
    "rows": [{ "cpf": "12345678901", "nome": "João Silva" }]
  },
  "dns": [
    { "idx": 0, "env": "HML", "url": "https://hml.example.com" },
    { "idx": 1, "env": "PRD", "url": "https://prd.example.com" }
  ],
  "combined": [
    { "cpf": "12345678901", "nome": "João Silva", "env": "HML", "url": "https://hml.example.com", "dns_idx": "0" },
    { "cpf": "12345678901", "nome": "João Silva", "env": "PRD", "url": "https://prd.example.com", "dns_idx": "1" }
  ]
}
```

### `POST /api/export/csv`

**Request body** — same fields as the parse response, plus a `type` discriminator:
```json
{
  "type": "combined",
  "massas": { "headers": [...], "rows": [...] },
  "dns": [...],
  "combined": [...]
}
```
`type` must be `"massas"`, `"dns"`, or `"combined"`.  
Response: `Content-Disposition: attachment; filename="massas-dns-{type}.csv"`.

### `POST /api/export/json`

**Request body** — same as above (no `type` field required).  
Response: `Content-Disposition: attachment; filename="massas-dns-export.json"`.

---

## Parser rules

### Delimiter detection (`detectSep`)
Tab → Semicolon → Comma (first match wins).

### Header detection (`parseMassa`)
The first line whose fields contain at least one known keyword is treated as the header row.

**Known header keywords:** `cpf`, `nome`, `conta`, `agência`, `agencia`, `agency`, `email`, `telefone`

### DNS parsing (`parseDNS`)
Each non-empty line is split by whitespace:
- **2+ tokens** → `token[0]` becomes `env` (uppercased), `token[1]` becomes `url`.
- **1 token**   → treated as `url`; environment is **inferred** from the URL string.

### Environment inference (`inferEnv`)
| Keyword in URL          | Env label |
|-------------------------|-----------|
| `hml` / `homolog`       | `HML`     |
| `prd` / `prod`          | `PROD`    |
| `dev`                   | `DEV`     |
| `sit`                   | `SIT`     |
| `uat`                   | `UAT`     |
| `qas`                   | `QAS`     |
| *(no match)*            | `UNKNOWN` |

### Combined output (`buildCombined`)
Cartesian product of every massa row × every DNS entry.  
Each merged row includes all massa columns plus `env`, `url`, and `dns_idx`.

---

## CORS

All routes return `Access-Control-Allow-Origin: *`.  
`OPTIONS` pre-flight requests are handled automatically.
