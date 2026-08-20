package com.itau.massasdns.controller;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.itau.massasdns.model.CombinedData;
import com.itau.massasdns.model.DNSEntry;
import com.itau.massasdns.model.MassaData;
import com.itau.massasdns.model.ParseRequest;
import com.itau.massasdns.model.ParseResponse;
import com.itau.massasdns.service.ParserService;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;

@CrossOrigin(origins = "*")
@RestController
public class MassasDnsController {

    private final ParserService parserService;
    private final ObjectMapper objectMapper;

    public MassasDnsController(ParserService parserService, ObjectMapper objectMapper) {
        this.parserService = parserService;
        this.objectMapper = objectMapper;
    }

    // -------------------------------------------------------------------------
    // Frontend
    // -------------------------------------------------------------------------

    /**
     * Serves the static {@code index.html} from the classpath
     * ({@code src/main/resources/static/index.html}).
     * Falls back to a minimal inline page if the file is not found.
     */
    @GetMapping(value = "/", produces = MediaType.TEXT_HTML_VALUE)
    public ResponseEntity<String> index() {
        try (InputStream is = getClass().getResourceAsStream("/static/index.html")) {
            if (is != null) {
                String html = new String(is.readAllBytes(), StandardCharsets.UTF_8);
                return ResponseEntity.ok().contentType(MediaType.TEXT_HTML).body(html);
            }
        } catch (Exception ignored) {
            // fall through to inline fallback
        }
        String fallback = """
                <!DOCTYPE html>
                <html lang="pt-BR">
                <head><meta charset="UTF-8"><title>Massas &amp; DNS</title></head>
                <body>
                  <h1>Massas &amp; DNS — Java / Spring Boot</h1>
                  <p>Place your <code>index.html</code> in
                     <code>src/main/resources/static/</code> to serve the full UI.</p>
                  <ul>
                    <li><a href="/health">/health</a></li>
                    <li>POST /api/parse</li>
                    <li>POST /api/export/csv</li>
                    <li>POST /api/export/json</li>
                  </ul>
                </body>
                </html>
                """;
        return ResponseEntity.ok().contentType(MediaType.TEXT_HTML).body(fallback);
    }

    // -------------------------------------------------------------------------
    // API
    // -------------------------------------------------------------------------

    /**
     * Parses massas and DNS raw text and returns the structured result.
     *
     * <pre>POST /api/parse
     * Content-Type: application/json
     * { "massas": "...", "dns": "..." }
     * </pre>
     */
    @PostMapping(value = "/api/parse",
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    public ParseResponse parse(@RequestBody ParseRequest request) {
        MassaData massaData    = parserService.parseMassa(request.massas());
        List<DNSEntry> dns     = parserService.parseDNS(request.dns());
        CombinedData combined  = parserService.buildCombined(massaData, dns);
        return new ParseResponse(massaData, dns, combined);
    }

    /**
     * Returns a CSV file built from the combined table.
     *
     * <pre>POST /api/export/csv
     * Content-Type: application/json
     * { "massas": "...", "dns": "..." }
     * </pre>
     */
    @PostMapping(value = "/api/export/csv",
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = "text/csv")
    public ResponseEntity<byte[]> exportCsv(@RequestBody ParseRequest request) {
        MassaData massaData   = parserService.parseMassa(request.massas());
        List<DNSEntry> dns    = parserService.parseDNS(request.dns());
        CombinedData combined = parserService.buildCombined(massaData, dns);

        String csv = buildCsvString(combined);
        byte[] bytes = csv.getBytes(StandardCharsets.UTF_8);

        HttpHeaders headers = new HttpHeaders();
        headers.setContentDispositionFormData("attachment", "massas_dns_export.csv");
        headers.setContentType(MediaType.parseMediaType("text/csv; charset=UTF-8"));

        return ResponseEntity.ok().headers(headers).body(bytes);
    }

    /**
     * Returns a JSON file built from the full parse response.
     *
     * <pre>POST /api/export/json
     * Content-Type: application/json
     * { "massas": "...", "dns": "..." }
     * </pre>
     */
    @PostMapping(value = "/api/export/json",
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<byte[]> exportJson(@RequestBody ParseRequest request) {
        MassaData massaData   = parserService.parseMassa(request.massas());
        List<DNSEntry> dns    = parserService.parseDNS(request.dns());
        CombinedData combined = parserService.buildCombined(massaData, dns);
        ParseResponse response = new ParseResponse(massaData, dns, combined);

        byte[] bytes;
        try {
            bytes = objectMapper.writerWithDefaultPrettyPrinter()
                                .writeValueAsBytes(response);
        } catch (JsonProcessingException e) {
            return ResponseEntity.internalServerError().build();
        }

        HttpHeaders headers = new HttpHeaders();
        headers.setContentDispositionFormData("attachment", "massas_dns_export.json");
        headers.setContentType(MediaType.APPLICATION_JSON);

        return ResponseEntity.ok().headers(headers).body(bytes);
    }

    /**
     * Health-check endpoint.
     *
     * <pre>GET /health → { "status": "ok", "language": "Java", "framework": "Spring Boot" }</pre>
     */
    @GetMapping(value = "/health", produces = MediaType.APPLICATION_JSON_VALUE)
    public Map<String, String> health() {
        return Map.of(
                "status",    "ok",
                "language",  "Java",
                "framework", "Spring Boot"
        );
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /**
     * Converts {@link CombinedData} to a RFC-4180-style CSV string.
     * Cells containing commas, double-quotes, or newlines are quoted.
     */
    private String buildCsvString(CombinedData data) {
        StringBuilder sb = new StringBuilder();

        // Header row
        sb.append(rowToCsv(data.headers())).append("\r\n");

        // Data rows
        for (List<String> row : data.rows()) {
            sb.append(rowToCsv(row)).append("\r\n");
        }

        return sb.toString();
    }

    private String rowToCsv(List<String> cells) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < cells.size(); i++) {
            if (i > 0) sb.append(',');
            sb.append(escapeCsvCell(cells.get(i)));
        }
        return sb.toString();
    }

    private String escapeCsvCell(String value) {
        if (value == null) return "";
        // Quote if the value contains comma, double-quote, newline, or carriage-return
        if (value.contains(",") || value.contains("\"")
                || value.contains("\n") || value.contains("\r")) {
            return "\"" + value.replace("\"", "\"\"") + "\"";
        }
        return value;
    }
}
