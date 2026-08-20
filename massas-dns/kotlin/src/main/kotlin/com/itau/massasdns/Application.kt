package com.itau.massasdns

import io.ktor.http.*
import io.ktor.http.content.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.plugins.cors.routing.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

// ── Data classes ─────────────────────────────────────────────────────────────

@Serializable
data class ParseRequest(val massas: String, val dns: String)

@Serializable
data class MassaData(val headers: List<String>, val rows: List<List<String>>)

@Serializable
data class DnsEntry(val idx: Int, val env: String, val url: String)

@Serializable
data class CombinedData(val headers: List<String>, val rows: List<List<String>>)

@Serializable
data class ParseResponse(
    val massas: MassaData,
    val dns: List<DnsEntry>,
    val combined: CombinedData
)

@Serializable
data class ExportRequest(val type: String, val massas: String, val dns: String)

// ── Parser service ────────────────────────────────────────────────────────────

object ParserService {

    private val knownHeaders = listOf(
        "cpf", "nome", "conta", "agência", "agencia", "agency", "email", "telefone"
    )

    /** Detect the delimiter used in a line (tab > semicolon > comma). */
    fun detectSep(line: String): Char = when {
        line.contains('\t')  -> '\t'
        line.contains(';')   -> ';'
        else                 -> ','
    }

    /** Parse raw massa text into headers + rows. */
    fun parseMassa(raw: String): MassaData {
        val lines = raw.trim().lines().filter { it.isNotBlank() }
        if (lines.isEmpty()) return MassaData(emptyList(), emptyList())

        val sep     = detectSep(lines.first())
        val allRows = lines.map { line -> line.split(sep).map { it.trim() } }

        // Determine whether the first row is a header by checking against known names.
        val firstLow = allRows.first().map { it.lowercase() }
        val isHeader = firstLow.any { cell -> knownHeaders.any { kh -> cell.contains(kh) } }

        return if (isHeader) {
            MassaData(
                headers = allRows.first(),
                rows    = allRows.drop(1)
            )
        } else {
            // Generate positional headers: Col1, Col2, …
            val cols = allRows.maxOf { it.size }
            MassaData(
                headers = (1..cols).map { "Col$it" },
                rows    = allRows
            )
        }
    }

    /** Parse raw DNS text into a list of DnsEntry objects. */
    fun parseDns(raw: String): List<DnsEntry> {
        val lines = raw.trim().lines().filter { it.isNotBlank() }
        return lines.mapIndexed { idx, line ->
            val parts = line.trim().split(Regex("\\s+"), limit = 2)
            when {
                parts.size == 2 -> {
                    // Could be "ENV  url" or "url  ENV"
                    val (a, b) = parts
                    if (a.startsWith("http", ignoreCase = true) || a.contains('.')) {
                        DnsEntry(idx, inferEnv(a), a)
                    } else {
                        DnsEntry(idx, a.uppercase(), b.trim())
                    }
                }
                parts.size == 1 -> {
                    val url = parts[0].trim()
                    DnsEntry(idx, inferEnv(url), url)
                }
                else -> DnsEntry(idx, "ENV${idx + 1}", line.trim())
            }
        }
    }

    /** Infer environment label from a URL string. */
    fun inferEnv(url: String): String {
        val u = url.lowercase()
        return when {
            "hml"  in u -> "HML"
            "prod" in u -> "PROD"
            "dev"  in u -> "DEV"
            "sit"  in u -> "SIT"
            "qas"  in u -> "QAS"
            "uat"  in u -> "UAT"
            "stg"  in u || "staging" in u -> "STG"
            else        -> "ENV"
        }
    }

    /** Cross-join massa rows with DNS entries, one row per (massa row × DNS entry). */
    fun buildCombined(massas: MassaData, dns: List<DnsEntry>): CombinedData {
        if (massas.rows.isEmpty() || dns.isEmpty()) {
            val headers = massas.headers + listOf("Ambiente", "URL")
            return CombinedData(headers, emptyList())
        }

        val headers = massas.headers + listOf("Ambiente", "URL")
        val rows = massas.rows.flatMap { row ->
            dns.map { entry ->
                // Pad the massa row to match header count before appending DNS columns.
                val padded = row + List((massas.headers.size - row.size).coerceAtLeast(0)) { "" }
                padded + listOf(entry.env, entry.url)
            }
        }
        return CombinedData(headers, rows)
    }
}

// ── CSV helper ────────────────────────────────────────────────────────────────

private fun toCsv(headers: List<String>, rows: List<List<String>>): String {
    fun escape(v: String) = "\"${v.replace("\"", "\"\"")}\""
    val header = headers.joinToString(",") { escape(it) }
    val body   = rows.joinToString("\n") { r -> r.joinToString(",") { escape(it) } }
    return if (body.isBlank()) header else "$header\n$body"
}

// ── Application entry point ───────────────────────────────────────────────────

fun main() {
    embeddedServer(Netty, port = 8070, host = "0.0.0.0", module = Application::module)
        .start(wait = true)
}

fun Application.module() {
    install(ContentNegotiation) {
        json(Json { prettyPrint = true; ignoreUnknownKeys = true })
    }

    install(CORS) {
        anyHost()
        allowHeader(HttpHeaders.ContentType)
        allowMethod(HttpMethod.Get)
        allowMethod(HttpMethod.Post)
        allowMethod(HttpMethod.Options)
    }

    routing {

        // ── Serve frontend HTML ──────────────────────────────────────────────
        get("/") {
            val file = File("../automacao-massas-dns.html")
            if (file.exists()) {
                call.respondFile(file)
            } else {
                call.respondText(
                    "automacao-massas-dns.html not found. Start the server from the project root.",
                    status = HttpStatusCode.NotFound
                )
            }
        }

        // ── Parse ────────────────────────────────────────────────────────────
        post("/api/parse") {
            val req      = call.receive<ParseRequest>()
            val massas   = ParserService.parseMassa(req.massas)
            val dns      = ParserService.parseDns(req.dns)
            val combined = ParserService.buildCombined(massas, dns)
            call.respond(ParseResponse(massas, dns, combined))
        }

        // ── Export CSV ───────────────────────────────────────────────────────
        post("/api/export/csv") {
            val req      = call.receive<ExportRequest>()
            val massas   = ParserService.parseMassa(req.massas)
            val dns      = ParserService.parseDns(req.dns)
            val combined = ParserService.buildCombined(massas, dns)

            val (filename, headers, rows) = when (req.type) {
                "massas"    -> Triple("massas.csv",    massas.headers,   massas.rows)
                "dns"       -> Triple("dns.csv",       listOf("Idx", "Ambiente", "URL"),
                                      dns.map { listOf(it.idx.toString(), it.env, it.url) })
                "combinado" -> Triple("combinado.csv", combined.headers, combined.rows)
                else        -> Triple("export.csv",    combined.headers, combined.rows)
            }

            val csv = "\uFEFF${toCsv(headers, rows)}" // BOM for Excel UTF-8
            call.response.header(
                HttpHeaders.ContentDisposition,
                ContentDisposition.Attachment.withParameter(
                    ContentDisposition.Parameters.FileName, filename
                ).toString()
            )
            call.respondText(csv, ContentType.parse("text/csv; charset=utf-8"))
        }

        // ── Export JSON ──────────────────────────────────────────────────────
        post("/api/export/json") {
            val req      = call.receive<ExportRequest>()
            val massas   = ParserService.parseMassa(req.massas)
            val dns      = ParserService.parseDns(req.dns)
            val combined = ParserService.buildCombined(massas, dns)

            val payload  = ParseResponse(massas, dns, combined)
            val jsonText = Json { prettyPrint = true }.encodeToString(ParseResponse.serializer(), payload)

            call.response.header(
                HttpHeaders.ContentDisposition,
                ContentDisposition.Attachment.withParameter(
                    ContentDisposition.Parameters.FileName, "massas-dns.json"
                ).toString()
            )
            call.respondText(jsonText, ContentType.Application.Json)
        }

        // ── Health check ─────────────────────────────────────────────────────
        get("/health") {
            call.respond(
                mapOf(
                    "status"    to "ok",
                    "language"  to "Kotlin",
                    "framework" to "Ktor"
                )
            )
        }
    }
}
