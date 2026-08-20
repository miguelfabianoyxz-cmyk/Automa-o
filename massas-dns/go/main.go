package main

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"path/filepath"
	"runtime"
	"strings"
)

// ---------------------------------------------------------------------------
// Domain structs
// ---------------------------------------------------------------------------

// MassaData holds the parsed tabular massa data.
type MassaData struct {
	Headers []string            `json:"headers"`
	Rows    []map[string]string `json:"rows"`
}

// DNSEntry represents a single parsed DNS entry.
type DNSEntry struct {
	Idx int    `json:"idx"`
	Env string `json:"env"`
	URL string `json:"url"`
}

// ParseRequest is the body accepted by POST /api/parse.
type ParseRequest struct {
	Massas string `json:"massas"`
	DNS    string `json:"dns"`
}

// ParseResponse is returned by POST /api/parse.
type ParseResponse struct {
	Massas   MassaData            `json:"massas"`
	DNS      []DNSEntry           `json:"dns"`
	Combined []map[string]string  `json:"combined"`
}

// ExportRequest is the body accepted by the export endpoints.
type ExportRequest struct {
	Type     string               `json:"type"` // "massas" | "dns" | "combined"
	Massas   MassaData            `json:"massas"`
	DNS      []DNSEntry           `json:"dns"`
	Combined []map[string]string  `json:"combined"`
}

// ---------------------------------------------------------------------------
// Parser helpers
// ---------------------------------------------------------------------------

var knownHeaders = []string{
	"cpf", "nome", "conta", "agência", "agencia", "agency", "email", "telefone",
}

// detectSep returns the most likely delimiter in a line: tab > semicolon > comma.
func detectSep(line string) rune {
	if strings.ContainsRune(line, '\t') {
		return '\t'
	}
	if strings.ContainsRune(line, ';') {
		return ';'
	}
	return ','
}

// isHeaderRow returns true when the lower-cased fields contain at least one known header keyword.
func isHeaderRow(fields []string) bool {
	for _, f := range fields {
		lower := strings.ToLower(strings.TrimSpace(f))
		for _, kh := range knownHeaders {
			if lower == kh {
				return true
			}
		}
	}
	return false
}

// parseMassa parses raw tabular text and returns MassaData.
func parseMassa(raw string) MassaData {
	lines := splitLines(raw)
	if len(lines) == 0 {
		return MassaData{Headers: []string{}, Rows: []map[string]string{}}
	}

	sep := detectSep(lines[0])

	// Find the header row (first row that contains a known header keyword).
	headerIdx := -1
	for i, line := range lines {
		fields := strings.Split(line, string(sep))
		if isHeaderRow(fields) {
			headerIdx = i
			break
		}
	}

	// If no header row was detected, treat the first non-empty line as data with
	// auto-generated column names.
	var headers []string
	dataStart := 0
	if headerIdx >= 0 {
		rawHeaders := strings.Split(lines[headerIdx], string(sep))
		for _, h := range rawHeaders {
			headers = append(headers, strings.TrimSpace(h))
		}
		dataStart = headerIdx + 1
	} else {
		firstFields := strings.Split(lines[0], string(sep))
		for i := range firstFields {
			headers = append(headers, fmt.Sprintf("col%d", i+1))
		}
	}

	var rows []map[string]string
	for _, line := range lines[dataStart:] {
		if strings.TrimSpace(line) == "" {
			continue
		}
		fields := strings.Split(line, string(sep))
		row := make(map[string]string, len(headers))
		for i, h := range headers {
			if i < len(fields) {
				row[h] = strings.TrimSpace(fields[i])
			} else {
				row[h] = ""
			}
		}
		rows = append(rows, row)
	}

	if rows == nil {
		rows = []map[string]string{}
	}

	return MassaData{Headers: headers, Rows: rows}
}

// inferEnv derives an environment label from a URL string.
func inferEnv(url string) string {
	lower := strings.ToLower(url)
	switch {
	case strings.Contains(lower, "hml") || strings.Contains(lower, "homolog"):
		return "HML"
	case strings.Contains(lower, "prd") || strings.Contains(lower, "prod"):
		return "PROD"
	case strings.Contains(lower, "dev"):
		return "DEV"
	case strings.Contains(lower, "sit"):
		return "SIT"
	case strings.Contains(lower, "uat"):
		return "UAT"
	case strings.Contains(lower, "qas"):
		return "QAS"
	default:
		return "UNKNOWN"
	}
}

// parseDNS parses raw DNS/URL text into a slice of DNSEntry.
// Each non-empty line is split by whitespace:
//   - 2+ tokens → first token is env (ToUpper), second is URL
//   - 1 token   → URL only, env is inferred
func parseDNS(raw string) []DNSEntry {
	lines := splitLines(raw)
	var entries []DNSEntry
	idx := 0
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.Fields(line)
		var env, url string
		if len(parts) >= 2 {
			env = strings.ToUpper(parts[0])
			url = parts[1]
		} else {
			url = parts[0]
			env = inferEnv(url)
		}
		entries = append(entries, DNSEntry{Idx: idx, Env: env, URL: url})
		idx++
	}
	if entries == nil {
		entries = []DNSEntry{}
	}
	return entries
}

// buildCombined returns the cartesian product of massa rows × DNS entries.
// Each combined row merges the massa row fields with "env" and "url" from the DNS entry.
func buildCombined(massa MassaData, dns []DNSEntry) []map[string]string {
	var combined []map[string]string
	for _, row := range massa.Rows {
		for _, entry := range dns {
			merged := make(map[string]string, len(row)+3)
			for k, v := range row {
				merged[k] = v
			}
			merged["env"] = entry.Env
			merged["url"] = entry.URL
			merged["dns_idx"] = fmt.Sprintf("%d", entry.Idx)
			combined = append(combined, merged)
		}
	}
	if combined == nil {
		combined = []map[string]string{}
	}
	return combined
}

// splitLines splits text on \n, trimming \r.
func splitLines(s string) []string {
	raw := strings.Split(s, "\n")
	var out []string
	for _, l := range raw {
		l = strings.TrimRight(l, "\r")
		if strings.TrimSpace(l) != "" {
			out = append(out, l)
		}
	}
	return out
}

// ---------------------------------------------------------------------------
// Middleware
// ---------------------------------------------------------------------------

// withCORS adds permissive CORS headers and handles pre-flight OPTIONS requests.
func withCORS(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next(w, r)
	}
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

// handleIndex serves the front-end HTML file.
func handleIndex(w http.ResponseWriter, r *http.Request) {
	_, filename, _, _ := runtime.Caller(0)
	dir := filepath.Dir(filename)
	htmlPath := filepath.Join(dir, "..", "automacao-massas-dns.html")
	http.ServeFile(w, r, htmlPath)
}

// handleHealth returns a simple liveness JSON response.
func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status":    "ok",
		"language":  "Go",
		"framework": "net/http",
	})
}

// handleParse parses massa + DNS text and returns the structured result.
func handleParse(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req ParseRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON: "+err.Error(), http.StatusBadRequest)
		return
	}

	massa := parseMassa(req.Massas)
	dns := parseDNS(req.DNS)
	combined := buildCombined(massa, dns)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(ParseResponse{
		Massas:   massa,
		DNS:      dns,
		Combined: combined,
	})
}

// handleExportCSV builds a CSV file from the requested dataset and streams it.
func handleExportCSV(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req ExportRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON: "+err.Error(), http.StatusBadRequest)
		return
	}

	var headers []string
	var rows []map[string]string

	switch req.Type {
	case "dns":
		headers = []string{"idx", "env", "url"}
		for _, e := range req.DNS {
			rows = append(rows, map[string]string{
				"idx": fmt.Sprintf("%d", e.Idx),
				"env": e.Env,
				"url": e.URL,
			})
		}
	case "combined":
		headers = req.Massas.Headers
		headers = append(headers, "env", "url", "dns_idx")
		rows = req.Combined
	default: // "massas"
		headers = req.Massas.Headers
		rows = req.Massas.Rows
	}

	filename := fmt.Sprintf("massas-dns-%s.csv", req.Type)
	w.Header().Set("Content-Type", "text/csv; charset=utf-8")
	w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, filename))

	cw := csv.NewWriter(w)
	_ = cw.Write(headers)
	for _, row := range rows {
		record := make([]string, len(headers))
		for i, h := range headers {
			record[i] = row[h]
		}
		_ = cw.Write(record)
	}
	cw.Flush()
}

// handleExportJSON returns the full parsed payload as a downloadable JSON file.
func handleExportJSON(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req ExportRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON: "+err.Error(), http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="massas-dns-export.json"`)

	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	enc.Encode(map[string]interface{}{
		"massas":   req.Massas,
		"dns":      req.DNS,
		"combined": req.Combined,
	})
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("/", withCORS(handleIndex))
	mux.HandleFunc("/health", withCORS(handleHealth))
	mux.HandleFunc("/api/parse", withCORS(handleParse))
	mux.HandleFunc("/api/export/csv", withCORS(handleExportCSV))
	mux.HandleFunc("/api/export/json", withCORS(handleExportJSON))

	addr := ":8080"
	log.Printf("Massas & DNS server (Go / net/http) listening on http://localhost%s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
