using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

// ---------------------------------------------------------------------------
// Records
// ---------------------------------------------------------------------------

record ParseRequest(string Massas, string Dns);
record MassaData(List<string> Headers, List<List<string>> Rows);
record DnsEntry(int Idx, string Env, string Url);
record CombinedData(List<string> Headers, List<List<string>> Rows);
record ParseResponse(MassaData Massas, List<DnsEntry> Dns, CombinedData Combined);
record ExportRequest(
    string Type,
    MassaData? MassasData,
    List<DnsEntry>? DnsData,
    CombinedData? CombinedData);

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

static class ParserService
{
    private static readonly string[] DefaultHeaders = ["CPF", "Nome", "Conta", "Agência"];

    private static readonly HashSet<string> KnownHeaders =
        new(StringComparer.OrdinalIgnoreCase)
        {
            "cpf", "nome", "conta", "agência", "agencia", "agency", "email", "telefone"
        };

    private static readonly (Regex Pattern, string Label)[] EnvPatterns =
    [
        (new Regex(@"hml|homolog", RegexOptions.IgnoreCase), "HML"),
        (new Regex(@"prd|prod",    RegexOptions.IgnoreCase), "PROD"),
        (new Regex(@"\bdev\b",     RegexOptions.IgnoreCase), "DEV"),
        (new Regex(@"\bsit\b",     RegexOptions.IgnoreCase), "SIT"),
        (new Regex(@"\buat\b",     RegexOptions.IgnoreCase), "UAT"),
        (new Regex(@"\bqas\b",     RegexOptions.IgnoreCase), "QAS"),
    ];

    // Returns the dominant separator in the first non-empty line.
    public static char DetectSep(string line)
    {
        foreach (char sep in new[] { '\t', ';', ',' })
            if (line.Contains(sep))
                return sep;
        return '\t';
    }

    // Infers the environment label from a URL string.
    public static string InferEnv(string url)
    {
        foreach (var (pattern, label) in EnvPatterns)
            if (pattern.IsMatch(url))
                return label;
        return "UNKNOWN";
    }

    // Parses raw massa text into headers + rows.
    public static MassaData ParseMassa(string raw)
    {
        var lines = raw.Split('\n')
                       .Select(l => l.TrimEnd('\r'))
                       .Where(l => l.Trim().Length > 0)
                       .ToList();

        if (lines.Count == 0)
            return new MassaData([.. DefaultHeaders], []);

        char sep = DetectSep(lines[0]);

        var firstCols = lines[0].Split(sep).Select(c => c.Trim()).ToList();
        bool isHeader = firstCols.Any(c => KnownHeaders.Contains(c));

        List<string> headers;
        List<string> dataLines;

        if (isHeader)
        {
            headers = firstCols;
            dataLines = lines.Skip(1).ToList();
        }
        else
        {
            int colCount = firstCols.Count;
            if (colCount <= DefaultHeaders.Length)
                headers = [.. DefaultHeaders[..colCount]];
            else
            {
                headers = [.. DefaultHeaders];
                for (int i = DefaultHeaders.Length + 1; i <= colCount; i++)
                    headers.Add($"Col{i}");
            }
            dataLines = lines;
        }

        var rows = new List<List<string>>();
        foreach (var line in dataLines)
        {
            if (line.Trim().Length == 0) continue;
            var cols = line.Split(sep).Select(c => c.Trim()).ToList();
            while (cols.Count < headers.Count) cols.Add("");
            rows.Add(cols[..headers.Count]);
        }

        return new MassaData(headers, rows);
    }

    // Parses raw DNS text into a list of DnsEntry records.
    public static List<DnsEntry> ParseDns(string raw)
    {
        var entries = new List<DnsEntry>();
        int idx = 1;

        foreach (var rawLine in raw.Split('\n'))
        {
            var line = rawLine.Trim('\r').Trim();
            if (line.Length == 0) continue;

            var tokens = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            string env, url;

            if (tokens.Length >= 2)
            {
                env = tokens[0].ToUpperInvariant();
                url = string.Join(" ", tokens[1..]);
            }
            else
            {
                url = tokens[0];
                env = InferEnv(url);
            }

            entries.Add(new DnsEntry(idx++, env, url));
        }

        return entries;
    }

    // Cartesian product of massa rows × DNS entries.
    public static CombinedData BuildCombined(MassaData massas, List<DnsEntry> dns)
    {
        var headers = massas.Headers.Concat(["Ambiente", "URL"]).ToList();
        var rows = new List<List<string>>();

        foreach (var row in massas.Rows)
            foreach (var entry in dns)
            {
                var combined = new List<string>(row) { entry.Env, entry.Url };
                rows.Add(combined);
            }

        return new CombinedData(headers, rows);
    }

    // Builds a UTF-8 BOM CSV string from headers + rows (RFC-4180).
    public static string ToCsv(List<string> headers, List<List<string>> rows)
    {
        var sb = new StringBuilder();
        sb.Append('\uFEFF'); // BOM

        sb.AppendLine(string.Join(",", headers.Select(CsvEscape)));

        foreach (var row in rows)
            sb.AppendLine(string.Join(",", row.Select(CsvEscape)));

        return sb.ToString();
    }

    private static string CsvEscape(string value)
    {
        if (value.Contains(',') || value.Contains('"') || value.Contains('\n') || value.Contains('\r'))
            return $"\"{value.Replace("\"", "\"\"")}\"";
        return value;
    }
}

// ---------------------------------------------------------------------------
// App bootstrap
// ---------------------------------------------------------------------------

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddCors(options =>
    options.AddDefaultPolicy(policy =>
        policy.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader()));

builder.Services.ConfigureHttpJsonOptions(opts =>
{
    opts.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    opts.SerializerOptions.WriteIndented = false;
});

var app = builder.Build();

app.UseCors();

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

// GET / — serve the HTML front-end
app.MapGet("/", async (HttpContext ctx) =>
{
    var htmlPath = Path.GetFullPath(
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..",
                     "automacao-massas-dns.html"));

    // Fallback: one directory up from the project file location
    if (!File.Exists(htmlPath))
        htmlPath = Path.GetFullPath(
            Path.Combine(Directory.GetCurrentDirectory(), "..",
                         "automacao-massas-dns.html"));

    if (!File.Exists(htmlPath))
    {
        ctx.Response.StatusCode = 404;
        await ctx.Response.WriteAsync("Frontend HTML not found.");
        return;
    }

    ctx.Response.ContentType = "text/html; charset=utf-8";
    await ctx.Response.SendFileAsync(htmlPath);
});

// GET /health
app.MapGet("/health", () => Results.Ok(new
{
    status    = "ok",
    language  = "C#",
    framework = ".NET 8 Minimal API",
    port      = 8090
}));

// POST /api/parse
app.MapPost("/api/parse", (ParseRequest req) =>
{
    var massas   = ParserService.ParseMassa(req.Massas);
    var dns      = ParserService.ParseDns(req.Dns);
    var combined = ParserService.BuildCombined(massas, dns);

    return Results.Ok(new ParseResponse(massas, dns, combined));
});

// POST /api/export/csv
app.MapPost("/api/export/csv", (ExportRequest req) =>
{
    string csv;
    string filename;

    switch (req.Type?.ToLowerInvariant())
    {
        case "massas" when req.MassasData is not null:
            csv      = ParserService.ToCsv(req.MassasData.Headers, req.MassasData.Rows);
            filename = "massas.csv";
            break;

        case "dns" when req.DnsData is not null:
            var dnsHeaders = new List<string> { "idx", "env", "url" };
            var dnsRows    = req.DnsData
                               .Select(e => new List<string>
                                   { e.Idx.ToString(), e.Env, e.Url })
                               .ToList();
            csv      = ParserService.ToCsv(dnsHeaders, dnsRows);
            filename = "dns.csv";
            break;

        default: // "combined" or anything else
            var data = req.CombinedData
                       ?? new CombinedData([], []);
            csv      = ParserService.ToCsv(data.Headers, data.Rows);
            filename = "combined.csv";
            break;
    }

    var bytes = Encoding.UTF8.GetBytes(csv);
    return Results.File(bytes, "text/csv",
                        fileDownloadName: filename);
});

// POST /api/export/json
app.MapPost("/api/export/json", (ParseRequest req) =>
{
    var massas   = ParserService.ParseMassa(req.Massas);
    var dns      = ParserService.ParseDns(req.Dns);
    var combined = ParserService.BuildCombined(massas, dns);

    var payload = new ParseResponse(massas, dns, combined);
    var json    = JsonSerializer.Serialize(payload,
                      new JsonSerializerOptions
                      {
                          PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                          WriteIndented        = true
                      });

    var bytes = Encoding.UTF8.GetBytes(json);
    return Results.File(bytes, "application/json",
                        fileDownloadName: "massas-dns.json");
});

// ---------------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------------

app.Run("http://localhost:8090");
