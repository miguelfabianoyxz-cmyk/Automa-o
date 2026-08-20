# ============================================================
#  Massas & DNS — R Plumber API  (port 8040)
# ============================================================

library(plumber)
library(jsonlite)

# ── Known header tokens ──────────────────────────────────────
KNOWN_HEADERS <- c(
  "cpf", "nome", "conta",
  "agência", "agencia", "agency",
  "email", "telefone"
)

# ============================================================
#  Helper functions
# ============================================================

#' Detect the column separator used in a delimited line.
#'
#' @param line A single character string (one CSV/TSV row).
#' @return One of "\t", ";", or ",".
detect_sep <- function(line) {
  if (grepl("\t", line, fixed = TRUE)) return("\t")
  if (grepl(";", line, fixed = TRUE)) return(";")
  return(",")
}

#' Parse raw massa text into headers + rows.
#'
#' @param raw A character string with newline-separated rows.
#' @return list(headers = character, rows = list of named lists)
parse_massa <- function(raw) {
  lines <- strsplit(raw, "\n", fixed = TRUE)[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  if (length(lines) == 0L) {
    return(list(headers = character(0), rows = list()))
  }

  sep    <- detect_sep(lines[[1]])
  fields <- strsplit(lines, sep, fixed = TRUE)

  # Detect header row: first row whose tokens overlap with KNOWN_HEADERS
  first_lower <- tolower(trimws(fields[[1]]))
  is_header   <- any(first_lower %in% KNOWN_HEADERS)

  if (is_header) {
    headers    <- trimws(fields[[1]])
    data_lines <- fields[-1]
  } else {
    n_cols  <- length(fields[[1]])
    headers <- paste0("col", seq_len(n_cols))
    data_lines <- fields
  }

  rows <- lapply(data_lines, function(tokens) {
    tokens <- trimws(tokens)
    # Pad or trim to header length
    length(tokens) <- length(headers)
    tokens[is.na(tokens)] <- ""
    row <- as.list(tokens)
    names(row) <- headers
    row
  })

  list(headers = headers, rows = rows)
}

#' Parse raw DNS text into a list of environment/URL entries.
#'
#' Each non-empty line is treated as one URL.
#' @param raw A character string with newline-separated URLs.
#' @return list of list(idx, env, url)
parse_dns <- function(raw) {
  lines <- strsplit(raw, "\n", fixed = TRUE)[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  entries <- vector("list", length(lines))
  for (i in seq_along(lines)) {
    entries[[i]] <- list(
      idx = i,
      env = infer_env(lines[[i]]),
      url = lines[[i]]
    )
  }
  entries
}

#' Infer the deployment environment from a URL string.
#'
#' @param url A character string.
#' @return One of "HML", "PROD", "DEV", "SIT", "UAT", "QAS", or "UNKNOWN".
infer_env <- function(url) {
  u <- tolower(url)
  if (grepl("hml|homolog", u))  return("HML")
  if (grepl("prd|prod",   u))   return("PROD")
  if (grepl("dev",        u))   return("DEV")
  if (grepl("sit",        u))   return("SIT")
  if (grepl("uat",        u))   return("UAT")
  if (grepl("qas",        u))   return("QAS")
  "UNKNOWN"
}

#' Build a combined (cartesian) dataset from massa rows and DNS entries.
#'
#' @param massas  Output of parse_massa() — list(headers, rows).
#' @param dns     Output of parse_dns()   — list of list(idx, env, url).
#' @return list(headers = character, rows = list of named lists)
build_combined <- function(massas, dns) {
  m_rows <- massas$rows
  m_hdrs <- massas$headers

  if (length(m_rows) == 0L || length(dns) == 0L) {
    combined_headers <- c(m_hdrs, "dns_env", "dns_url")
    return(list(headers = combined_headers, rows = list()))
  }

  # Cartesian product via nested loops (no extra dependencies)
  combined <- vector("list", length(m_rows) * length(dns))
  idx <- 1L
  for (row in m_rows) {
    for (entry in dns) {
      combined[[idx]] <- c(row, list(dns_env = entry$env, dns_url = entry$url))
      idx <- idx + 1L
    }
  }

  combined_headers <- c(m_hdrs, "dns_env", "dns_url")
  list(headers = combined_headers, rows = combined)
}

#' Serialise headers + rows to a CSV string.
#'
#' @param headers character vector of column names.
#' @param rows    list of named lists (each list is one row).
#' @return A single character string ready to write as .csv.
to_csv <- function(headers, rows) {
  header_line <- paste(headers, collapse = ",")
  if (length(rows) == 0L) return(header_line)

  row_lines <- vapply(rows, function(r) {
    vals <- vapply(headers, function(h) {
      v <- if (!is.null(r[[h]])) as.character(r[[h]]) else ""
      # Escape double-quotes and wrap fields that contain commas/quotes
      if (grepl('[",\n\r]', v)) {
        v <- paste0('"', gsub('"', '""', v, fixed = TRUE), '"')
      }
      v
    }, character(1L))
    paste(vals, collapse = ",")
  }, character(1L))

  paste(c(header_line, row_lines), collapse = "\n")
}

# ============================================================
#  CORS filter
# ============================================================

#* @filter cors
function(req, res) {
  res$setHeader("Access-Control-Allow-Origin",  "*")
  res$setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
  res$setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")

  if (req$REQUEST_METHOD == "OPTIONS") {
    res$status <- 204L
    return(list())
  }

  plumber::forward()
}

# ============================================================
#  Routes
# ============================================================

#* Serve the front-end HTML
#* @get /
#* @serializer contentType list(type="text/html; charset=utf-8")
function(res) {
  html_path <- normalizePath(
    file.path(dirname(sys.frame(1)$ofile), "..", "automacao-massas-dns.html"),
    mustWork = FALSE
  )

  # Fallback: relative to working directory
  if (!file.exists(html_path)) {
    html_path <- "../automacao-massas-dns.html"
  }

  if (!file.exists(html_path)) {
    res$status <- 404L
    return("HTML file not found.")
  }

  paste(readLines(html_path, warn = FALSE), collapse = "\n")
}

#* Parse massa and DNS text into structured JSON
#* @post /api/parse
#* @serializer json
function(req) {
  body <- jsonlite::fromJSON(req$postBody, simplifyVector = FALSE)

  massas_raw <- body$massas %||% ""
  dns_raw    <- body$dns    %||% ""

  massas_parsed <- parse_massa(massas_raw)
  dns_parsed    <- parse_dns(dns_raw)
  combined      <- build_combined(massas_parsed, dns_parsed)

  list(
    massas   = massas_parsed,
    dns      = dns_parsed,
    combined = combined
  )
}

#* Export combined data as a CSV file attachment
#* @post /api/export/csv
#* @serializer contentType list(type="text/csv; charset=utf-8")
function(req, res) {
  body <- jsonlite::fromJSON(req$postBody, simplifyVector = FALSE)

  massas_raw <- body$massas %||% ""
  dns_raw    <- body$dns    %||% ""

  massas_parsed <- parse_massa(massas_raw)
  dns_parsed    <- parse_dns(dns_raw)
  combined      <- build_combined(massas_parsed, dns_parsed)

  csv_text <- to_csv(combined$headers, combined$rows)

  res$setHeader(
    "Content-Disposition",
    'attachment; filename="massas-dns-export.csv"'
  )
  csv_text
}

#* Health-check endpoint
#* @get /health
#* @serializer json
function() {
  list(status = "ok", language = "R", framework = "Plumber")
}

# ── Null-coalescing operator (base R >= 4.4 has it; provide for older) ──
`%||%` <- function(x, y) if (!is.null(x) && nzchar(x)) x else y
