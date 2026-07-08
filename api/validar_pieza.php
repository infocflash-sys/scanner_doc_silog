<?php
header('Content-Type: application/json');
mysqli_report(MYSQLI_REPORT_OFF);

$db_host = "173.231.200.130";
$db_name = "intran23_mis_envios";
$db_user = "intran23_Alvaro";
$db_pass = "Alvaro1324";

$id_pieza = $_GET['id_pieza'] ?? '';

if ($id_pieza === '') {
    echo json_encode(["status" => "error", "message" => "ID de pieza no proporcionado"]);
    exit;
}

$conn = new mysqli($db_host, $db_user, $db_pass, $db_name);
if ($conn->connect_error) {
    echo json_encode(["status" => "error", "message" => "Error de conexión a BD"]);
    exit;
}

$conn->set_charset("utf8");

$stmt = $conn->prepare("SELECT fp.id, fp.create, fc.nombre AS cliente FROM flash_piezas fp JOIN flash_comprobantes_ingresos fci ON fp.comprobante_ingreso_id = fci.id JOIN flash_clientes fc ON fci.cliente_id = fc.id WHERE fp.id = ?");

if ($stmt === false) {
    echo json_encode(["status" => "error", "message" => "Error en consulta"]);
    exit;
}

$stmt->bind_param("s", $id_pieza);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    echo json_encode(["status" => "error", "message" => "Pieza no encontrada"]);
    $stmt->close();
    $conn->close();
    exit;
}

$pieza = $result->fetch_assoc();
$stmt->close();
$conn->close();

echo json_encode([
    "status" => "success",
    "data" => [
        "id" => $pieza['id'],
        "cliente" => $pieza['cliente'],
        "fecha_creacion" => $pieza['create']
    ]
]);
?>
