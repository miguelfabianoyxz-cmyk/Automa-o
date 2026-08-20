import csv
import io
import json
import os
import re
from itertools import product

from flask import Flask, jsonify, request, send_file, send_from_directory
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

FRONTEND_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "automacao-massas-dns.html")
)

KNOWN_HEADERS = {"cpf", "nome", "conta", "agência", "agencia", "agency", "email", "telefone"}
DEFAULT_HEADERS = ["CPF", "Nome", "Conta", "Agência"]

ENV_PATTERNS = [
    (re.compile(r"hml|homolog", re.IGNORECASE), "HML"),
    (re.compile(r"prd|prod", re.IGNORECASE), "PROD"),
    (re.compile(r"\bdev\b", re.IGNORECASE), "DEV"),
    (re.compile(r"\bsit\b", re.IGNORECASE), "SIT"),
    (re.compile(r"\buat\b", re.IGNORECASE), "UAT"),
    (re.compile(r"\bqas\b", re.IGNORECASE), "QAS"),
]

# ---------------------------------------------------------------------------
# Parser helpers
# ---------------------------------------------------------------------------


def detect_separator(text: str) -> str:
    """Return the dominant separator among tab, semicolon, comma."""
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if not lines:
        return "\t"
    sample = lines[0]
    for sep in ("\t", ";", ","):
        if sep in sample:
            return sep
    return "\t"


def infer_env(url: str) -> str:
    for pattern, label in ENV_PATTERNS:
        if pattern.search(url):
            return label
    return ""


def parse_massas(raw: str) -> dict:
    """Parse mass data and return {'headers': [...], 'rows': [[...]]}."""
    lines = [ln for ln in raw.splitlines() if ln.strip()]
    if not lines:
        return {"headers": DEFAULT_HEADERS, "rows": []}

    sep = detect_separator(raw)

    # Check whether the first row looks like a header row.
    first_cols = [c.strip() for c in lines[0].split(sep)]
    is_header = any(c.lower() in KNOWN_HEADERS for c in first_cols)

    if is_header:
        headers = first_cols
        data_lines = lines[1:]
    else:
        # Pad or trim defaults to match column count.
        col_count = len(first_cols)
        if col_count <= len(DEFAULT_HEADERS):
            headers = DEFAULT_HEADERS[:col_count]
        else:
            headers = DEFAULT_HEADERS + [f"Col{i}" for i in range(len(DEFAULT_HEADERS) + 1, col_count + 1)]
        data_lines = lines

    rows = []
    for line in data_lines:
        if not line.strip():
            continue
        cols = [c.strip() for c in line.split(sep)]
        # Pad short rows, trim long rows to match header length.
        while len(cols) < len(headers):
            cols.append("")
        rows.append(cols[: len(headers)])

    return {"headers": headers, "rows": rows}


def parse_dns(raw: str) -> list:
    """Parse DNS/environment entries. Returns list of {idx, env, url}."""
    entries = []
    idx = 1
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        tokens = line.split()
        if len(tokens) >= 2:
            env = tokens[0].upper()
            url = " ".join(tokens[1:])
        else:
            url = tokens[0]
            env = infer_env(url)
        entries.append({"idx": idx, "env": env, "url": url})
        idx += 1
    return entries


def build_combined(massas: dict, dns_entries: list) -> list:
    """Cartesian product of massas rows × dns entries."""
    headers = massas["headers"]
    rows = massas["rows"]
    combined = []
    for row, dns in product(rows, dns_entries):
        record = dict(zip(headers, row))
        record["ambiente"] = dns["env"]
        record["url"] = dns["url"]
        combined.append(record)
    return combined


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@app.get("/")
def index():
    return send_file(FRONTEND_PATH)


@app.get("/health")
def health():
    return jsonify({"status": "ok", "language": "Python", "framework": "Flask"})


@app.post("/api/parse")
def api_parse():
    body = request.get_json(force=True, silent=True) or {}
    raw_massas = body.get("massas", "")
    raw_dns = body.get("dns", "")

    massas = parse_massas(raw_massas)
    dns_entries = parse_dns(raw_dns)
    combined = build_combined(massas, dns_entries)

    return jsonify({"massas": massas, "dns": dns_entries, "combined": combined})


@app.post("/api/export/csv")
def api_export_csv():
    body = request.get_json(force=True, silent=True) or {}
    export_type = body.get("type", "combined")
    raw_massas = body.get("massas", "")
    raw_dns = body.get("dns", "")

    massas = parse_massas(raw_massas)
    dns_entries = parse_dns(raw_dns)
    combined = build_combined(massas, dns_entries)

    buf = io.StringIO()
    writer = csv.writer(buf)

    if export_type == "massas":
        writer.writerow(massas["headers"])
        writer.writerows(massas["rows"])
        filename = "massas.csv"
    elif export_type == "dns":
        writer.writerow(["idx", "env", "url"])
        for entry in dns_entries:
            writer.writerow([entry["idx"], entry["env"], entry["url"]])
        filename = "dns.csv"
    else:
        if combined:
            writer.writerow(list(combined[0].keys()))
            for record in combined:
                writer.writerow(list(record.values()))
        filename = "combined.csv"

    buf.seek(0)
    return send_file(
        io.BytesIO(buf.getvalue().encode("utf-8-sig")),
        mimetype="text/csv",
        as_attachment=True,
        download_name=filename,
    )


@app.post("/api/export/json")
def api_export_json():
    body = request.get_json(force=True, silent=True) or {}
    raw_massas = body.get("massas", "")
    raw_dns = body.get("dns", "")

    massas = parse_massas(raw_massas)
    dns_entries = parse_dns(raw_dns)
    combined = build_combined(massas, dns_entries)

    payload = {"massas": massas, "dns": dns_entries, "combined": combined}
    buf = io.BytesIO(json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8"))

    return send_file(
        buf,
        mimetype="application/json",
        as_attachment=True,
        download_name="massas_dns.json",
    )


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5000)
