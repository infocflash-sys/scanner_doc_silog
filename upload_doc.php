<?php
header('Content-Type: application/json');
mysqli_report(MYSQLI_REPORT_OFF);

$db_host = "173.231.200.130";
$db_name = "intran23_mis_envios";
$db_user = "intran23_Alvaro";
$db_pass = "Alvaro1324";
$target_dir = "/home/intran23/archivoscompartidos.intranetflash.com/public/archivos/documentacion/";

function fail($msg) {
    echo json_encode(["status" => "error", "message" => $msg]);
    exit;
}

try {
    $id_pieza = $_POST['id_pieza'] ?? '';
    if (empty($id_pieza)) fail("ID de pieza no proporcionado");

    if (!isset($_FILES["pdf_file"])) {
        fail("No se recibió archivo PDF");
    }

    // Conexión BD
    $conn = new mysqli($db_host, $db_user, $db_pass, $db_name);
    if ($conn->connect_error) fail("Conexión BD fallida");

    $stmt = $conn->prepare("SELECT id FROM flash_piezas WHERE id = ?");
    $stmt->bind_param("s", $id_pieza);
    $stmt->execute();
    if ($stmt->get_result()->num_rows === 0) fail("Pieza no existe");
    $stmt->close();

    // Generar nombre con versionado
    $file_name = $id_pieza . ".pdf";
    $target_file = $target_dir . $file_name;
    $version = 1;

    while (file_exists($target_file)) {
        $file_name = $id_pieza . "_v" . $version . ".pdf";
        $target_file = $target_dir . $file_name;
        $version++;
    }

    // Guardar archivo
    if (!move_uploaded_file($_FILES["pdf_file"]["tmp_name"], $target_file)) {
        fail("Error al guardar archivo. Verifica permisos o ruta.");
    }

    if (!file_exists($target_file)) {
        fail("Archivo no se guardó correctamente.");
    }

    // Actualizar BD
    if ($version === 1) {
        $upd = $conn->prepare("UPDATE flash_piezas SET docum_file = ? WHERE id = ?");
        $upd->bind_param("ss", $file_name, $id_pieza);
        $upd->execute();
        $upd->close();
    }

    $conn->close();

    echo json_encode([
        "status" => "success",
        "message" => "Documento subido correctamente",
        "file" => $file_name,
        "version" => $version,
        "id_pieza" => $id_pieza
    ]);

} catch (Exception $e) {
    echo json_encode(["status" => "error", "message" => "Error: " . $e->getMessage()]);
}
?>
