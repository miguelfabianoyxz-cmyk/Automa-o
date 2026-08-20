# Massas & DNS — Swift / Vapor

## Requisitos

- Swift 5.9+
- Xcode 15+ (macOS) ou Swift toolchain (Linux)

## Execução

```bash
swift run
```

Acesse: http://localhost:8050

## Endpoints

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/` | Info do serviço (nome, versão, status) |
| `GET` | `/health` | Health-check `{"status":"ok"}` |
| `POST` | `/api/parse` | Parseia massas + DNS e retorna JSON estruturado |
| `POST` | `/api/export/csv` | Retorna tabela combinada como arquivo `.csv` |
| `POST` | `/api/export/json` | Retorna tabela combinada como array-of-objects `.json` |

## Payload — `/api/parse` e `/api/export/*`

```json
{
  "massas": "<texto CSV/TSV colado>",
  "dns":    "<lista de URLs, uma por linha>"
}
```

O campo `type` é aceito (mas ignorado) nas rotas `/api/export/*` por compatibilidade.

### Resposta de `/api/parse`

```json
{
  "massas":   { "headers": [...], "rows": [[...], ...] },
  "dns":      [{ "idx": 1, "env": "PRD", "url": "https://..." }, ...],
  "combined": { "headers": [...], "rows": [[...], ...] }
}
```

## Detecção automática

| Recurso | Comportamento |
|---------|---------------|
| Separador | Detectado por contagem de `\t`, `;` e `,` na linha de cabeçalho |
| Cabeçalho | Primeira linha cujos campos batem com `cpf`, `nome`, `conta`, `agência`, `agencia`, `agency`, `email`, `telefone` |
| Ambiente DNS | Heurística por substring: `homolog/hml → HML`, `staging/stg → STG`, `dev → DEV`, `qa → QA`, `uat → UAT`, demais → `PRD` |

## Estrutura do projeto

```
massas-dns/swift/
├── Package.swift
├── README.md
└── Sources/
    └── App/
        └── main.swift
```

## Build para produção

```bash
swift build -c release
.build/release/App
```

## Docker (opcional)

```dockerfile
FROM swift:5.9-jammy AS build
WORKDIR /app
COPY . .
RUN swift build -c release

FROM ubuntu:22.04
WORKDIR /app
COPY --from=build /app/.build/release/App .
EXPOSE 8050
CMD ["./App"]
```
