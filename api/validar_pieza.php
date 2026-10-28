<?php
require __DIR__ . '/../config.php';

$id_pieza = sanitize_id($_GET['id_pieza'] ?? '');

$conn = db();

$stmt = $conn->prepare(
    'SELECT fp.id, fp.`create`, fp.docum_file, fc.nombre AS cliente
       FROM flash_piezas fp
       JOIN flash_comprobantes_ingresos fci ON fp.comprobante_ingreso_id = fci.id
       JOIN flash_clientes fc ON fci.cliente_id = fc.id
      WHERE fp.id = ?'
);
if ($stmt === false) {
    error_log('[doc_silog] prepare validar: ' . $conn->error);
    fail('Error en consulta', 500);
}

$stmt->bind_param('s', $id_pieza);
$stmt->execute();
$pieza = $stmt->get_result()->fetch_assoc();
$stmt->close();
$conn->close();

if (!$pieza) {
    fail('Pieza no encontrada', 404, 'no_encontrada');
}

$docum = trim((string)($pieza['docum_file'] ?? ''));

json_out([
    'status' => 'success',
    'data' => [
        'id'             => $pieza['id'],
        'cliente'        => $pieza['cliente'],
        'fecha_creacion' => $pieza['create'],
        'tiene_pdf'      => $docum !== '',
        'docum_file'     => $docum !== '' ? $docum : null,
    ],
]);
