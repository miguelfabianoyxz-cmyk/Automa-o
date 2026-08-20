# Massas & DNS — Ruby / Sinatra

Backend para a ferramenta de automação **Massas & DNS**, implementado em Ruby com o microframework Sinatra.

---

## Requisitos

- Ruby 3.1+
- Bundler (`gem install bundler`)

---

## Instalação

```bash
bundle install
```

---

## Execução

```bash
ruby app.rb
```

Acesse: <http://localhost:4567>

---

## Endpoints

| Método | Rota               | Descrição                                                  |
|--------|--------------------|------------------------------------------------------------|
| GET    | `/`                | Serve o front-end `automacao-massas-dns.html`              |
| GET    | `/health`          | Health check — retorna `{ status, language, framework }`  |
| POST   | `/api/parse`       | Faz o parse do texto de massas e DNS; retorna JSON         |
| POST   | `/api/export/csv`  | Exporta o resultado como arquivo `.csv`                    |
| POST   | `/api/export/json` | Exporta o resultado como arquivo `.json`                   |

---

## Corpo das requisições POST

### `/api/parse`

```json
{
  "massa": "<texto CSV/TSV com as massas>",
  "dns":   "<URLs, uma por linha>"
}
```

**Resposta:**

```json
{
  "massas":   { "headers": ["cpf", "nome", ...], "rows": [...] },
  "dns":      [{ "idx": 1, "env": "HML", "url": "https://..." }],
  "combined": { "headers": [...], "rows": [...] }
}
```

---

### `/api/export/csv` e `/api/export/json`

```json
{
  "massa":    "<texto das massas>",
  "dns":      "<URLs>",
  "mode":     "combined",
  "filename": "resultado.csv"
}
```

`mode` aceita: `combined` (padrão), `massas`, `dns`.

---

## Inferência de ambiente (`infer_env`)

| Padrão na URL         | Ambiente |
|-----------------------|----------|
| `hml` / `homolog`     | HML      |
| `prd` / `prod`        | PRD      |
| `dev`                 | DEV      |
| `sit`                 | SIT      |
| `uat`                 | UAT      |
| `qas`                 | QAS      |
| (nenhum dos acima)    | UNKNOWN  |

---

## Estrutura do projeto

```
massas-dns/ruby/
├── app.rb      # Aplicação Sinatra
├── Gemfile     # Dependências
└── README.md   # Este arquivo
```
