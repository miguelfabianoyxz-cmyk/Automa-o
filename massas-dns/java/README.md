# Massas & DNS — Java / Spring Boot

Backend REST API for the **Massas & DNS** automation tool.  
Parses raw "massas" (test-data tables) and DNS URL lists, combines them, and exposes export endpoints for CSV and JSON.

---

## Requisitos

| Tool | Versão mínima |
|------|--------------|
| Java | 17+ |
| Maven | 3.8+ |

---

## Execução

```bash
# Com o wrapper Maven incluído no projeto:
./mvnw spring-boot:run

# Ou com o Maven instalado localmente:
mvn spring-boot:run
```

Acesse: <http://localhost:8080>

---

## Endpoints

| Método | Caminho | Descrição | Content-Type (req) | Resposta |
|--------|---------|-----------|-------------------|----------|
| `GET` | `/` | Serve o `index.html` estático (UI) | — | `text/html` |
| `GET` | `/health` | Health-check | — | `application/json` |
| `POST` | `/api/parse` | Analisa massas + DNS e retorna JSON estruturado | `application/json` | `application/json` |
| `POST` | `/api/export/csv` | Exporta tabela combinada como arquivo CSV | `application/json` | `text/csv` (attachment) |
| `POST` | `/api/export/json` | Exporta resultado completo como arquivo JSON | `application/json` | `application/json` (attachment) |

### Corpo da requisição (`/api/parse`, `/api/export/csv`, `/api/export/json`)

```json
{
  "massas": "<texto bruto da tabela de massas — separado por tab, ponto-e-vírgula ou vírgula>",
  "dns":    "<lista de URLs, uma por linha>"
}
```

### Exemplo — `/api/parse`

```bash
curl -s -X POST http://localhost:8080/api/parse \
  -H "Content-Type: application/json" \
  -d '{
    "massas": "cpf\tnome\tconta\n12345678900\tJoão Silva\t0001-1",
    "dns":    "https://api.hml.itau.com.br/v1\nhttps://api.prod.itau.com.br/v1"
  }' | jq .
```

### Exemplo — `/api/export/csv`

```bash
curl -s -X POST http://localhost:8080/api/export/csv \
  -H "Content-Type: application/json" \
  -d '{"massas":"cpf\tnome\n111\tAna","dns":"https://dev.example.com"}' \
  -o export.csv
```

### Resposta — `/health`

```json
{
  "status":    "ok",
  "language":  "Java",
  "framework": "Spring Boot"
}
```

---

## UI estática

Coloque um arquivo `index.html` em:

```
src/main/resources/static/index.html
```

O endpoint `GET /` o servirá automaticamente.  
Se o arquivo não existir, uma página de fallback mínima é exibida.

---

## Estrutura do projeto

```
massas-dns/java/
├── pom.xml
├── README.md
└── src/main/java/com/itau/massasdns/
    ├── MassasDnsApplication.java
    ├── controller/
    │   └── MassasDnsController.java     ← endpoints REST + export
    ├── service/
    │   └── ParserService.java           ← parsing, inferência de env, combinação
    └── model/
        ├── ParseRequest.java            ← record { massas, dns }
        ├── ParseResponse.java           ← record { massas, dns, combined }
        ├── MassaData.java               ← record { headers, rows }
        ├── DNSEntry.java                ← record { idx, env, url }
        └── CombinedData.java            ← record { headers, rows }
```

---

## Build para produção

```bash
mvn clean package -DskipTests
java -jar target/massas-dns-1.0.0.jar
```
