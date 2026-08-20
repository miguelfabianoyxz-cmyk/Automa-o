package com.itau.massasdns.service;

import com.itau.massasdns.model.CombinedData;
import com.itau.massasdns.model.DNSEntry;
import com.itau.massasdns.model.MassaData;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Set;

@Service
public class ParserService {

    /** Known column header keywords that identify a massas table row. */
    private static final Set<String> KNOWN_HEADERS = Set.of(
            "cpf", "nome", "conta", "agência", "agencia", "agency"
    );

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /**
     * Parses raw massas text (tab / semicolon / comma separated) into a
     * {@link MassaData} record containing headers and data rows.
     */
    public MassaData parseMassa(String raw) {
        if (raw == null || raw.isBlank()) {
            return new MassaData(List.of(), List.of());
        }

        List<String> lines = splitLines(raw.strip());
        if (lines.isEmpty()) {
            return new MassaData(List.of(), List.of());
        }

        String sep = detectSep(lines.get(0));

        // Try to find a header line that contains at least one known keyword
        int headerIdx = 0;
        for (int i = 0; i < lines.size(); i++) {
            String lower = lines.get(i).toLowerCase();
            boolean hasKnown = KNOWN_HEADERS.stream().anyMatch(lower::contains);
            if (hasKnown) {
                headerIdx = i;
                break;
            }
        }

        List<String> headers = splitRow(lines.get(headerIdx), sep);

        List<List<String>> rows = new ArrayList<>();
        for (int i = headerIdx + 1; i < lines.size(); i++) {
            String line = lines.get(i);
            if (line.isBlank()) continue;
            List<String> cells = splitRow(line, sep);
            // Pad or truncate to match header count
            rows.add(normalizeRow(cells, headers.size()));
        }

        return new MassaData(headers, rows);
    }

    /**
     * Parses raw DNS text.  Each non-blank line is treated as a URL;
     * the environment is inferred from the URL.
     */
    public List<DNSEntry> parseDNS(String raw) {
        if (raw == null || raw.isBlank()) {
            return List.of();
        }

        List<DNSEntry> entries = new ArrayList<>();
        int idx = 1;
        for (String line : splitLines(raw.strip())) {
            String url = line.strip();
            if (url.isBlank()) continue;
            entries.add(new DNSEntry(idx++, inferEnv(url), url));
        }
        return entries;
    }

    /**
     * Builds a combined table by appending DNS columns (idx, env, url) to
     * each row from massas, cycling through DNS entries as needed.
     */
    public CombinedData buildCombined(MassaData massas, List<DNSEntry> dnsList) {
        if (massas == null || massas.headers().isEmpty()) {
            return new CombinedData(List.of(), List.of());
        }

        List<String> headers = new ArrayList<>(massas.headers());
        headers.add("dns_idx");
        headers.add("dns_env");
        headers.add("dns_url");

        List<List<String>> rows = new ArrayList<>();
        List<List<String>> massaRows = massas.rows();

        for (int i = 0; i < massaRows.size(); i++) {
            List<String> row = new ArrayList<>(massaRows.get(i));
            if (!dnsList.isEmpty()) {
                DNSEntry entry = dnsList.get(i % dnsList.size());
                row.add(String.valueOf(entry.idx()));
                row.add(entry.env());
                row.add(entry.url());
            } else {
                row.add("");
                row.add("");
                row.add("");
            }
            rows.add(row);
        }

        return new CombinedData(headers, rows);
    }

    /**
     * Infers the environment label from a URL string.
     * Rules (case-insensitive, in priority order):
     * <ol>
     *   <li>contains "prod"  → PROD</li>
     *   <li>contains "hml" or "homolog" → HML</li>
     *   <li>contains "sit" or "staging" → SIT</li>
     *   <li>contains "dev"  → DEV</li>
     *   <li>contains "local" or "127.0.0.1" or "localhost" → LOCAL</li>
     *   <li>otherwise       → UNKNOWN</li>
     * </ol>
     */
    public String inferEnv(String url) {
        if (url == null) return "UNKNOWN";
        String lower = url.toLowerCase();
        if (lower.contains("prod"))                                    return "PROD";
        if (lower.contains("hml") || lower.contains("homolog"))       return "HML";
        if (lower.contains("sit") || lower.contains("staging"))       return "SIT";
        if (lower.contains("dev"))                                     return "DEV";
        if (lower.contains("local") || lower.contains("127.0.0.1")
                || lower.contains("localhost"))                        return "LOCAL";
        return "UNKNOWN";
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /**
     * Detects the field separator used in a line.
     * Priority: tab {@literal >} semicolon {@literal >} comma.
     */
    private String detectSep(String line) {
        if (line.contains("\t"))  return "\t";
        if (line.contains(";"))   return ";";
        return ",";
    }

    /** Splits raw text into non-null lines, handling Windows and Unix endings. */
    private List<String> splitLines(String raw) {
        return Arrays.asList(raw.split("\\r?\\n", -1));
    }

    /** Splits a single row by the given separator and trims each cell. */
    private List<String> splitRow(String line, String sep) {
        // Escape the separator for use in a regex
        String[] parts = line.split(java.util.regex.Pattern.quote(sep), -1);
        List<String> cells = new ArrayList<>(parts.length);
        for (String p : parts) {
            cells.add(p.strip());
        }
        return cells;
    }

    /**
     * Ensures a row has exactly {@code size} cells, padding with empty strings
     * or dropping trailing extras.
     */
    private List<String> normalizeRow(List<String> cells, int size) {
        List<String> result = new ArrayList<>(cells);
        while (result.size() < size) result.add("");
        if (result.size() > size)    result = result.subList(0, size);
        return new ArrayList<>(result);
    }
}
