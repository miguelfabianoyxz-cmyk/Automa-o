# Massas & DNS — Rust / Actix-web

Backend para a ferramenta de automação **Massas & DNS**, implementado em Rust com
o framework [Actix-web](https://actix.rs/).

## Requisitos

- Rust 1.75+
- Cargo (incluído na instalação padrão do Rust via `rustup`)

## Execução

```bash
cargo run
```

O servidor sobe em **http://localhost:8090**.

> O arquivo `../automacao-massas-dns.html` deve existir no diretório pai para
> que a rota `GET /` funcione corretamente.

## Endpoints

| Método | Rota               | Descrição                                              |
|--------|--------------------|--------------------------------------------------------|
| GET    | `/`                | Serve o frontend HTML (`automacao-massas-dns.html`)    |
| GET    | `/health`          | Liveness probe — retorna `{ status, language, framework }` |
| POST   | `/api/parse`       | Analisa massas + DNS e retorna os dados combinados     |
| POST   | `/api/export/csv`  | Exporta a tabela selecionada como arquivo CSV          |
| POST   | `/api/export/json` | Exporta a tabela selecionada como arquivo JSON         |

## Payloads

### `POST /api/parse`

```json
{
  "massas": "<texto CSV/TSV das massas>",
  "dns":    "<texto com as entradas DNS>"
}
```

Resposta:

```json
{
  "massas":   { "headers": [...], "rows": [[...], ...] },
  "dns":      [{ "idx": 0, "env": "PROD", "url": "https://..." }, ...],
  "combined": { "headers": [...], "rows": [[...], ...] }
}
```

### `POST /api/export/csv` e `POST /api/export/json`

```json
{
  "type":   "massas" | "dns" | "combined",
  "massas": "<texto CSV/TSV das massas>",
  "dns":    "<texto com as entradas DNS>"
}
```

Retorna o arquivo com o header `Content-Disposition: attachment`.

## Build de produção

```bash
cargo build --release
./target/release/massas-dns
```
