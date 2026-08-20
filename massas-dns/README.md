# Massas & DNS — Automação Itaú

Automação de massas de dados e ambientes DNS implementada em **12 linguagens de programação**, cada uma com seu próprio servidor backend e compartilhando o mesmo frontend HTML.

---

## Frontend

O arquivo [`automacao-massas-dns.html`](../automacao-massas-dns.html) é o frontend compartilhado por todas as implementações. Basta abrir diretamente no navegador **ou** servir via qualquer um dos backends abaixo.

**Funcionalidades do frontend:**
- Cole CSV/Excel ou arraste arquivos `.csv`/`.txt`
- Detecção automática de separadores (`,` `;` tab)
- Detecção automática de cabeçalho
- Contador ao vivo de linhas
- Modo escuro / claro (persiste via `localStorage`)
- 3 abas: Massas · DNS · Visão Combinada (produto cartesiano)
- Barra de estatísticas
- Filtro em tempo real com highlight
- Ordenação por coluna (clique no cabeçalho)
- Paginação (25 por página)
- Export CSV, TSV e JSON
- Atalho `⌘/Ctrl + Enter` para gerar tabelas

---

## Implementações por linguagem

| # | Pasta | Linguagem | Framework | Porta |
|---|---|---|---|---|
| 1 | [`python/`](python/) | Python 3.10+ | Flask 3 | **8000** |
| 2 | [`nodejs/`](nodejs/) | Node.js 18+ | Express 4 | **8080** |
| 3 | [`java/`](java/) | Java 17 | Spring Boot 3.2 | **8010** |
| 4 | [`go/`](go/) | Go 1.21+ | net/http (stdlib) | **8020** |
| 5 | [`php/`](php/) | PHP 8.1+ | Built-in server | **8088** |
| 6 | [`ruby/`](ruby/) | Ruby 3.2+ | Sinatra 3 | **8030** |
| 7 | [`rust/`](rust/) | Rust 1.75+ | Actix-web 4 | **8050** |
| 8 | [`csharp/`](csharp/) | C# 12 | .NET 8 Minimal API | **8090** |
| 9 | [`kotlin/`](kotlin/) | Kotlin 1.9+ | Ktor 2.3 | **8070** |
| 10 | [`swift/`](swift/) | Swift 5.9+ | Vapor 4 | **8050** |
| 11 | [`typescript-deno/`](typescript-deno/) | TypeScript / Deno 1.40+ | Oak 12 | **8060** |
| 12 | [`r-plumber/`](r-plumber/) | R 4.2+ | Plumber 1.2 | **8040** |

---

## API — Endpoints comuns

Todas as implementações expõem os mesmos endpoints:

| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/` | Serve o frontend HTML |
| `GET` | `/health` | Status + linguagem + framework |
| `POST` | `/api/parse` | Parseia massas + DNS → JSON estruturado + visão combinada |
| `POST` | `/api/export/csv` | Download CSV (massas / dns / combinado) |
| `POST` | `/api/export/json` | Download JSON completo |

### `POST /api/parse` — Exemplo

**Request:**
```json
{
  "massas": "CPF,Nome,Conta,Agência\n123.456.789-00,João Silva,12345-6,0032",
  "dns":    "HML app.hml.banco.com.br\nPROD app.prod.banco.com.br"
}
```

**Response:**
```json
{
  "massas": {
    "headers": ["CPF", "Nome", "Conta", "Agência"],
    "rows":    [["123.456.789-00", "João Silva", "12345-6", "0032"]]
  },
  "dns": [
    { "idx": 1, "env": "HML",  "url": "app.hml.banco.com.br" },
    { "idx": 2, "env": "PROD", "url": "app.prod.banco.com.br" }
  ],
  "combined": {
    "headers": ["CPF", "Nome", "Conta", "Agência", "Ambiente", "URL / DNS"],
    "rows": [
      ["123.456.789-00", "João Silva", "12345-6", "0032", "HML",  "app.hml.banco.com.br"],
      ["123.456.789-00", "João Silva", "12345-6", "0032", "PROD", "app.prod.banco.com.br"]
    ]
  }
}
```

---

## Inferência de ambiente

| Substring na URL | Badge gerado |
|---|---|
| `hml`, `homolog` | `HML` |
| `prd`, `prod` | `PROD` |
| `dev` | `DEV` |
| `sit` | `SIT` |
| `uat` | `UAT` |
| `qas` | `QAS` |
| (nenhuma) | `UNKNOWN` / `—` |

Você também pode declarar o ambiente explicitamente prefixando a linha:
```
HML   app.hml.banco.com.br
PROD  app.prod.banco.com.br
```

---

## Como executar cada versão

### 🐍 Python (Flask)
```bash
cd python
pip install -r requirements.txt
python app.py          # http://localhost:8000
```

### 🟩 Node.js (Express)
```bash
cd nodejs
npm install
npm start              # http://localhost:8080
npm run dev            # hot-reload com nodemon
```

### ☕ Java (Spring Boot)
```bash
cd java
./mvnw spring-boot:run  # http://localhost:8010
```

### 🐹 Go (net/http)
```bash
cd go
go run main.go          # http://localhost:8020
```

### 🐘 PHP (Built-in server)
```bash
cd php
php -S localhost:8088 index.php
```

### 💎 Ruby (Sinatra)
```bash
cd ruby
bundle install
bundle exec ruby app.rb  # http://localhost:8030
```

### 🦀 Rust (Actix-web)
```bash
cd rust
cargo run               # http://localhost:8050
cargo build --release   # binário otimizado
```

### 🔷 C# (.NET 8)
```bash
cd csharp
dotnet run              # http://localhost:8090
dotnet watch run        # hot-reload
```

### 🎯 Kotlin (Ktor)
```bash
cd kotlin
./gradlew run           # http://localhost:8070
```

### 🦅 Swift (Vapor)
```bash
cd swift
swift run               # http://localhost:8050
```

### 🦕 TypeScript (Deno)
```bash
cd typescript-deno
deno task start         # http://localhost:8060
deno task dev           # com --watch
```

### 📊 R (Plumber)
```bash
cd r-plumber
Rscript run.R           # http://localhost:8040
```

---

## Estrutura do projeto

```
massas-dns/
├── automacao-massas-dns.html   ← Frontend compartilhado
│
├── python/
│   ├── app.py
│   ├── requirements.txt
│   └── README.md
│
├── nodejs/
│   ├── server.js
│   ├── package.json
│   └── README.md
│
├── java/
│   ├── pom.xml
│   ├── src/
│   └── README.md
│
├── go/
│   ├── main.go
│   ├── go.mod
│   └── README.md
│
├── php/
│   ├── index.php
│   └── README.md
│
├── ruby/
│   ├── app.rb
│   ├── Gemfile
│   └── README.md
│
├── rust/
│   ├── src/main.rs
│   ├── Cargo.toml
│   └── README.md
│
├── csharp/
│   ├── Program.cs
│   ├── MassasDns.csproj
│   └── README.md
│
├── kotlin/
│   ├── src/main/kotlin/...
│   ├── build.gradle.kts
│   └── README.md
│
├── swift/
│   ├── Sources/App/main.swift
│   ├── Package.swift
│   └── README.md
│
├── typescript-deno/
│   ├── main.ts
│   ├── deno.json
│   └── README.md
│
└── r-plumber/
    ├── plumber.R
    ├── run.R
    └── README.md
```

---

## Lógica do parser (comum a todas as linguagens)

```
Entrada: texto bruto (massas ou DNS)
         │
         ▼
1. Dividir por \n, filtrar linhas vazias
         │
         ▼
2. Detectar separador: tab > ; > ,
         │
         ▼
3. Verificar se primeira linha é cabeçalho
   (contém: cpf, nome, conta, agência, email, etc.)
         │
    ┌────┴────┐
   SIM       NÃO
    │         │
    │         └─ usar cabeçalho padrão: [CPF, Nome, Conta, Agência]
    │
    ▼
4. Mapear linhas para arrays de strings
         │
         ▼
5. (DNS) Inferir ambiente por substring da URL
         │
         ▼
6. (Combinado) Produto cartesiano massa × DNS
```

---

*Projeto desenvolvido para automação de testes — Itaú*
