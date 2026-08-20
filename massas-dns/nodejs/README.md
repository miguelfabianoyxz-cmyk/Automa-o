# Massas & DNS — Node.js / Express

Servidor backend em **Node.js 18+ com Express** para a automação de Massas & DNS.

## Requisitos

| Dependência | Versão mínima |
|---|---|
| Node.js | 18.0.0 |
| npm | 8.0.0 |

## Instalação e execução

```bash
# Instalar dependências
npm install

# Produção
npm start          # porta 8080

# Desenvolvimento (hot-reload via nodemon)
npm run dev
```

Abra [http://localhost:8080](http://localhost:8080) no navegador.

## Endpoints

| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/` | Serve o frontend `automacao-massas-dns.html` |
| `GET` | `/health` | Status da aplicação |
| `POST` | `/api/parse` | Parseia massas + DNS, retorna JSON estruturado + combinado |
| `POST` | `/api/export/csv` | Download CSV (massas, dns ou combinado) |
| `POST` | `/api/export/json` | Download JSON completo |

### `POST /api/parse`

**Request:**
```json
{
  "massas": "CPF,Nome,Conta\n123.456.789-00,João,12345-6",
  "dns": "HML app.hml.banco.com.br\nPROD app.prod.banco.com.br"
}
```

**Response:**
```json
{
  "massas":   { "headers": ["CPF","Nome","Conta"], "rows": [["123.456.789-00","João","12345-6"]] },
  "dns":      [{ "idx": 1, "env": "HML", "url": "app.hml.banco.com.br" }],
  "combined": { "headers": ["CPF","Nome","Conta","Ambiente","URL / DNS"], "rows": [...] }
}
```

### `POST /api/export/csv`

**Request:**
```json
{
  "type": "massas",
  "massasData": { "headers": [...], "rows": [[...]] }
}
```

Tipos válidos: `massas` | `dns` | `combinado`

### `POST /api/export/json`

Mesma estrutura do `/api/parse`. Retorna arquivo `massas-dns.json` como download.

## Lógica de inferência de ambiente

| Substring na URL | Badge |
|---|---|
| `hml`, `homolog` | `HML` |
| `prd`, `prod` | `PROD` |
| `dev` | `DEV` |
| `sit` | `SIT` |
| `uat` | `UAT` |
| `qas` | `QAS` |
| (nenhuma) | `UNKNOWN` |

## Estrutura

```
nodejs/
├── server.js       # Servidor Express + parser + rotas
├── package.json    # Dependências
└── README.md       # Este arquivo
```
