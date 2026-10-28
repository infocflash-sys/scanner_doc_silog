# Bitácora — Doc SILOG

Registro vivo del proyecto: qué es, cómo está construido, qué se hizo, qué falló y qué falta.
**Actualizar este archivo al cerrar cada sesión de trabajo.**

- **Repositorio:** https://github.com/infocflash-sys/scanner_doc_silog (rama `main`)
- **Última actualización:** 2026-10-28

---

## 1. Qué es

Sistema para digitalizar la documentación de una **pieza** del ERP SILOG (Intranet Flash):
una app Android escanea los documentos con la cámara, genera un PDF y lo sube al servidor,
donde queda asignado a la pieza (`flash_piezas.docum_file`).

Partes:

| Parte | Ubicación | Tecnología |
|---|---|---|
| App Android | `APP/` | Flutter 3.47 / Dart 3.13 |
| API del servidor | `api/`, `upload_doc.php`, `config.php` | PHP + MySQL |

Servidor de producción: `https://files.intranetflash.com` (la URL está en `APP/lib/core/config.dart`).
Base de datos: `intran23_mis_envios` (tablas `flash_piezas`, `flash_comprobantes_ingresos`, `flash_clientes`).

---

## 2. Estado actual

| Elemento | Estado |
|---|---|
| App con cámara en vivo y recorte automático | **Funciona** (probada en campo por el usuario con la versión v5) |
| Validación de pieza contra el ERP | **Funciona** (probada en campo) |
| Aviso cuando la pieza ya tiene PDF | Implementado (app + servidor 409). Verificación en campo pendiente |
| Subida del PDF y registro en BD | Implementada; **el usuario la está verificando** |
| Cola de envío sin conexión | Implementada, **sin probar** |
| Autenticación de los endpoints | **No existe** (decisión: se deja para después) |
| Firma de release | **Pendiente** (el APK usa la clave de depuración) |
| Pruebas automáticas | 5 pruebas del motor de visión (`APP/test/`), pasan |

---

## 3. Decisiones técnicas y por qué

| Decisión | Motivo |
|---|---|
| **Flutter** (no Capacitor/web) | Control de la cámara y rendimiento nativo; ya estaba instalado |
| **Procesamiento propio en Dart puro** (no OpenCV) | Sin dependencias nativas pesadas ni de pago; estable de compilar; se probó con imágenes sintéticas |
| **`camerawesome`** para la cámara | Permite analizar en vivo a baja resolución (~480 px) y tomar la foto final a resolución completa. El plugin oficial `camera` usa la misma resolución para ambas, obligando a elegir entre fluidez y calidad |
| **Se descartó Google ML Kit Document Scanner** | En el teléfono de pruebas fallaba al iniciar con un error vacío (excepción sin mensaje dentro del plugin) y no se pudo depurar sin acceso al equipo |
| **Endpoints sin login por ahora** | Decisión explícita del usuario ("por ahora déjalo sin login") |
| **Una pieza, un PDF; nunca se sobrescribe** | Requisito del usuario: si la pieza ya tiene PDF, mensaje informativo y no se sube otro |
| **Credenciales fuera del código** | `config.local.php` (no versionado) o variables de entorno |
| **Se retiró la versión web** | La app la reemplaza; además publicaba una subida sin autenticación |

---

## 4. Cómo funciona la app

**Flujo:** ID de pieza (teclado numérico) → validar → pantalla de la pieza → cámara en vivo →
revisión (filtros, giro, recorte, reordenar) → PDF A4 → subida → resultado.

**Procesamiento de imagen** (`APP/lib/services/doc_vision.dart`, corre en *isolates*):
1. *Detección de la hoja:* umbral de Otsu → componente clara central → esquinas extremas en las
   diagonales; se valida convexidad, área (8–98 %) y que la región llene el cuadrilátero.
2. *Perspectiva:* homografía cuadrado→cuadrilátero con interpolación bilineal (con 0,4 % de recorte
   interior para evitar bordes oscuros).
3. *Filtro «Documento»:* estima la iluminación del papel con filtro de máximo + desenfoque, divide
   la imagen entre ella (quita sombras), fija negro/blanco con curva suave y afila.
   *«Gris»*: normaliza y afila. *«Color+»*: mismo principio por canal.
4. *Cámara en vivo* (`live_scan_screen.dart`, `live_detector.dart`): analiza ~6 fps; si la hoja
   permanece estable ≈1 s dispara sola (modo Auto). El mapeo de coordenadas funciona con las 4
   rotaciones posibles del sensor (verificado con prueba automática).
5. La foto final siempre se **vuelve a detectar y recortar** con el motor completo, por lo que un
   error en el contorno que se dibuja en vivo no afecta el resultado.

**Otras piezas:** `pdf_service.dart` (PDF A4, una imagen por página), `api_service.dart` (Dio),
`storage_service.dart` (historial y cola offline), `temp_cleaner.dart` (borra temporales),
`splash_screen.dart` + `scan_intro_painter.dart` (animación de bienvenida), `tools/gen_icon.py` (ícono).

**Dependencias principales:** `camerawesome`, `image`, `pdf`, `dio`, `image_picker`, `path_provider`,
`flutter_animate`; dev: `flutter_launcher_icons`. Ninguna de pago.

---

## 5. Servidor (PHP)

| Endpoint | Función |
|---|---|
| `GET /api/validar_pieza.php?id_pieza=` | Devuelve cliente, fecha, `tiene_pdf` y `docum_file` |
| `POST /upload_doc.php` | Recibe `id_pieza` + `pdf_file`; valida y guarda `<id>.pdf` |

Reglas del servidor: ID solo `[A-Za-z0-9_-]`; el archivo debe empezar con `%PDF-`; tamaño máx. 25 MB;
guardado atómico (`fopen('x')`) sin sobrescribir; `UPDATE` solo si `docum_file` está vacío.
Códigos: `409 ya_tiene_pdf`, `404 no_encontrada`, `413`, `415`.

**Despliegue:** copiar los PHP por FTP y crear `config.local.php` en el servidor (plantilla en
`config.local.example.php`). El servidor del usuario ya lo tiene configurado (la validación de piezas
funciona desde la app).

---

## 6. Cronología (sesión del 2026-10-28)

1. **Análisis inicial.** La app web original (PHP + JS, detección con TensorFlow COCO-SSD) se revisó:
   credenciales de BD escritas en 4 archivos, `estructura_db.php` expuesto, subida sin validación real.
2. **Entorno Android.** Flutter ya estaba instalado. Se configuró el JDK 21 de Android Studio
   (`flutter config --jdk-dir`), se instaló `cmdline-tools` desde Google y se aceptaron las licencias del SDK.
3. **App v1.** Primera versión con el escáner de Google ML Kit, validación, revisión con filtros,
   PDF y subida. Backend endurecido y regla «una pieza, un PDF».
4. **Prueba en campo #1.** El escáner de Google falló (error vacío); la cámara normal funcionaba pero
   la foto no se recortaba ni se mejoraba.
5. **v2.** Reintentos + alternativa de cámara del sistema; teclado numérico; contraste de avisos.
6. **v3.** Pantalla de bienvenida animada e ícono propio (misma identidad visual).
7. **v4.** Motor propio: detección de la hoja, perspectiva, filtros nuevos y editor de recorte;
   se abandona ML Kit. Validado con una foto sintética (esquinas con error < 0,3 %).
8. **v5.** Cámara en vivo con detección en tiempo real y disparo automático (`camerawesome`).
   **Probada en campo: «funciona bien».**
9. **Repositorio.** Se usó el remoto ya vinculado y se subió en commits separados (seguridad / app /
   mejoras / retiro de la web).
10. **Mejoras.** Limpieza de temporales, 5 pruebas automáticas, README de la app, APK por arquitectura
    (arm64: 20 MB frente a 56,5 MB del universal).
11. **Retiro de la versión web** del repositorio.

Commits relevantes: `7f2c7d6` (seguridad del backend), `c31fdb4` (app), `6721d16` (temporales, pruebas,
docs), `5aab34b` (retiro de la web).

---

## 7. Problemas encontrados y cómo se resolvieron

| Problema | Causa | Solución |
|---|---|---|
| Build: *Daemon compilation failed… different roots* | El proyecto está en `D:` y la caché de pub en `C:`: la compilación incremental de Kotlin falla | `kotlin.incremental=false` en `APP/android/gradle.properties` |
| Build: *Timeout waiting to lock build logic queue* | Un daemon de Gradle lanzado por la extensión Java de VS Code tenía tomado `android/.gradle` | Terminar ese proceso y recompilar; si se repite, cerrar VS Code o desactivar esa extensión para la carpeta |
| `cmdline-tools` quedaba incompleto | `Expand-Archive` falla por el límite de longitud de ruta de Windows | Extraer con `tar` en una ruta corta (`C:\cx`) y mover a `sdk\cmdline-tools\latest` |
| `.gitignore` ignoraba `config.php` | Regla antigua cuando contenía secretos | Se quitó la regla (ahora no tiene secretos) |
| Commit mezclaba backend y app | Una cadena de `git add` se cortó por un archivo ya borrado | Se deshizo el commit local (sin subir) y se rehizo separado |
| Capturas del teléfono dentro de `APP/` | Archivos `WhatsApp Image*` (uno muestra un CV con datos personales) | Excluidos con `.gitignore`; **no se borraron** |
| Filtro «Documento» dejaba halo en bloques oscuros | La estimación de fondo con solo desenfoque confundía una foto con sombra | Filtro de máximo antes del desenfoque |

---

## 8. Verificado y no verificado

**Verificado:** análisis estático sin errores; 5 pruebas automáticas (detección, perspectiva, filtro con
sombra, consistencia con las 4 rotaciones del sensor); compilación del APK; uso en campo de la cámara en
vivo, el recorte y la validación de piezas.

**No verificado:** subida completa hasta la BD (en curso), cola sin conexión, rechazo 409 en campo,
comportamiento en teléfonos de 32 bits, ejecución en iOS (no se soporta).

---

## 9. Pendientes y decisiones abiertas

- [ ] **Cambiar la contraseña de la BD en el servidor.** Está en el historial publicado de git
      (commits anteriores a `7f2c7d6`). Reescribir el historial no la protege.
- [ ] **Eliminar del servidor** los archivos de la versión web (`scanner.php`, `index.php`, `css/`,
      `js/`): quitarlos del repo no los borra del servidor.
- [ ] **Proteger los endpoints** (token por dispositivo o login). Hoy cualquiera con la URL puede subir
      un PDF a una pieza sin documento.
- [ ] **Firma de release** con keystore propio (ver sección 10).
- [ ] Verificar en la BD: `docum_file = <id>.pdf`, archivo en la carpeta de documentación y rechazo de
      una segunda subida.
- [ ] Probar la cola sin conexión (modo avión → subir → reenviar).
- [ ] Mejoras posibles: sugerir «Color+» cuando el documento tiene imágenes grandes; control de tamaño
      del PDF; OCR opcional.

---

## 10. Firma de release (nota de referencia)

Android exige que todo APK esté firmado. Hoy se usa la **clave de depuración**, que se genera sola en
cada computador. Consecuencias: un APK compilado en otro equipo no puede actualizar al instalado (hay
que desinstalar), no sirve para Play Store y puede dar avisos de seguridad. Con un **keystore propio**
(un archivo `.jks` + contraseña) las actualizaciones se instalan encima y se puede publicar. El keystore
**no se versiona** y hay que respaldarlo: si se pierde, no se puede actualizar la app ya instalada.
Cambiar de clave exige desinstalar la versión actual una sola vez.

---

## 11. Retomar el trabajo

```bash
cd APP
flutter pub get
flutter test                                  # 5 pruebas del motor
flutter analyze
flutter build apk --release --split-per-abi   # APK por arquitectura
```

- **APKs:** `APP/build/app/outputs/flutter-apk/` (usar `app-arm64-v8a-release.apk`). Copias de versiones
  anteriores en `APP/build/app-v2…`, `v3…`, `v4…` (no versionadas).
- **Entorno de esta máquina:** SDK Android en `%LOCALAPPDATA%\Android\sdk`; JDK de Android Studio
  configurado con `flutter config --jdk-dir`.
- **Regenerar el ícono:** `python tools/gen_icon.py` y luego `dart run flutter_launcher_icons`.
- **Sin acceso al teléfono** no se puede depurar la cámara: pedir al usuario la captura o el texto del error.
