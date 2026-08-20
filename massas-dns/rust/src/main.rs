use actix_cors::Cors;
use actix_web::{get, post, web, App, HttpResponse, HttpServer, Responder};
use serde::{Deserialize, Serialize};
use std::fs;

// ---------------------------------------------------------------------------
// Data structures
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize, Deserialize, Clone)]
struct ParseRequest {
    massas: String,
    dns: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
struct MassaData {
    headers: Vec<String>,
    rows: Vec<Vec<String>>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
struct DnsEntry {
    idx: usize,
    env: String,
    url: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
struct CombinedData {
    headers: Vec<String>,
    rows: Vec<Vec<String>>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
struct ParseResponse {
    massas: MassaData,
    dns: Vec<DnsEntry>,
    combined: CombinedData,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
struct ExportRequest {
    r#type: String,
    massas: String,
    dns: String,
}

// ---------------------------------------------------------------------------
// Parser helpers
// ---------------------------------------------------------------------------

/// Detect the field separator used in a line: tab, semicolon, or comma.
fn detect_sep(line: &str) -> char {
    if line.contains('\t') {
        '\t'
    } else if line.contains(';') {
        ';'
    } else {
        ','
    }
}

/// Parse raw massas CSV/TSV text into a [`MassaData`] struct.
fn parse_massa(raw: &str) -> MassaData {
    let lines: Vec<&str> = raw
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .collect();

    if lines.is_empty() {
        return MassaData {
            headers: vec![],
            rows: vec![],
        };
    }

    let sep = detect_sep(lines[0]);

    let headers: Vec<String> = lines[0]
        .split(sep)
        .map(|h| h.trim().to_string())
        .collect();

    let rows: Vec<Vec<String>> = lines[1..]
        .iter()
        .map(|line| {
            line.split(sep)
                .map(|cell| cell.trim().to_string())
                .collect()
        })
        .collect();

    MassaData { headers, rows }
}

/// Infer environment tag from a URL string.
fn infer_env(url: &str) -> String {
    let lower = url.to_lowercase();
    if lower.contains("prod") {
        "PROD".to_string()
    } else if lower.contains("hom") || lower.contains("homolog") {
        "HOM".to_string()
    } else if lower.contains("dev") {
        "DEV".to_string()
    } else if lower.contains("sit") {
        "SIT".to_string()
    } else if lower.contains("uat") {
        "UAT".to_string()
    } else {
        "N/A".to_string()
    }
}

/// Parse raw DNS text (one URL per line, optional `env|url` format) into a
/// [`Vec<DnsEntry>`].
fn parse_dns(raw: &str) -> Vec<DnsEntry> {
    raw.lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .enumerate()
        .map(|(idx, line)| {
            // Support optional "ENV|URL" or "ENV;URL" or "ENV URL" split
            if let Some(pos) = line.find('|') {
                let env = line[..pos].trim().to_uppercase();
                let url = line[pos + 1..].trim().to_string();
                DnsEntry { idx, env, url }
            } else if line.contains(';') {
                let parts: Vec<&str> = line.splitn(2, ';').collect();
                let env = parts[0].trim().to_uppercase();
                let url = parts.get(1).map(|s| s.trim()).unwrap_or("").to_string();
                DnsEntry { idx, env, url }
            } else {
                // No explicit env — infer from URL content
                let url = line.to_string();
                let env = infer_env(&url);
                DnsEntry { idx, env, url }
            }
        })
        .collect()
}

/// Combine massas headers/rows with DNS entries into a single table.
fn build_combined(massas: &MassaData, dns: &[DnsEntry]) -> CombinedData {
    let mut headers = massas.headers.clone();
    headers.push("dns_env".to_string());
    headers.push("dns_url".to_string());

    let dns_lookup: std::collections::HashMap<usize, &DnsEntry> =
        dns.iter().map(|e| (e.idx, e)).collect();

    let rows: Vec<Vec<String>> = massas
        .rows
        .iter()
        .enumerate()
        .map(|(i, row)| {
            let mut combined_row = row.clone();
            if let Some(entry) = dns_lookup.get(&i) {
                combined_row.push(entry.env.clone());
                combined_row.push(entry.url.clone());
            } else {
                combined_row.push(String::new());
                combined_row.push(String::new());
            }
            combined_row
        })
        .collect();

    CombinedData { headers, rows }
}

// ---------------------------------------------------------------------------
// Route handlers
// ---------------------------------------------------------------------------

/// `GET /` — serve the frontend HTML file.
#[get("/")]
async fn index() -> impl Responder {
    match fs::read_to_string("../automacao-massas-dns.html") {
        Ok(content) => HttpResponse::Ok()
            .content_type("text/html; charset=utf-8")
            .body(content),
        Err(e) => HttpResponse::InternalServerError()
            .body(format!("Failed to read HTML file: {e}")),
    }
}

/// `GET /health` — liveness probe.
#[get("/health")]
async fn health() -> impl Responder {
    HttpResponse::Ok().json(serde_json::json!({
        "status": "ok",
        "language": "Rust",
        "framework": "Actix-web"
    }))
}

/// `POST /api/parse` — parse massas + DNS and return combined data.
#[post("/api/parse")]
async fn api_parse(body: web::Json<ParseRequest>) -> impl Responder {
    let massas = parse_massa(&body.massas);
    let dns = parse_dns(&body.dns);
    let combined = build_combined(&massas, &dns);

    let response = ParseResponse {
        massas,
        dns,
        combined,
    };

    HttpResponse::Ok().json(response)
}

/// `POST /api/export/csv` — export the requested table as a CSV download.
#[post("/api/export/csv")]
async fn api_export_csv(body: web::Json<ExportRequest>) -> impl Responder {
    let massas = parse_massa(&body.massas);
    let dns = parse_dns(&body.dns);
    let combined = build_combined(&massas, &dns);

    let (headers, rows) = match body.r#type.as_str() {
        "massas" => (massas.headers.clone(), massas.rows.clone()),
        "dns" => {
            let headers = vec!["idx".to_string(), "env".to_string(), "url".to_string()];
            let rows = dns
                .iter()
                .map(|e| vec![e.idx.to_string(), e.env.clone(), e.url.clone()])
                .collect();
            (headers, rows)
        }
        _ => (combined.headers.clone(), combined.rows.clone()),
    };

    let mut csv = String::new();
    csv.push_str(&headers.join(","));
    csv.push('\n');
    for row in &rows {
        let escaped: Vec<String> = row
            .iter()
            .map(|cell| {
                if cell.contains(',') || cell.contains('"') || cell.contains('\n') {
                    format!("\"{}\"", cell.replace('"', "\"\""))
                } else {
                    cell.clone()
                }
            })
            .collect();
        csv.push_str(&escaped.join(","));
        csv.push('\n');
    }

    HttpResponse::Ok()
        .content_type("text/csv; charset=utf-8")
        .insert_header((
            "Content-Disposition",
            format!("attachment; filename=\"{}.csv\"", body.r#type),
        ))
        .body(csv)
}

/// `POST /api/export/json` — export the requested table as a JSON download.
#[post("/api/export/json")]
async fn api_export_json(body: web::Json<ExportRequest>) -> impl Responder {
    let massas = parse_massa(&body.massas);
    let dns = parse_dns(&body.dns);
    let combined = build_combined(&massas, &dns);

    let payload: serde_json::Value = match body.r#type.as_str() {
        "massas" => serde_json::json!({ "headers": massas.headers, "rows": massas.rows }),
        "dns" => serde_json::json!(dns),
        _ => serde_json::json!({ "headers": combined.headers, "rows": combined.rows }),
    };

    let json_bytes = serde_json::to_vec_pretty(&payload).unwrap_or_default();

    HttpResponse::Ok()
        .content_type("application/json; charset=utf-8")
        .insert_header((
            "Content-Disposition",
            format!("attachment; filename=\"{}.json\"", body.r#type),
        ))
        .body(json_bytes)
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    println!("🦀 Massas & DNS — Actix-web listening on http://0.0.0.0:8090");

    HttpServer::new(|| {
        let cors = Cors::default()
            .allow_any_origin()
            .allow_any_method()
            .allow_any_header()
            .max_age(3600);

        App::new()
            .wrap(cors)
            .service(index)
            .service(health)
            .service(api_parse)
            .service(api_export_csv)
            .service(api_export_json)
    })
    .bind("0.0.0.0:8090")?
    .run()
    .await
}
