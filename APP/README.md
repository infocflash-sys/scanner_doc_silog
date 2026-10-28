# Doc SILOG — App Android

Escáner de documentos para SILOG ERP. Se escanea la documentación de una **pieza** con la cámara
del teléfono, se genera un PDF y se sube al servidor, quedando asignado a la pieza en el ERP.

## Qué hace

1. Se ingresa el **ID de la pieza** (teclado numérico) y se valida contra el ERP.
   Si la pieza **ya tiene un PDF**, la app lo informa y no permite subir otro.
2. **Cámara en vivo**: detecta la hoja en tiempo real, la resalta y, cuando está firme, dispara
   sola (modo *Auto*; también hay modo *Manual*). Linterna y enfoque táctil. Se pueden tomar
   varias páginas seguidas. Opcionalmente se eligen fotos de la **galería**.
3. **Revisión** de cada página: filtros **Documento** (blanco y negro nítido, sin sombras),
   **Gris**, **Color+** y **Original**; giro, borrado, reordenar (mantener presionado y
   arrastrar), zoom y **editor de recorte** con 4 esquinas.
4. Se arma un **PDF A4** multipágina y se sube con barra de progreso. Sin conexión, queda
   guardado en el teléfono y se envía después desde el inicio.

## Cómo procesa la imagen

Todo en Dart puro (sin OpenCV ni servicios de pago), en *isolates* para no congelar la interfaz.
Código en `lib/services/doc_vision.dart`:

| Paso | Técnica |
|---|---|
| Detección de la hoja | Umbral de Otsu → componente clara central → esquinas extremas en las diagonales; valida convexidad y área |
| Perspectiva | Homografía cuadrado→cuadrilátero con interpolación bilineal |
| Filtro *Documento* | Estima la iluminación del papel (filtro de máximo + desenfoque), divide la imagen entre ella, fija negro/blanco y afila |
| Cámara en vivo | `camerawesome`: análisis a ~480 px en vivo y foto final a resolución completa |

## Estructura

```
lib/
├── core/            config (URL del servidor) y tema
├── models/          PiezaInfo, ScanPage, HistorialItem…
├── screens/         splash, home, pieza, live_scan, crop, review, upload
├── services/        api, doc_vision, image, live_detector, pdf, storage, capture_flow, temp_cleaner
└── widgets/         componentes y animación de bienvenida
tools/gen_icon.py    genera el ícono (Pillow)
test/                pruebas del motor de detección y filtros
```

## Compilar

Requisitos: Flutter estable, JDK 17+ (el de Android Studio sirve) y Android SDK con licencias aceptadas.

```bash
flutter pub get
flutter test                                # pruebas del motor de visión
flutter build apk --release                 # APK universal
flutter build apk --release --split-per-abi # APKs por arquitectura (más livianos)
```

El APK queda en `build/app/outputs/flutter-apk/`. En la mayoría de los teléfonos actuales
corresponde `app-arm64-v8a-release.apk`.

> Si Gradle falla con *"Timeout waiting to lock build logic queue"*, otro proceso (por ejemplo la
> extensión Java de VS Code) tiene tomado el directorio `android/.gradle`. Ciérralo y reintenta.

## Configuración

- **URL del servidor**: `lib/core/config.dart` (`AppConfig.baseUrl`).
- **Servidor**: los endpoints PHP de la raíz del repositorio (`api/validar_pieza.php`,
  `upload_doc.php`). Requieren un `config.local.php` en el servidor (ver
  `config.local.example.php`) con las credenciales de la BD y la ruta de almacenamiento.
- **Ícono**: `python tools/gen_icon.py` y luego `dart run flutter_launcher_icons`.

## Pendiente / limitaciones conocidas

- **Sin autenticación**: los endpoints no piden login ni token todavía.
- **Firma**: el APK de *release* se firma con la clave de depuración. Para distribuir o actualizar
  de forma estable hace falta un *keystore* propio.
- La detección falla si la hoja es tan clara como el fondo (papel blanco sobre mesa blanca);
  en ese caso se ajustan las esquinas a mano.
- En modo *Documento* las fotos grandes del papel quedan como bloque oscuro (es blanco y negro
  puro); usar *Color+* para conservarlas.
