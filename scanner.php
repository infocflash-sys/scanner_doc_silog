<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
    <title>Escáner - Misenvios</title>
    <link rel="stylesheet" href="css/style.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/html2pdf.js/0.10.1/html2pdf.bundle.min.js"></script>
</head>
<body>
    <!-- 1. FORMULARIO INGRESO -->
    <div id="formularioIngreso" class="pantalla-formulario">
        <div class="header-simple">
            <h1>Escáner de Documentos</h1>
        </div>
        <div class="form-container">
            <h2>Ingrese ID de Pieza</h2>
            <input type="text" id="idPieza" placeholder="Ej: 123456" class="input-field">
            <button onclick="validarPieza()" class="btn btn-primary">Validar</button>
            <div id="mensajeValidacion" class="mensaje"></div>
        </div>
    </div>

    <!-- 2. INTERFAZ DE CAPTURA -->
    <div id="interfazCaptura" class="pantalla-captura" style="display:none;">
        <div class="header-captura">
            <span id="titulo-captura">Captura en Progreso</span>
            <span id="contador-fotos" class="badge">0 fotos</span>
        </div>

        <div class="video-principal">
            <video id="videoStream" autoplay playsinline></video>
            <canvas id="canvasDetection" style="display:none;"></canvas>
            <div id="estadoCaptura" class="estado-detector">📷 Cámara lista</div>
        </div>

        <div class="controles-captura">
            <button onclick="volverAlMenu()" class="btn btn-control btn-volver">↩️ Volver</button>
            <button onclick="capturarManual()" class="btn btn-control btn-capturar">📸 Capturar</button>
            <button onclick="mostrarGaleria()" class="btn btn-control" id="btn-galeria" style="display:none;">➡️ Continuar</button>
        </div>
    </div>

    <!-- 4. PREVIEW DE CAPTURA -->
    <div id="previewCaptura" class="pantalla-captura" style="display:none;">
        <div class="header-captura">
            <span>Confirmar Captura</span>
            <span class="badge" id="preview-numero">Foto 1</span>
        </div>

        <div class="video-principal">
            <img id="previewImg" src="" style="width:100%; height:100%; object-fit:contain; background: #000;">
        </div>

        <div class="controles-captura">
            <button onclick="descartarCaptura()" class="btn btn-control btn-descartar">❌ Descartar</button>
            <button onclick="confirmarCaptura()" class="btn btn-control btn-confirmar">✓ Confirmar</button>
        </div>
    </div>

    <!-- 5. GALERÍA DE FOTOS -->
    <div id="galeriaFotos" class="pantalla-formulario" style="display:none; flex-direction: column;">
        <div class="header-simple">
            <h1>Fotos Capturadas</h1>
        </div>
        <div class="form-container" style="flex: 0; padding: 15px; gap: 10px;">
            <button onclick="volverACapturar()" class="btn btn-primary">➕ Capturar Más</button>
            <button onclick="generarPDF()" class="btn btn-success">✅ Generar PDF</button>
        </div>
        <div class="galeria-container" style="flex: 1;">
            <div id="galeriaContent" class="galeria-grid"></div>
        </div>
    </div>

    <!-- 6. PROGRESO DE SUBIDA -->
    <div id="progresoCarga" class="pantalla-formulario" style="display:none;">
        <div class="header-simple">
            <h1>Subiendo Documento</h1>
        </div>
        <div class="form-container">
            <div class="progress-container">
                <div class="progress-bar" id="progressBar"></div>
            </div>
            <p id="textoProgreso">Generando PDF...</p>
        </div>
    </div>

    <!-- 7. ÉXITO -->
    <div id="exitoSubida" class="pantalla-formulario" style="display:none;">
        <div class="header-simple">
            <h1>✓ Éxito</h1>
        </div>
        <div class="form-container exito-box">
            <p id="textoExito"></p>
            <button onclick="reiniciar()" class="btn btn-primary">🔄 Nuevo Escaneo</button>
        </div>
    </div>

    <!-- 8. ERROR -->
    <div id="error" class="pantalla-formulario" style="display:none;">
        <div class="header-simple">
            <h1>✕ Error</h1>
        </div>
        <div class="form-container error-box">
            <p id="textoError"></p>
            <button onclick="reiniciar()" class="btn btn-primary">Volver</button>
        </div>
    </div>

    <script src="js/scanner.js"></script>
</body>
</html>
