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
        // Secreto para firmar las sesiones de la app (obligatorio; ver config.local.example.php).
        'auth_secret' => $file['auth_secret'] ?? getenv('SILOG_AUTH_SECRET') ?: '',
        'session_ttl' => (int)($file['session_ttl'] ?? 86400),   // 24 h
        'max_fails'   => (int)($file['max_fails'] ?? 3),          // intentos fallidos por usuario
        'lock_secs'   => (int)($file['lock_secs'] ?? 300),        // 5 min de bloqueo
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

// ============================================================
//  Autenticación (usuarios del ERP: tabla `users`, solo lectura)
// ============================================================

function b64u_enc(string $s): string { return rtrim(strtr(base64_encode($s), '+/', '-_'), '='); }
function b64u_dec(string $s): string { return (string)base64_decode(strtr($s, '-_', '+/')); }

/**
 * Comprueba la clave con el esquema del ERP (Ion Auth sin salt almacenado):
 * hash = salt(10 car.) . substr(sha1(salt . clave), 0, 30).
 */
function verify_password(string $stored, string $password): bool {
    if (strlen($stored) !== 40) return false;
    $salt = substr($stored, 0, 10);
    return hash_equals($stored, $salt . substr(sha1($salt . $password), 0, 30));
}

/** Sesión sin estado: payload.firma (HMAC-SHA256). Vence según session_ttl (24 h). */
function token_issue(int $uid): string {
    $c = cfg();
    if ($c['auth_secret'] === '') {
        error_log('[doc_silog] auth_secret no configurado');
        fail('Servidor sin configurar', 500);
    }
    $payload = b64u_enc(json_encode(['uid' => $uid, 'exp' => time() + $c['session_ttl']]));
    return $payload . '.' . b64u_enc(hash_hmac('sha256', $payload, $c['auth_secret'], true));
}

// ============================================================
//  Control de versiones de la app (tabla silog_app_config)
// ============================================================

/**
 * Estado de la app según la BD: app_activa (1/0), build_minimo, mensaje, url_descarga.
 * Si la tabla no responde NO se bloquea (se registra el error): una falla de config no debe tumbar el servicio.
 */
function app_status(): array {
    $def = ['activa' => true, 'build_minimo' => 0,
            'mensaje' => 'Esta versión de Doc SILOG ya no está habilitada. Instala la versión más reciente o contacta a un administrador.',
            'url' => ''];
    $c = cfg();
    if ($c['db_name'] === '' || $c['db_user'] === '') return $def;
    $conn = @new mysqli($c['db_host'], $c['db_user'], $c['db_pass'], $c['db_name']);
    if ($conn->connect_error) { error_log('[doc_silog] app_status BD: ' . $conn->connect_error); return $def; }
    $conn->set_charset('utf8mb4');
    $r = $conn->query('SELECT clave, valor FROM silog_app_config');
    if (!$r) { error_log('[doc_silog] app_status: ' . $conn->error); $conn->close(); return $def; }
    $v = [];
    while ($f = $r->fetch_assoc()) $v[$f['clave']] = $f['valor'];
    $conn->close();
    return [
        'activa'       => ($v['app_activa'] ?? '1') !== '0',
        'build_minimo' => (int)($v['build_minimo'] ?? 0),
        'mensaje'      => trim($v['mensaje'] ?? '') !== '' ? $v['mensaje'] : $def['mensaje'],
        'url'          => trim($v['url_descarga'] ?? ''),
    ];
}

/** Build que declara la app en la cabecera X-Silog-Build (0 si no la envía: versiones antiguas). */
function app_build(): int { return (int)($_SERVER['HTTP_X_SILOG_BUILD'] ?? 0); }

function app_permitida(array $st): bool { return $st['activa'] && app_build() >= $st['build_minimo']; }

/** Termina con 426 (code "version") si esta versión de la app no está habilitada. */
function check_app_version(): void {
    $st = app_status();
    if (app_permitida($st)) return;
    json_out(['status' => 'error', 'code' => 'version', 'message' => $st['mensaje'], 'url' => $st['url']], 426);
}

/** Devuelve el usuario de la sesión o termina con 401 (code "sesion"). Reconsulta `active` en cada petición. */
function require_auth(): array {
    check_app_version();
    $c = cfg();
    $tok = $_SERVER['HTTP_X_SILOG_TOKEN'] ?? '';
    $parts = explode('.', $tok);
    if ($c['auth_secret'] === '' || count($parts) !== 2) fail('Sesión no válida. Inicia sesión.', 401, 'sesion');

    $sig = b64u_enc(hash_hmac('sha256', $parts[0], $c['auth_secret'], true));
    if (!hash_equals($sig, $parts[1])) fail('Sesión no válida. Inicia sesión.', 401, 'sesion');

    $data = json_decode(b64u_dec($parts[0]), true);
    if (!is_array($data) || !isset($data['uid'], $data['exp']) || (int)$data['exp'] < time()) {
        fail('Tu sesión venció. Inicia sesión nuevamente.', 401, 'sesion');
    }

    $conn = db();
    $stmt = $conn->prepare('SELECT id, nombre, apellido FROM users WHERE id = ? AND active = 1');
    $uid = (int)$data['uid'];
    $stmt->bind_param('i', $uid);
    $stmt->execute();
    $u = $stmt->get_result()->fetch_assoc();
    $stmt->close();
    $conn->close();
    if (!$u) fail('Tu usuario ya no está activo.', 401, 'sesion');
    return $u;
}

// ---- Bloqueo por intentos fallidos (archivos en el temporal del sistema; no toca la BD) ----

function lock_path(string $key): string {
    $dir = sys_get_temp_dir() . DIRECTORY_SEPARATOR . 'silog_auth';
    if (!is_dir($dir)) @mkdir($dir, 0700, true);
    return $dir . DIRECTORY_SEPARATOR . $key . '.json';
}

function lock_read(string $key): array {
    $base = ['fails' => 0, 'last' => 0, 'until' => 0];
    $raw = @file_get_contents(lock_path($key));
    $d = $raw ? json_decode($raw, true) : null;
    return is_array($d) ? $d + $base : $base;
}

/** Segundos que faltan para que termine el bloqueo (0 si no está bloqueado). */
function lock_remaining(string $key): int {
    return max(0, (int)lock_read($key)['until'] - time());
}

/** Registra un fallo; al llegar al máximo bloquea. Devuelve [fallos_acumulados, segundos_de_bloqueo]. */
function lock_fail(string $key, int $max, int $secs): array {
    $d = lock_read($key);
    $expired = (int)$d['until'] > 0 && (int)$d['until'] <= time();
    if ($expired || time() - (int)$d['last'] > 900) $d['fails'] = 0;
    $d['fails'] = (int)$d['fails'] + 1;
    $d['last'] = time();
    $d['until'] = 0;
    if ($d['fails'] >= $max) { $d['until'] = time() + $secs; $d['fails'] = 0; }
    @file_put_contents(lock_path($key), json_encode($d), LOCK_EX);
    return [$d['fails'], max(0, $d['until'] - time())];
}

function lock_clear(string $key): void { @unlink(lock_path($key)); }
