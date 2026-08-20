# Massas & DNS — C# / .NET 8 Minimal API

Server implementation of the **Massas & DNS** automation tool using C# with the
[.NET 8 Minimal API](https://learn.microsoft.com/aspnet/core/fundamentals/minimal-apis)
programming model. The entire implementation lives in a single `Program.cs` file
using top-level statements, records, and one `static class`.

---

## Requirements

| Tool | Version |
|------|---------|
| [.NET SDK](https://dotnet.microsoft.com/download) | **8.0** or later |

Verify your installation:

```bash
dotnet --version   # should print 8.x.x
```

---

## Running

```bash
# from this directory (massas-dns/csharp/)
dotnet run
```

The server starts on **http://localhost:8090**.

To watch for file changes during development:

```bash
dotnet watch run
```

---

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET`  | `/` | Serves `../automacao-massas-dns.html` as `text/html` |
| `GET`  | `/health` | Returns `{ status, language, framework, port }` |
| `POST` | `/api/parse` | Accepts `{ massas, dns }`, returns parsed `MassaData`, `DnsEntry[]`, and `CombinedData` |
| `POST` | `/api/export/csv` | Accepts `ExportRequest`, returns a UTF-8 BOM CSV file download |
| `POST` | `/api/export/json` | Accepts `{ massas, dns }`, returns a JSON file download |

### `/api/parse` — request body

```json
{
  "massas": "CPF\tNome\n123\tJoão",
  "dns":    "HML https://api.hml.example.com"
}
```

### `/api/export/csv` — request body

```json
{
  "type": "combined",
  "massasData": { "headers": [...], "rows": [[...]] },
  "dnsData":    [{ "idx": 1, "env": "HML", "url": "..." }],
  "combinedData": { "headers": [...], "rows": [[...]] }
}
```

`type` may be `"massas"`, `"dns"`, or `"combined"` (default).

---

## Architecture notes

- **Top-level statements** — `Program.cs` contains no wrapping `class Program`.
- **Records** — all data-transfer types (`ParseRequest`, `MassaData`, `DnsEntry`,
  `CombinedData`, `ParseResponse`, `ExportRequest`) are C# 9+ positional records.
- **`static class ParserService`** — all parsing and export logic is grouped here:
  - `DetectSep` — sniffs the column separator (tab → semicolon → comma).
  - `InferEnv` — maps URL substrings to environment labels (HML, PROD, DEV, SIT, UAT, QAS).
  - `ParseMassa` — splits raw text, auto-detects or infers headers.
  - `ParseDns` — one entry per line; optional env prefix or auto-inferred.
  - `BuildCombined` — cartesian product of massa rows × DNS entries.
  - `ToCsv` — RFC-4180 output with UTF-8 BOM (`\uFEFF`).
- **CORS** — `AllowAnyOrigin / AllowAnyMethod / AllowAnyHeader` is configured via
  `builder.Services.AddCors` and activated with `app.UseCors()`.
- **JSON** — uses `camelCase` property naming via `ConfigureHttpJsonOptions`.

---

## Project structure

```
massas-dns/csharp/
├── MassasDns.csproj   # SDK-style project file targeting net8.0
├── Program.cs         # All routes, records, and service logic
└── README.md          # This file
```
