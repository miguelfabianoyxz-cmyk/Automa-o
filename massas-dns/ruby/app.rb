require 'sinatra'
require 'json'
require 'csv'

# ---------------------------------------------------------------------------
# Parser module
# ---------------------------------------------------------------------------
module MassasParser
  KNOWN_HEADERS = %w[cpf nome conta agência agencia agency email telefone].freeze

  # Detect the column separator used in a line
  def self.detect_sep(line)
    return "\t" if line.include?("\t")
    return ';'  if line.include?(';')
    ','
  end

  # Parse a raw massa (CSV-like text) into { headers: [], rows: [] }
  def self.parse_massa(raw)
    lines = raw.to_s.strip.split(/\r?\n/).reject(&:empty?)
    return { headers: [], rows: [] } if lines.empty?

    sep = detect_sep(lines.first)

    rows_raw = lines.map { |l| l.split(sep).map(&:strip) }

    # Determine whether the first row is a header row
    first_row_lower = rows_raw.first.map(&:downcase)
    if first_row_lower.any? { |cell| KNOWN_HEADERS.include?(cell) }
      headers  = rows_raw.shift
      data_rows = rows_raw
    else
      headers  = rows_raw.first.each_with_index.map { |_, i| "col#{i + 1}" }
      data_rows = rows_raw
    end

    rows = data_rows.map do |cells|
      row = {}
      headers.each_with_index { |h, i| row[h] = cells[i] || '' }
      row
    end

    { headers: headers, rows: rows }
  end

  # Parse raw DNS text → array of { idx, env, url }
  def self.parse_dns(raw)
    lines = raw.to_s.strip.split(/\r?\n/).reject(&:empty?)
    lines.each_with_index.map do |line, idx|
      url = line.strip
      { idx: idx + 1, env: infer_env(url), url: url }
    end
  end

  # Infer environment from URL
  def self.infer_env(url)
    lower = url.downcase
    return 'HML' if lower.match?(/hml|homolog/)
    return 'PRD' if lower.match?(/prd|prod/)
    return 'DEV' if lower.include?('dev')
    return 'SIT' if lower.include?('sit')
    return 'UAT' if lower.include?('uat')
    return 'QAS' if lower.include?('qas')
    'UNKNOWN'
  end

  # Cartesian product: each massa row × each DNS entry
  def self.build_combined(massas, dns_list)
    return { headers: [], rows: [] } if massas[:rows].empty? || dns_list.empty?

    extra_headers = %w[dns_idx dns_env dns_url]
    combined_headers = massas[:headers] + extra_headers

    rows = massas[:rows].flat_map do |massa_row|
      dns_list.map do |dns|
        row = {}
        massas[:headers].each { |h| row[h] = massa_row[h] }
        row['dns_idx'] = dns[:idx]
        row['dns_env'] = dns[:env]
        row['dns_url'] = dns[:url]
        row
      end
    end

    { headers: combined_headers, rows: rows }
  end
end

# ---------------------------------------------------------------------------
# Sinatra configuration
# ---------------------------------------------------------------------------
set :port, 4567
set :bind, '0.0.0.0'

# CORS — allow all origins
before do
  response.headers['Access-Control-Allow-Origin']  = '*'
  response.headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
  response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Accept'
end

options '*' do
  200
end

# ---------------------------------------------------------------------------
# Helper — read and parse JSON body
# ---------------------------------------------------------------------------
def json_body
  request.body.rewind
  JSON.parse(request.body.read)
rescue JSON::ParserError
  halt 400, { 'Content-Type' => 'application/json' }, JSON.generate({ error: 'Invalid JSON body' })
end

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

# Serve the HTML front-end
get '/' do
  send_file File.expand_path('../automacao-massas-dns.html', __dir__)
end

# Health check
get '/health' do
  content_type :json
  JSON.generate({ status: 'ok', language: 'Ruby', framework: 'Sinatra' })
end

# Parse raw massa + DNS text and return structured JSON
post '/api/parse' do
  content_type :json

  body = json_body
  massa_raw = body['massa'] || body['massas'] || ''
  dns_raw   = body['dns']   || ''

  massas   = MassasParser.parse_massa(massa_raw)
  dns_list = MassasParser.parse_dns(dns_raw)
  combined = MassasParser.build_combined(massas, dns_list)

  JSON.generate({
    massas:   massas,
    dns:      dns_list,
    combined: combined
  })
end

# Export CSV
post '/api/export/csv' do
  body     = json_body
  mode     = body['mode'] || 'combined'
  filename = body['filename'] || "export-#{mode}.csv"

  massa_raw = body['massa'] || body['massas'] || ''
  dns_raw   = body['dns']   || ''

  massas   = MassasParser.parse_massa(massa_raw)
  dns_list = MassasParser.parse_dns(dns_raw)
  combined = MassasParser.build_combined(massas, dns_list)

  dataset =
    case mode
    when 'massas' then massas
    when 'dns'
      # Normalise dns array into the same { headers, rows } shape
      { headers: %w[dns_idx dns_env dns_url],
        rows: dns_list.map { |d| { 'dns_idx' => d[:idx], 'dns_env' => d[:env], 'dns_url' => d[:url] } } }
    else
      combined
    end

  csv_string = CSV.generate(headers: true) do |csv|
    csv << dataset[:headers]
    dataset[:rows].each { |row| csv << dataset[:headers].map { |h| row[h] } }
  end

  content_type 'text/csv'
  headers['Content-Disposition'] = "attachment; filename=\"#{filename}\""
  csv_string
end

# Export JSON
post '/api/export/json' do
  body     = json_body
  mode     = body['mode'] || 'combined'
  filename = body['filename'] || "export-#{mode}.json"

  massa_raw = body['massa'] || body['massas'] || ''
  dns_raw   = body['dns']   || ''

  massas   = MassasParser.parse_massa(massa_raw)
  dns_list = MassasParser.parse_dns(dns_raw)
  combined = MassasParser.build_combined(massas, dns_list)

  payload =
    case mode
    when 'massas' then massas
    when 'dns'    then dns_list
    else               combined
    end

  content_type 'application/json'
  headers['Content-Disposition'] = "attachment; filename=\"#{filename}\""
  JSON.generate(payload)
end
