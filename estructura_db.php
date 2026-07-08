<?php
header('Content-Type: text/html; charset=utf-8');

$db_host = "localhost";
$db_name = "intran23_mis_envios";
$db_user = "intran23_Alvaro";
$db_pass = "Alvaro1324";

$conn = new mysqli($db_host, $db_user, $db_pass, $db_name);
if ($conn->connect_error) {
    die("Error conexión: " . $conn->connect_error);
}

$conn->set_charset("utf8");

echo "<h2>Estructura BD - intran23_mis_envios</h2>";

$tablas = ['flash_piezas', 'flash_comprobantes_ingresos', 'flash_clientes'];

foreach ($tablas as $tabla) {
    echo "<h3>Tabla: $tabla</h3>";
    echo "<pre>";
    $result = $conn->query("DESCRIBE $tabla");
    while ($row = $result->fetch_assoc()) {
        echo implode(" | ", $row) . "\n";
    }
    echo "</pre>";
    
    echo "<h4>Primeras 2 filas:</h4>";
    echo "<pre>";
    $result = $conn->query("SELECT * FROM $tabla LIMIT 2");
    while ($row = $result->fetch_assoc()) {
        print_r($row);
    }
    echo "</pre>";
}

$conn->close();
?>
