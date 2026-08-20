# Massas & DNS — PHP

## Requisitos
- PHP 8.1+

## Execução
```bash
php -S localhost:8088 index.php
```

Acesse: http://localhost:8088

## Endpoints table

| Método | Rota | Descrição |
| --- | --- | --- |
| GET | `/` | Retorna o conteúdo de [`automacao-massas-dns.html`](../automacao-massas-dns.html) |
| POST | `/api/parse` | Faz o parse de `{ massas, dns }` e retorna `massas`, `dns` e `combined` |
| POST | `/api/export/csv` | Retorna download de CSV |
| POST | `/api/export/json` | Retorna download de JSON |
| GET | `/health` | Retorna status de saúde da aplicação |
