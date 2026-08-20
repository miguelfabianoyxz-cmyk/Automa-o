# Massas & DNS — Kotlin / Ktor

Backend server for the **Massas & DNS** automation tool, written in Kotlin with the [Ktor](https://ktor.io/) framework.

## Requisitos

| Ferramenta | Versão mínima |
|-----------|---------------|
| JDK       | 17+           |
| Gradle    | bundled (wrapper) |

## Execução

```bash
# From massas-dns/kotlin/
./gradlew run
```

Acesse: <http://localhost:8070>

> The server must be started from `massas-dns/kotlin/` so that the relative path
> `../automacao-massas-dns.html` resolves correctly to the project root.

## Endpoints

| Method | Path               | Description                                              |
|--------|--------------------|----------------------------------------------------------|
| `GET`  | `/`                | Serves `automacao-massas-dns.html` from the project root |
| `POST` | `/api/parse`       | Parses massa + DNS text → `ParseResponse` JSON           |
| `POST` | `/api/export/csv`  | Returns a `.csv` file attachment                         |
| `POST` | `/api/export/json` | Returns a `.json` file attachment                        |
| `GET`  | `/health`          | Health check → `{ status, language, framework }`         |

## Request / Response shapes

### `POST /api/parse`

**Request body**
```json
{
  "massas": "cpf;nome;conta\n123;João;001",
  "dns": "HML  app.hml.banco.com.br\nPROD app.prod.banco.com.br"
}
```

**Response body**
```json
{
  "massas":   { "headers": [...], "rows": [[...]] },
  "dns":      [{ "idx": 0, "env": "HML", "url": "app.hml.banco.com.br" }],
  "combined": { "headers": [...], "rows": [[...]] }
}
```

### `POST /api/export/csv` and `POST /api/export/json`

**Request body**
```json
{
  "type":   "massas | dns | combinado",
  "massas": "<raw text>",
  "dns":    "<raw text>"
}
```

Returns a file attachment (`Content-Disposition: attachment`).

## Estrutura do projeto

```
kotlin/
├── build.gradle.kts
├── settings.gradle.kts
└── src/main/kotlin/com/itau/massasdns/
    └── Application.kt          ← entry point + routes + ParserService
```

## Lógica de parsing

- **Separador** detectado automaticamente: `\t` → `;` → `,`
- **Cabeçalho** de massa inferido pelos nomes conhecidos: `cpf`, `nome`, `conta`, `agência`, `email`, `telefone`
- **Ambiente DNS** inferido a partir da URL: `hml`, `prod`, `dev`, `sit`, `qas`, `uat`, `stg`
- **Tabela combinada**: produto cartesiano linhas × entradas DNS
