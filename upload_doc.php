<?php
require __DIR__ . '/config.php';

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    fail('Método no permitido', 405);
}

$auth = require_auth();
$c = cfg();
$id_pieza = sanitize_id($_POST['id_pieza'] ?? '');

// ---- Validación del archivo ----
if (!isset($_FILES['pdf_file']) || $_FILES['pdf_file']['error'] !== UPLOAD_ERR_OK) {
    $err = $_FILES['pdf_file']['error'] ?? UPLOAD_ERR_NO_FILE;
    if ($err === UPLOAD_ERR_INI_SIZE || $err === UPLOAD_ERR_FORM_SIZE) {
        fail('El archivo excede el tamaño permitido por el servidor', 413);
    }
    fail('No se recibió el archivo PDF', 400);
}

$tmp = $_FILES['pdf_file']['tmp_name'];
if (!is_uploaded_file($tmp)) fail('Subida inválida', 400);

$size = filesize($tmp);
if ($size === false || $size === 0) fail('El archivo está vacío', 400);
if ($size > $c['max_bytes']) {
    fail('El PDF supera el máximo de ' . round($c['max_bytes'] / 1048576) . ' MB', 413);
}

// El contenido debe ser realmente un PDF (no basta con la extensión ni el tipo declarado).
$fh = fopen($tmp, 'rb');
$magic = $fh ? fread($fh, 5) : '';
if ($fh) fclose($fh);
if ($magic !== '%PDF-') fail('El archivo no es un PDF válido', 415);

if ($c['target_dir'] === '' || !is_dir($c['target_dir'])) {
    error_log('[doc_silog] target_dir inválido');
    fail('Servidor sin configurar', 500);
}

// ---- Regla de negocio: una pieza con PDF asignado NO admite otro ----
$conn = db();

$stmt = $conn->prepare('SELECT docum_file FROM flash_piezas WHERE id = ?');
$stmt->bind_param('s', $id_pieza);
$stmt->execute();
$row = $stmt->get_result()->fetch_assoc();
$stmt->close();

if (!$row) fail('La pieza no existe', 404, 'no_encontrada');

if (trim((string)($row['docum_file'] ?? '')) !== '') {
    fail(
        'La pieza ya tiene un PDF asignado (' . $row['docum_file'] . '). '
        . 'Para reemplazarlo, un administrador debe eliminarlo primero desde el ERP.',
        409,
        'ya_tiene_pdf'
    );
}

// ---- Guardado atómico: 'x' falla si el archivo ya existe (evita carreras y sobrescrituras) ----
// <id_pieza>-<id_usuario>.pdf: queda registrado quién subió el documento.
$file_name = $id_pieza . '-' . (int)$auth['id'] . '.pdf';
$target = rtrim($c['target_dir'], '/\\') . DIRECTORY_SEPARATOR . $file_name;

$out = @fopen($target, 'x');
if ($out === false) {
    // Existe en disco aunque la BD no lo refleje: no se pisa.
    fail('Ya existe un archivo con ese nombre en el servidor. Contacta a un administrador.', 409, 'ya_tiene_pdf');
}
$in = fopen($tmp, 'rb');
$ok = $in && stream_copy_to_stream($in, $out) === $size;
if ($in) fclose($in);
fclose($out);

if (!$ok) {
    @unlink($target);
    error_log('[doc_silog] fallo al copiar PDF a ' . $target);
    fail('Error al guardar el archivo', 500);
}
@chmod($target, 0644);

// ---- Actualizar BD solo si sigue vacío (protege contra subidas simultáneas) ----
$upd = $conn->prepare(
    "UPDATE flash_piezas SET docum_file = ? WHERE id = ? AND (docum_file IS NULL OR docum_file = '')"
);
$upd->bind_param('ss', $file_name, $id_pieza);
$upd->execute();
$changed = $upd->affected_rows;
$upd->close();
$conn->close();

if ($changed < 1) {
    @unlink($target);
    fail('La pieza ya tiene un PDF asignado.', 409, 'ya_tiene_pdf');
}

json_out([
    'status'   => 'success',
    'message'  => 'Documento subido correctamente',
    'file'     => $file_name,
    'version'  => 1,
    'id_pieza' => $id_pieza,
]);
