let state = {
    idPieza: null,
    piezaData: null,
    stream: null,
    video: null,
    fotos: [],
    fotoTemp: null,
    usingFrontCamera: false
};

function mostrarPantalla(id) {
    document.querySelectorAll('[id^="formularioIngreso"], [id^="seleccionCaptura"], [id^="interfazCaptura"], [id^="previewCaptura"], [id^="galeriaFotos"], [id^="progresoCarga"], [id^="exitoSubida"], [id^="error"]').forEach(el => {
        el.style.display = 'none';
    });
    document.getElementById(id).style.display = 'flex';
}

async function validarPieza() {
    const idPieza = document.getElementById('idPieza').value.trim();
    const msg = document.getElementById('mensajeValidacion');

    if (!idPieza) {
        msg.className = 'mensaje error';
        msg.textContent = 'Ingrese ID de pieza';
        return;
    }

    msg.textContent = 'Validando...';
    msg.className = 'mensaje';

    try {
        const res = await fetch(`api/validar_pieza.php?id_pieza=${encodeURIComponent(idPieza)}`);
        const data = await res.json();

        if (data.status === 'error') {
            msg.className = 'mensaje error';
            msg.textContent = data.message;
            return;
        }

        state.idPieza = idPieza;
        state.piezaData = data.data;
        msg.className = 'mensaje success';
        msg.textContent = `✓ Pieza: ${data.data.cliente}`;

        setTimeout(() => {
            mostrarPantalla('interfazCaptura');
            iniciarCaptura();
        }, 500);
    } catch (error) {
        msg.className = 'mensaje error';
        msg.textContent = 'Error: ' + error.message;
    }
}

async function iniciarCaptura() {
    try {
        const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
        const facingMode = isMobile ? 'environment' : 'user';

        const constraints = {
            video: {
                facingMode: { ideal: facingMode },
                width: { ideal: 1280 },
                height: { ideal: 720 }
            },
            audio: false
        };

        state.stream = await navigator.mediaDevices.getUserMedia(constraints);
        state.video = document.getElementById('videoStream');
        state.video.srcObject = state.stream;

        state.video.onloadedmetadata = () => {
            state.video.play();
            updateEstado();

            setTimeout(() => {
                const canvas = document.getElementById('canvasDetection');
                initializeDetector(state.video, canvas);
            }, 500);
        };
    } catch (error) {
        mostrarError('Error cámara: ' + error.message);
    }
}

function updateEstado() {
    const estadoDiv = document.getElementById('estadoCaptura');
    estadoDiv.textContent = '📷 Cámara lista - Toca Capturar';
    estadoDiv.style.color = '#17a2b8';
}

function capturarManual() {
    const canvas = document.createElement('canvas');
    canvas.width = state.video.videoWidth;
    canvas.height = state.video.videoHeight;
    const ctx = canvas.getContext('2d');
    ctx.drawImage(state.video, 0, 0);

    const crop = getDetectedCrop();
    if (crop && crop.width > 0 && crop.height > 0) {
        const cropped = document.createElement('canvas');
        cropped.width = crop.width;
        cropped.height = crop.height;
        cropped.getContext('2d').drawImage(
            canvas,
            crop.x, crop.y, crop.width, crop.height,
            0, 0, crop.width, crop.height
        );
        state.fotoTemp = cropped;
    } else {
        state.fotoTemp = canvas;
    }

    mejorarYReducir(state.fotoTemp);
    mostrarPreview();
    reproducirSonido();
}

function mostrarPreview() {
    const img = document.getElementById('previewImg');
    img.src = state.fotoTemp.toDataURL('image/jpeg', 0.85);
    const num = state.fotos.length + 1;
    document.getElementById('preview-numero').textContent = `Foto ${num}`;
    mostrarPantalla('previewCaptura');
}

function descartarCaptura() {
    state.fotoTemp = null;
    mostrarPantalla('interfazCaptura');
}

function confirmarCaptura() {
    if (!state.fotoTemp) return;

    mejorarYReducir(state.fotoTemp);
    state.fotos.push(state.fotoTemp);
    state.fotoTemp = null;

    const badge = document.getElementById('contador-fotos');
    badge.textContent = `${state.fotos.length} fotos`;

    document.getElementById('btn-galeria').style.display = 'flex';

    mostrarPantalla('interfazCaptura');
}

function mostrarGaleria() {
    const container = document.getElementById('galeriaContent');
    container.innerHTML = '';

    state.fotos.forEach((foto, idx) => {
        const div = document.createElement('div');
        div.className = 'galeria-item';

        const img = document.createElement('img');
        img.src = foto.toDataURL('image/jpeg', 0.8);

        const num = document.createElement('div');
        num.className = 'numero';
        num.textContent = idx + 1;

        const btn = document.createElement('button');
        btn.className = 'btn-eliminar';
        btn.textContent = '✕';
        btn.onclick = (e) => {
            e.stopPropagation();
            state.fotos.splice(idx, 1);
            document.getElementById('contador-fotos').textContent = `${state.fotos.length} fotos`;
            if (state.fotos.length === 0) {
                document.getElementById('btn-galeria').style.display = 'none';
                mostrarPantalla('interfazCaptura');
            } else {
                mostrarGaleria();
            }
        };

        div.appendChild(img);
        div.appendChild(num);
        div.appendChild(btn);
        container.appendChild(div);
    });

    mostrarPantalla('galeriaFotos');
}

function volverAlMenu() {
    stopDetection();
    if (state.stream) {
        state.stream.getTracks().forEach(track => track.stop());
        state.stream = null;
    }
    state.fotos = [];
    document.getElementById('contador-fotos').textContent = '0 fotos';
    document.getElementById('btn-galeria').style.display = 'none';
    mostrarPantalla('formularioIngreso');
}

function volverACapturar() {
    mostrarPantalla('interfazCaptura');
}

async function generarPDF() {
    if (state.fotos.length === 0) {
        mostrarError('No hay fotos capturadas');
        return;
    }

    mostrarPantalla('progresoCarga');

    try {
        const element = document.createElement('div');
        element.style.width = '210mm';
        element.style.padding = '0';
        element.style.backgroundColor = 'white';

        state.fotos.forEach((foto, i) => {
            if (i > 0) {
                const pb = document.createElement('div');
                pb.style.pageBreakAfter = 'always';
                element.appendChild(pb);
            }

            const img = document.createElement('img');
            img.src = foto.toDataURL('image/jpeg', 0.9);
            img.style.width = '100%';
            img.style.height = 'auto';
            img.style.display = 'block';
            element.appendChild(img);
        });

        document.getElementById('textoProgreso').textContent = 'Generando PDF...';
        document.getElementById('progressBar').style.width = '50%';

        const pdf = await html2pdf().set({
            margin: [0, 0, 0, 0],
            filename: `${state.idPieza}.pdf`,
            image: { type: 'jpeg', quality: 0.95 },
            html2canvas: { scale: 2, useCORS: true },
            jsPDF: { format: 'a4', orientation: 'portrait' }
        }).from(element).toPdf().output('blob');

        document.getElementById('textoProgreso').textContent = 'Subiendo...';
        document.getElementById('progressBar').style.width = '75%';

        await subirPDF(pdf);

    } catch (error) {
        mostrarError('Error PDF: ' + error.message);
    }
}

async function subirPDF(pdfBlob) {
    const formData = new FormData();
    formData.append('id_pieza', state.idPieza);
    formData.append('pdf_file', pdfBlob, `${state.idPieza}.pdf`);

    try {
        const res = await fetch('upload_doc.php', {
            method: 'POST',
            body: formData
        });

        const data = await res.json();

        if (data.status === 'error') {
            mostrarError(data.message);
            return;
        }

        document.getElementById('progressBar').style.width = '100%';
        document.getElementById('textoProgreso').textContent = 'Completado';

        const verText = data.version > 1 ? ` (v${data.version})` : '';
        const texto = `${data.file}${verText}\nPieza: ${state.idPieza}\nCliente: ${state.piezaData.cliente}`;

        document.getElementById('textoExito').textContent = texto;

        setTimeout(() => mostrarPantalla('exitoSubida'), 800);

    } catch (error) {
        mostrarError('Error subida: ' + error.message);
    }
}

function reiniciar() {
    state = {
        idPieza: null,
        piezaData: null,
        stream: null,
        video: null,
        fotos: [],
        fotoTemp: null,
        usingFrontCamera: false
    };

    document.getElementById('idPieza').value = '';
    document.getElementById('mensajeValidacion').textContent = '';
    document.getElementById('contador-fotos').textContent = '0 fotos';
    document.getElementById('btn-galeria').style.display = 'none';
    mostrarPantalla('formularioIngreso');
}

function mostrarError(msg) {
    document.getElementById('textoError').textContent = msg;
    mostrarPantalla('error');
}

function mejorarYReducir(canvas) {
    const ctx = canvas.getContext('2d');
    const imgData = ctx.getImageData(0, 0, canvas.width, canvas.height);
    const data = imgData.data;

    for (let i = 0; i < data.length; i += 4) {
        data[i] = Math.min(255, Math.max(0, (data[i] - 128) * 1.4 + 128 + 20));
        data[i + 1] = Math.min(255, Math.max(0, (data[i + 1] - 128) * 1.4 + 128 + 20));
        data[i + 2] = Math.min(255, Math.max(0, (data[i + 2] - 128) * 1.4 + 128 + 20));
    }

    ctx.putImageData(imgData, 0, 0);

    const MAX_DIM = 2000;
    const scale = Math.min(1, MAX_DIM / Math.max(canvas.width, canvas.height));

    if (scale < 1) {
        const newW = canvas.width * scale;
        const newH = canvas.height * scale;
        const temp = document.createElement('canvas');
        temp.width = newW;
        temp.height = newH;
        temp.getContext('2d').drawImage(canvas, 0, 0, newW, newH);

        ctx.clearRect(0, 0, canvas.width, canvas.height);
        canvas.width = newW;
        canvas.height = newH;
        ctx.drawImage(temp, 0, 0);
    }

    const grayImgData = ctx.getImageData(0, 0, canvas.width, canvas.height);
    const grayData = grayImgData.data;

    for (let i = 0; i < grayData.length; i += 4) {
        const gray = grayData[i] * 0.299 + grayData[i + 1] * 0.587 + grayData[i + 2] * 0.114;
        grayData[i] = grayData[i + 1] = grayData[i + 2] = gray;
    }

    ctx.putImageData(grayImgData, 0, 0);
}

function reproducirSonido() {
    try {
        const ctx = new (window.AudioContext || window.webkitAudioContext)();
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.frequency.value = 800;
        gain.gain.setValueAtTime(0.3, ctx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.1);
        osc.start(ctx.currentTime);
        osc.stop(ctx.currentTime + 0.1);
    } catch (e) {}
}

document.addEventListener('DOMContentLoaded', () => {
    const input = document.getElementById('idPieza');
    if (input) {
        input.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') validarPieza();
        });
    }
});
