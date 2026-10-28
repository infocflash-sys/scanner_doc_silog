<?php
/**
 * Configuración y utilidades compartidas de la API de Doc SILOG.
 *
 * Las credenciales NO viven en el código: se leen de config.local.php
 * (ignorado por git; ver config.local.example.php) o de variables de entorno.
 */

if (basename($_SERVER['SCRIPT_FILENAME'] ?? '') === basename(__FILE__)) {
    http_response_code(403);
    exit;
}

mysqli_report(MYSQLI_REPORT_OFF);

function cfg(): array {
    static $cfg = null;
    if ($cfg !== null) return $cfg;

    $local = __DIR__ . '/config.local.php';
    $file = is_file($local) ? require $local : [];

    $cfg = [
        'db_host'    => $file['db_host']    ?? getenv('SILOG_DB_HOST') ?: 'localhost',
        'db_name'    => $file['db_name']    ?? getenv('SILOG_DB_NAME') ?: '',
        'db_user'    => $file['db_user']    ?? getenv('SILOG_DB_USER') ?: '',
        'db_pass'    => $file['db_pass']    ?? getenv('SILOG_DB_PASS') ?: '',
        'target_dir' => $file['target_dir'] ?? getenv('SILOG_TARGET_DIR') ?: '',
        // Tamaño máximo del PDF en bytes (por defecto 25 MB).
        'max_bytes'  => (int)($file['max_bytes'] ?? 25 * 1024 * 1024),
    ];
    return $cfg;
}

function json_out(array $payload, int $status = 200): void {
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('X-Content-Type-Options: nosniff');
    header('Cache-Control: no-store');
    echo json_encode($payload, JSON_UNESCAPED_UNICODE);
    exit;
}

function fail(string $msg, int $status = 400, ?string $code = null): void {
    $out = ['status' => 'error', 'message' => $msg];
    if ($code !== null) $out['code'] = $code;
    json_out($out, $status);
}

function db(): mysqli {
    $c = cfg();
    if ($c['db_name'] === '' || $c['db_user'] === '') {
        error_log('[doc_silog] config.local.php no configurado');
        fail('Servidor sin configurar', 500);
    }
    $conn = @new mysqli($c['db_host'], $c['db_user'], $c['db_pass'], $c['db_name']);
    if ($conn->connect_error) {
        error_log('[doc_silog] BD: ' . $conn->connect_error);
        fail('No se pudo conectar a la base de datos', 503);
    }
    $conn->set_charset('utf8mb4');
    return $conn;
}

/** El ID de pieza solo admite caracteres seguros (también se usa para armar el nombre del archivo). */
function sanitize_id(string $id): string {
    $id = trim($id);
    if ($id === '' || !preg_match('/^[A-Za-z0-9_-]{1,40}$/', $id)) {
        fail('ID de pieza inválido', 400);
    }
    return $id;
}
