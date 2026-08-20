# Massas & DNS — TypeScript / Deno + Oak

Backend para a ferramenta de automação **Massas & DNS**, implementado em TypeScript rodando sobre o runtime **Deno** com o framework **Oak**.

## Requisitos

- [Deno](https://deno.land/) 1.40+

Sem `npm install`, sem `node_modules` — Deno baixa as dependências automaticamente na primeira execução.

## Execução

```bash
# Produção
deno task start

# Desenvolvimento (reinicia ao salvar)
deno task dev
```

Acesse: <http://localhost:8060>

## Endpoints

| Método | Rota               | Descrição                                              |
|--------|--------------------|--------------------------------------------------------|
| GET    | `/`                | Serve o frontend `automacao-massas-dns.html`           |
| GET    | `/health`          | Retorna status, linguagem, runtime e framework         |
| POST   | `/api/parse`       | Recebe `{ massas, dns }` e retorna JSON estruturado    |
| POST   | `/api/export/csv`  | Retorna arquivo `.csv` com os dados combinados         |
| POST   | `/api/export/json` | Retorna arquivo `.json` com todos os dados parseados   |

### Exemplo — `/api/parse`

**Request**
```json
{
  "massas": "cpf;nome;conta\n12345678900;João Silva;001-1",
  "dns": "https://api.hom.banco.com.br/v1"
}
```

**Response**
```json
{
  "massas": {
    "headers": ["cpf", "nome", "conta"],
    "rows": [["12345678900", "João Silva", "001-1"]]
  },
  "dns": [
    { "idx": 1, "env": "HOM", "url": "https://api.hom.banco.com.br/v1" }
  ],
  "combined": {
    "headers": ["cpf", "nome", "conta", "dns_idx", "dns_env", "dns_url"],
    "rows": [["12345678900", "João Silva", "001-1", "1", "HOM", "https://api.hom.banco.com.br/v1"]]
  }
}
```

## Estrutura

```
typescript-deno/
├── main.ts        # Servidor Oak — rotas, parser, exportação
├── deno.json      # Tasks e import map
└── README.md
```

## Lógica do parser

| Função           | Descrição                                                        |
|------------------|------------------------------------------------------------------|
| `detectSep`      | Detecta separador dominante (`\t`, `;`, `,`, `\|`) na linha     |
| `parseMassa`     | Localiza o cabeçalho pelo match com colunas conhecidas e extrai linhas |
| `parseDns`       | Extrai URLs/hostnames e infere ambiente por substring            |
| `inferEnv`       | Mapeia `hom/homo→HOM`, `uat→UAT`, `sit→SIT`, `dev→DEV`, default `PROD` |
| `buildCombined`  | Mescla colunas de massas e DNS linha a linha (zip com padding)   |
| `toCsv`          | Serializa headers + rows para CSV com escape de aspas duplas     |

## Permissões Deno

| Flag             | Motivo                                    |
|------------------|-------------------------------------------|
| `--allow-net`    | Escutar na porta 8060 e baixar Oak        |
| `--allow-read`   | Ler `automacao-massas-dns.html` do disco  |
