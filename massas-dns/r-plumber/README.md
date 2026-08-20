# Massas & DNS — R / Plumber

Backend REST para a ferramenta de automação **Massas & DNS**, implementado em **R** com o framework [Plumber](https://www.rplumber.io/).

---

## Requisitos

| Item | Versão mínima |
|------|--------------|
| R    | 4.2+         |
| plumber  | 1.2+     |
| jsonlite | qualquer |

---

## Instalação

```r
install.packages(c("plumber", "jsonlite"))
```

---

## Execução

```bash
Rscript run.R
```

Acesse: <http://localhost:8040>

---

## Endpoints

| Método | Caminho          | Descrição                                                    |
|--------|-----------------|--------------------------------------------------------------|
| GET    | `/`             | Serve o front-end HTML (`automacao-massas-dns.html`)         |
| POST   | `/api/parse`    | Recebe `{ massas, dns }` (texto) e retorna JSON estruturado  |
| POST   | `/api/export/csv` | Recebe `{ massas, dns }` e devolve CSV como attachment      |
| GET    | `/health`       | Health-check — retorna `{ status, language, framework }`     |

---

## Contrato da API

### `POST /api/parse`

**Request body** (JSON):

```json
{
  "massas": "cpf;nome;conta\n12345678900;Alice;001\n98765432100;Bob;002",
  "dns": "https://api-hml.banco.com.br\nhttps://api-prd.banco.com.br"
}
```

**Response** (JSON):

```json
{
  "massas": {
    "headers": ["cpf", "nome", "conta"],
    "rows": [
      { "cpf": "12345678900", "nome": "Alice", "conta": "001" },
      { "cpf": "98765432100", "nome": "Bob",   "conta": "002" }
    ]
  },
  "dns": [
    { "idx": 1, "env": "HML",  "url": "https://api-hml.banco.com.br" },
    { "idx": 2, "env": "PROD", "url": "https://api-prd.banco.com.br" }
  ],
  "combined": {
    "headers": ["cpf", "nome", "conta", "dns_env", "dns_url"],
    "rows": [ ... ]
  }
}
```

### `POST /api/export/csv`

Mesma estrutura de body que `/api/parse`. Retorna um arquivo `.csv` com o produto cartesiano entre as massas e os ambientes DNS.

**Response headers:**
```
Content-Type: text/csv; charset=utf-8
Content-Disposition: attachment; filename="massas-dns-export.csv"
```

### `GET /health`

```json
{ "status": "ok", "language": "R", "framework": "Plumber" }
```

---

## Inferência de ambiente (DNS)

A função `infer_env()` analisa a URL e classifica o ambiente:

| Padrão na URL       | Ambiente |
|---------------------|----------|
| `hml` / `homolog`   | HML      |
| `prd` / `prod`      | PROD     |
| `dev`               | DEV      |
| `sit`               | SIT      |
| `uat`               | UAT      |
| `qas`               | QAS      |
| *(nenhum)*          | UNKNOWN  |

---

## Estrutura do projeto

```
r-plumber/
├── plumber.R   # Definição da API (rotas, filtros, helpers)
├── run.R       # Entry-point — sobe o servidor na porta 8040
└── README.md   # Esta documentação
```

---

## CORS

Todas as respostas incluem:

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
```

Requisições `OPTIONS` (preflight) são respondidas com `204 No Content`.
