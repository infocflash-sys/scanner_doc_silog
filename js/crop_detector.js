let detectorState = {
    detector: null,
    canvas: null,
    ctx: null,
    isRunning: false,
    detectedBox: null,
    stability: 0,
    previousBox: null
};

async function initializeDetector(videoElement, canvasElement) {
    detectorState.canvas = canvasElement;
    detectorState.ctx = canvasElement.getContext('2d');

    try {
        console.log('Cargando modelo de detección...');
        detectorState.detector = await ml5.objectDetector('coco-ssd');
        console.log('✅ Detector listo');
        startDetection(videoElement);
    } catch (error) {
        console.error('Error al cargar detector:', error);
        console.log('⚠️ Detección deshabilitada, captura manual');
    }
}

function startDetection(videoElement) {
    detectorState.isRunning = true;
    detectFrame(videoElement);
}

function stopDetection() {
    detectorState.isRunning = false;
}

async function detectFrame(videoElement) {
    if (!detectorState.isRunning || !detectorState.detector) return;

    detectorState.canvas.width = videoElement.videoWidth;
    detectorState.canvas.height = videoElement.videoHeight;

    const ctx = detectorState.ctx;
    ctx.drawImage(videoElement, 0, 0);

    try {
        const predictions = await detectorState.detector.detect(videoElement);
        const documentBox = findDocumentBox(predictions);

        if (documentBox) {
            detectorState.detectedBox = documentBox;
            drawDetectionBox(documentBox);
            updateStability(documentBox);
        } else {
            detectorState.stability = 0;
            drawNoDetection();
        }
    } catch (error) {
        console.error('Error en detección:', error);
    }

    if (detectorState.isRunning) {
        requestAnimationFrame(() => detectFrame(videoElement));
    }
}

function findDocumentBox(predictions) {
    if (!predictions || predictions.length === 0) return null;

    const documents = predictions.filter(p => {
        const label = p.label.toLowerCase();
        return (label.includes('book') || label.includes('document') ||
                label.includes('paper') || label.includes('laptop') ||
                label.includes('phone')) && p.confidence > 0.4;
    });

    if (documents.length === 0) return null;

    const best = documents.reduce((prev, current) =>
        (prev.confidence > current.confidence) ? prev : current
    );

    return {
        x: Math.max(0, best.x),
        y: Math.max(0, best.y),
        width: Math.min(detectorState.canvas.width - best.x, best.width),
        height: Math.min(detectorState.canvas.height - best.y, best.height),
        confidence: best.confidence,
        label: best.label
    };
}

function updateStability(box) {
    if (!detectorState.previousBox) {
        detectorState.previousBox = box;
        detectorState.stability = 0.5;
        return;
    }

    const dx = Math.abs(box.x - detectorState.previousBox.x);
    const dy = Math.abs(box.y - detectorState.previousBox.y);
    const dw = Math.abs(box.width - detectorState.previousBox.width);
    const dh = Math.abs(box.height - detectorState.previousBox.height);

    const movement = dx + dy + dw + dh;
    const threshold = detectorState.canvas.width * 0.05;

    if (movement < threshold) {
        detectorState.stability = Math.min(1, detectorState.stability + 0.15);
    } else {
        detectorState.stability = Math.max(0, detectorState.stability - 0.1);
    }

    detectorState.previousBox = box;

    if (detectorState.stability > 0.8) {
        suggestAutoCapture();
    }
}

function suggestAutoCapture() {
    const badge = document.getElementById('detector-status');
    if (badge) {
        badge.textContent = '✅ Listo para capturar';
        badge.style.backgroundColor = 'rgba(40, 167, 69, 0.9)';
        badge.style.animation = 'pulse 1s infinite';
    }
}

function drawDetectionBox(box) {
    const ctx = detectorState.ctx;
    const stability = detectorState.stability;

    const color = stability > 0.7 ? '#17a2b8' : '#ffc107';
    ctx.strokeStyle = color;
    ctx.lineWidth = 3;
    ctx.globalAlpha = 0.8;

    ctx.strokeRect(box.x, box.y, box.width, box.height);

    ctx.fillStyle = color;
    ctx.globalAlpha = 0.3;
    ctx.fillRect(box.x, box.y, box.width, box.height);

    ctx.globalAlpha = 1;

    const cornerSize = 20;
    ctx.fillStyle = color;
    ctx.fillRect(box.x, box.y, cornerSize, 2);
    ctx.fillRect(box.x, box.y, 2, cornerSize);

    ctx.fillRect(box.x + box.width - cornerSize, box.y, cornerSize, 2);
    ctx.fillRect(box.x + box.width - 2, box.y, 2, cornerSize);

    ctx.fillRect(box.x, box.y + box.height - 2, cornerSize, 2);
    ctx.fillRect(box.x, box.y + box.height - cornerSize, 2, cornerSize);

    ctx.fillRect(box.x + box.width - cornerSize, box.y + box.height - 2, cornerSize, 2);
    ctx.fillRect(box.x + box.width - 2, box.y + box.height - cornerSize, 2, cornerSize);

    drawStabilityIndicator(stability);
}

function drawNoDetection() {
    const ctx = detectorState.ctx;
    ctx.fillStyle = 'rgba(255, 255, 255, 0.7)';
    ctx.font = 'bold 18px Arial';
    ctx.textAlign = 'center';
    ctx.fillText('📄 Enfoca un documento', detectorState.canvas.width / 2, detectorState.canvas.height / 2);

    const badge = document.getElementById('detector-status');
    if (badge) {
        badge.textContent = '📄 Enfoca documento';
        badge.style.backgroundColor = 'rgba(255, 193, 7, 0.9)';
        badge.style.animation = 'none';
    }
}

function drawStabilityIndicator(stability) {
    const ctx = detectorState.ctx;
    const barWidth = 200;
    const barHeight = 8;
    const x = detectorState.canvas.width / 2 - barWidth / 2;
    const y = detectorState.canvas.height - 40;

    ctx.fillStyle = 'rgba(0, 0, 0, 0.5)';
    ctx.fillRect(x, y, barWidth, barHeight);

    const fillColor = stability > 0.7 ? '#17a2b8' : (stability > 0.4 ? '#ffc107' : '#dc3545');
    ctx.fillStyle = fillColor;
    ctx.fillRect(x, y, barWidth * stability, barHeight);

    ctx.strokeStyle = 'rgba(255, 255, 255, 0.8)';
    ctx.lineWidth = 1;
    ctx.strokeRect(x, y, barWidth, barHeight);

    ctx.fillStyle = 'rgba(255, 255, 255, 0.9)';
    ctx.font = '12px Arial';
    ctx.textAlign = 'center';
    ctx.fillText(`${Math.round(stability * 100)}%`, detectorState.canvas.width / 2, y - 5);
}

function getDetectedCrop() {
    if (!detectorState.detectedBox) return null;

    const box = detectorState.detectedBox;
    return {
        x: Math.floor(box.x),
        y: Math.floor(box.y),
        width: Math.floor(box.width),
        height: Math.floor(box.height)
    };
}
