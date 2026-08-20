# Massas & DNS — Python / Flask

## Requisitos
- Python 3.10+
- pip

## Instalação
```bash
pip install -r requirements.txt
```

## Execução
```bash
python app.py
```

Acesse: http://localhost:5000

## Endpoints
| Método | Rota | Descrição |
|--------|------|-----------|
| GET | / | Interface web |
| POST | /api/parse | Parseia massas e DNS |
| POST | /api/export/csv | Exporta CSV |
| POST | /api/export/json | Exporta JSON |
| GET | /health | Health check |
