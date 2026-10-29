<?php
require __DIR__ . '/../config.php';

// Público (sin sesión): la app lo consulta al abrir para saber si esta versión sigue habilitada.
$st = app_status();
json_out([
    'status'    => 'success',
    'permitido' => app_permitida($st),
    'mensaje'   => $st['mensaje'],
    'url'       => $st['url'],
]);
