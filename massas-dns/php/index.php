<?php

declare(strict_types=1);

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$requestUri = $_SERVER['REQUEST_URI'] ?? '/';
$path = parse_url($requestUri, PHP_URL_PATH) ?: '/';

switch ([$method, $path]) {
    case ['GET', '/']:
        $htmlPath = __DIR__ . '/../automacao-massas-dns.html';

        if (!is_file($htmlPath)) {
            http_response_code(404);
            header('Content-Type: text/plain; charset=utf-8');
            echo 'File not found';
            exit;
        }

        header('Content-Type: text/html; charset=utf-8');
        readfile($htmlPath);
        exit;

    case ['POST', '/api/parse']:
        $payload = getJsonBody();
        $massas = parseMassa((string) ($payload['massas'] ?? ''));
        $dns = parseDNS((string) ($payload['dns'] ?? ''));
        $combined = buildCombined($massas, $dns);

        jsonResponse([
            'massas' => $massas,
            'dns' => $dns,
            'combined' => $combined,
        ]);
        break;

    case ['POST', '/api/export/csv']:
        $payload = getJsonBody();
        $headers = is_array($payload['headers'] ?? null) ? $payload['headers'] : [];
        $rows = is_array($payload['rows'] ?? null) ? $payload['rows'] : [];
        $csv = toCSV($headers, $rows);

        header('Content-Type: text/csv; charset=utf-8');
        header('Content-Disposition: attachment; filename="massas-dns.csv"');
        echo $csv;
        exit;

    case ['POST', '/api/export/json']:
        $payload = getJsonBody();

        header('Content-Type: application/json; charset=utf-8');
        header('Content-Disposition: attachment; filename="massas-dns.json"');
        echo json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;

    case ['GET', '/health']:
        jsonResponse([
            'status' => 'ok',
            'language' => 'PHP',
            'framework' => 'Built-in Server',
        ]);
        break;

    default:
        jsonResponse(['error' => 'Not found'], 404);
}

function getJsonBody(): array
{
    $raw = file_get_contents('php://input');
    $data = json_decode($raw ?: '{}', true);

    return is_array($data) ? $data : [];
}

function jsonResponse(array $data, int $status = 200): void
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function detectSep(string $line): string
{
    if (str_contains($line, "\t")) {
        return "\t";
    }

    if (str_contains($line, ';')) {
        return ';';
    }

    return ',';
}

function parseMassa(string $raw): array
{
    $lines = preg_split('/\r\n|\r|\n/', trim($raw)) ?: [];
    $lines = array_values(array_filter(array_map('trim', $lines), static fn (string $line): bool => $line !== ''));

    if ($lines === []) {
        return ['headers' => [], 'rows' => []];
    }

    $separator = detectSep($lines[0]);
    $firstLine = array_map('trim', str_getcsv($lines[0], $separator));
    $hasHeader = false;

    foreach ($firstLine as $value) {
        $normalized = mb_strtolower($value);
        if (
            str_contains($normalized, 'cpf') ||
            str_contains($normalized, 'nome') ||
            str_contains($normalized, 'conta') ||
            str_contains($normalized, 'agência') ||
            str_contains($normalized, 'agencia')
        ) {
            $hasHeader = true;
            break;
        }
    }

    $headers = $hasHeader ? $firstLine : [];
    $dataLines = $hasHeader ? array_slice($lines, 1) : $lines;
    $rows = [];

    foreach ($dataLines as $line) {
        $values = array_map('trim', str_getcsv($line, detectSep($line)));

        if ($headers !== []) {
            $row = [];
            foreach ($headers as $index => $header) {
                $row[$header] = $values[$index] ?? '';
            }
            $rows[] = $row;
            continue;
        }

        $rows[] = $values;
    }

    return ['headers' => $headers, 'rows' => $rows];
}

function parseDNS(string $raw): array
{
    $lines = preg_split('/\r\n|\r|\n/', trim($raw)) ?: [];
    $lines = array_values(array_filter(array_map('trim', $lines), static fn (string $line): bool => $line !== ''));
    $rows = [];

    foreach ($lines as $line) {
        $parts = preg_split('/\s+/', $line) ?: [];
        $parts = array_values(array_filter($parts, static fn (string $part): bool => $part !== ''));

        if (count($parts) >= 2) {
            $env = strtoupper((string) array_shift($parts));
            $url = implode(' ', $parts);
        } else {
            $url = $parts[0] ?? '';
            $env = inferEnv($url);
        }

        $rows[] = [
            'env' => $env,
            'url' => $url,
        ];
    }

    return ['rows' => $rows];
}

function inferEnv(string $url): string
{
    $normalized = mb_strtolower($url);

    if (str_contains($normalized, 'hml') || str_contains($normalized, 'homolog')) {
        return 'HML';
    }

    if (str_contains($normalized, 'prd') || str_contains($normalized, 'prod')) {
        return 'PROD';
    }

    if (str_contains($normalized, 'dev')) {
        return 'DEV';
    }

    if (str_contains($normalized, 'sit')) {
        return 'SIT';
    }

    if (str_contains($normalized, 'uat')) {
        return 'UAT';
    }

    if (str_contains($normalized, 'qas')) {
        return 'QAS';
    }

    return 'N/A';
}

function buildCombined(array $massas, array $dns): array
{
    $combined = [];
    $massaRows = $massas['rows'] ?? [];
    $dnsRows = $dns['rows'] ?? [];

    foreach ($massaRows as $massaRow) {
        foreach ($dnsRows as $dnsRow) {
            $combined[] = [
                'massa' => $massaRow,
                'dns' => $dnsRow,
            ];
        }
    }

    return $combined;
}

function toCSV(array $headers, array $rows): string
{
    $handle = fopen('php://temp', 'r+');

    if ($headers !== []) {
        fputcsv($handle, $headers);
    }

    foreach ($rows as $row) {
        if (is_array($row) && array_keys($row) !== range(0, count($row) - 1)) {
            $orderedRow = [];
            foreach ($headers as $header) {
                $orderedRow[] = $row[$header] ?? '';
            }
            fputcsv($handle, $orderedRow);
            continue;
        }

        fputcsv($handle, is_array($row) ? $row : [$row]);
    }

    rewind($handle);
    $csv = stream_get_contents($handle) ?: '';
    fclose($handle);

    return $csv;
}
