import Vapor

// MARK: - Models

struct ParseRequest: Content {
    var massas: String
    var dns: String
}

struct MassaData: Content {
    var headers: [String]
    var rows: [[String]]
}

struct DnsEntry: Content {
    var idx: Int
    var env: String
    var url: String
}

struct CombinedData: Content {
    var headers: [String]
    var rows: [[String]]
}

struct ParseResponse: Content {
    var massas: MassaData
    var dns: [DnsEntry]
    var combined: CombinedData
}

struct ExportRequest: Content {
    var type: String
    var massas: String
    var dns: String
}

// MARK: - Parser

enum Parser {

    static let knownHeaders: Set<String> = [
        "cpf", "nome", "conta", "agência", "agencia", "agency", "email", "telefone"
    ]

    /// Detects the field separator used in a CSV-like line.
    static func detectSep(_ line: String) -> Character {
        let candidates: [(Character, Int)] = [
            ("\t", line.filter { $0 == "\t" }.count),
            (";",  line.filter { $0 == ";" }.count),
            (",",  line.filter { $0 == "," }.count),
        ]
        return candidates.max(by: { $0.1 < $1.1 }).map(\.0) ?? ","
    }

    /// Parses raw CSV/TSV text into headers + row matrix.
    static func parseMassa(_ raw: String) -> MassaData {
        let lines = raw
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return MassaData(headers: [], rows: [])
        }

        // Find first line whose fields overlap with known headers
        var headerIdx = 0
        var sep: Character = ","

        for (i, line) in lines.enumerated() {
            let candidate = detectSep(line)
            let fields = line
                .split(separator: candidate, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            let overlap = fields.filter { knownHeaders.contains($0) }
            if !overlap.isEmpty {
                headerIdx = i
                sep = candidate
                break
            }
        }

        let headerLine = lines[headerIdx]
        sep = detectSep(headerLine)
        let headers = headerLine
            .split(separator: sep, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let rows: [[String]] = lines.dropFirst(headerIdx + 1).map { line in
            line
                .split(separator: sep, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        return MassaData(headers: headers, rows: rows)
    }

    /// Infers the environment label from a URL string.
    static func inferEnv(_ url: String) -> String {
        let lower = url.lowercased()
        if lower.contains("homolog") || lower.contains("hml") || lower.contains("-hml") {
            return "HML"
        }
        if lower.contains("staging") || lower.contains("stg") {
            return "STG"
        }
        if lower.contains("dev") || lower.contains("development") {
            return "DEV"
        }
        if lower.contains("qa") || lower.contains("quality") {
            return "QA"
        }
        if lower.contains("uat") {
            return "UAT"
        }
        return "PRD"
    }

    /// Parses raw DNS text (one URL per line, optionally with index/env prefix).
    static func parseDNS(_ raw: String) -> [DnsEntry] {
        let lines = raw
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.enumerated().compactMap { (i, line) -> DnsEntry? in
            // Accept lines that look like a URL (with or without scheme)
            let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
            let url: String
            if parts.count >= 2, let last = parts.last, last.contains(".") {
                url = last
            } else {
                url = line
            }
            guard url.contains(".") else { return nil }
            return DnsEntry(idx: i + 1, env: inferEnv(url), url: url)
        }
    }

    /// Combines massa rows with DNS entries into a single flat table.
    static func buildCombined(_ massas: MassaData, _ dns: [DnsEntry]) -> CombinedData {
        guard !massas.headers.isEmpty else {
            return CombinedData(headers: [], rows: [])
        }

        let extraHeaders = ["dns_idx", "dns_env", "dns_url"]
        let headers = massas.headers + extraHeaders

        var rows: [[String]] = []

        if dns.isEmpty {
            rows = massas.rows.map { row in
                let padded = padRow(row, to: massas.headers.count)
                return padded + ["", "", ""]
            }
        } else {
            for (ri, row) in massas.rows.enumerated() {
                let padded = padRow(row, to: massas.headers.count)
                let entry = dns.indices.contains(ri) ? dns[ri] : nil
                let dnsFields: [String] = [
                    entry.map { String($0.idx) } ?? "",
                    entry?.env ?? "",
                    entry?.url ?? "",
                ]
                rows.append(padded + dnsFields)
            }
        }

        return CombinedData(headers: headers, rows: rows)
    }

    /// Serialises headers + rows to RFC 4180 CSV.
    static func toCsv(_ headers: [String], _ rows: [[String]]) -> String {
        func escape(_ field: String) -> String {
            if field.contains(",") || field.contains("\"") || field.contains("\n") {
                return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return field
        }
        var lines = [headers.map(escape).joined(separator: ",")]
        lines += rows.map { $0.map(escape).joined(separator: ",") }
        return lines.joined(separator: "\n")
    }

    // MARK: Private helpers

    private static func padRow(_ row: [String], to count: Int) -> [String] {
        if row.count >= count { return Array(row.prefix(count)) }
        return row + Array(repeating: "", count: count - row.count)
    }
}

// MARK: - Application bootstrap

var env = try Environment.detect()
try LoggingSystem.bootstrap(from: &env)
let app = Application(env)
defer { app.shutdown() }

// CORS
let corsConfig = CORSMiddleware.Configuration(
    allowedOrigin: .all,
    allowedMethods: [.GET, .POST, .OPTIONS],
    allowedHeaders: [.accept, .authorization, .contentType, .origin]
)
app.middleware.use(CORSMiddleware(configuration: corsConfig))

// Port
app.http.server.configuration.port = 8050

// MARK: - Routes

// GET /
app.get { _ async in
    return Response(
        status: .ok,
        headers: HTTPHeaders([("Content-Type", "application/json")]),
        body: .init(string: #"{"service":"massas-dns","version":"1.0.0","status":"running"}"#)
    )
}

// GET /health
app.get("health") { _ async in
    return Response(
        status: .ok,
        headers: HTTPHeaders([("Content-Type", "application/json")]),
        body: .init(string: #"{"status":"ok"}"#)
    )
}

// POST /api/parse
app.post("api", "parse") { req async throws -> ParseResponse in
    let body = try req.content.decode(ParseRequest.self)
    let massas  = Parser.parseMassa(body.massas)
    let dns     = Parser.parseDNS(body.dns)
    let combined = Parser.buildCombined(massas, dns)
    return ParseResponse(massas: massas, dns: dns, combined: combined)
}

// POST /api/export/csv
app.post("api", "export", "csv") { req async throws -> Response in
    let body = try req.content.decode(ExportRequest.self)
    let massas  = Parser.parseMassa(body.massas)
    let dns     = Parser.parseDNS(body.dns)
    let combined = Parser.buildCombined(massas, dns)
    let csv = Parser.toCsv(combined.headers, combined.rows)
    return Response(
        status: .ok,
        headers: HTTPHeaders([
            ("Content-Type", "text/csv; charset=utf-8"),
            ("Content-Disposition", "attachment; filename=\"massas_dns_export.csv\""),
        ]),
        body: .init(string: csv)
    )
}

// POST /api/export/json
app.post("api", "export", "json") { req async throws -> Response in
    let body = try req.content.decode(ExportRequest.self)
    let massas  = Parser.parseMassa(body.massas)
    let dns     = Parser.parseDNS(body.dns)
    let combined = Parser.buildCombined(massas, dns)

    // Build array-of-objects JSON
    var objects: [[String: String]] = []
    for row in combined.rows {
        var obj: [String: String] = [:]
        for (i, header) in combined.headers.enumerated() {
            obj[header] = row.indices.contains(i) ? row[i] : ""
        }
        objects.append(obj)
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(objects)
    let json = String(data: data, encoding: .utf8) ?? "[]"

    return Response(
        status: .ok,
        headers: HTTPHeaders([
            ("Content-Type", "application/json; charset=utf-8"),
            ("Content-Disposition", "attachment; filename=\"massas_dns_export.json\""),
        ]),
        body: .init(string: json)
    )
}

try app.run()
