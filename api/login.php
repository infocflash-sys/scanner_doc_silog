<?php
require __DIR__ . '/../config.php';

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') fail('Método no permitido', 405);

check_app_version();
$c = cfg();
$username = trim((string)($_POST['username'] ?? ''));
$password = (string)($_POST['password'] ?? '');
if ($username === '' || $password === '' || strlen($username) > 100 || strlen($password) > 200) {
    fail('Ingresa usuario y clave', 400, 'datos');
}

$ku = 'u_' . sha1(mb_strtolower($username));
$ki = 'i_' . sha1($_SERVER['REMOTE_ADDR'] ?? '');
$ip_max = 15; // la IP puede ser compartida (red de la empresa): umbral mayor que el del usuario

$wait = max(lock_remaining($ku), lock_remaining($ki));
if ($wait > 0) {
    json_out([
        'status' => 'error', 'code' => 'bloqueado', 'retry_after' => $wait,
        'message' => 'Demasiados intentos. Espera ' . ceil($wait / 60) . ' min para volver a intentar.',
    ], 429);
}

$conn = db();
$stmt = $conn->prepare('SELECT id, username, password, active, nombre, apellido FROM users WHERE username = ?');
$stmt->bind_param('s', $username);
$stmt->execute();
$u = $stmt->get_result()->fetch_assoc();
$stmt->close();
$conn->close();

// Mismo mensaje exista o no el usuario (no revela cuáles existen).
$ok = $u && verify_password((string)$u['password'], $password);

if (!$ok) {
    [$fails, $lock] = lock_fail($ku, $c['max_fails'], $c['lock_secs']);
    lock_fail($ki, $ip_max, $c['lock_secs']);
    if ($lock > 0) {
        json_out([
            'status' => 'error', 'code' => 'bloqueado', 'retry_after' => $lock,
            'message' => 'Demasiados intentos. Espera ' . ceil($lock / 60) . ' min para volver a intentar.',
        ], 429);
    }
    json_out([
        'status' => 'error', 'code' => 'credenciales',
        'message' => 'Usuario o clave incorrectos.',
        'intentos_restantes' => max(0, $c['max_fails'] - $fails),
    ], 401);
}

if ((int)$u['active'] !== 1) {
    fail('Tu usuario está inactivo. Contacta a un administrador.', 403, 'inactivo');
}

lock_clear($ku);
json_out([
    'status'     => 'success',
    'token'      => token_issue((int)$u['id']),
    'expires_in' => $c['session_ttl'],
    'user'       => [
        'id'     => (int)$u['id'],
        'nombre' => trim(($u['nombre'] ?? '') . ' ' . ($u['apellido'] ?? '')) ?: $u['username'],
    ],
]);
