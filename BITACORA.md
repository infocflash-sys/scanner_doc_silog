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

---

## 12. Despliegue al servidor (2026-10-28, tarde)

- La subida de un PDF de 20 MB fallaba con «Error al guardar archivo. Verifica permisos o ruta.»: ese texto era
  del `upload_doc.php` **antiguo** que seguía en `files.intranetflash.com` (los PHP endurecidos nunca se habían
  desplegado; por eso tampoco funcionaba el aviso «la pieza ya tiene PDF»: el `validar_pieza.php` antiguo no
  devolvía `docum_file`/`tiene_pdf`).
- Se subieron por FTP (puerto 21; el 22 rechaza la autenticación) a la carpeta `files.intranetflash.com/`:
  `config.php`, `config.local.php` (credenciales; bloqueado por `.htaccess`), `.user.ini`
  (`upload_max_filesize=50M`, `post_max_size=55M`), `.htaccess` (se añadió el bloqueo de config), `upload_doc.php`
  y `api/validar_pieza.php`. Copia de los originales en `backup_servidor/` (ignorada por git).
- `archivoscompartidos.intranetflash.com/upload_doc.php` es **otra aplicación** (recibe firmas JPG): no se tocó.
- Verificado sin escribir datos (ID inexistente): validar → 404 `no_encontrada`; subida de 3 y 20 MB aceptada por PHP.
- App: tope por página 700 KB y 20 MB por PDF (`maxPdfBytes`); las páginas más pesadas se reducen automáticamente.
- Pendiente: probar en campo la subida larga y el rechazo de una segunda subida a la misma pieza.

## 13. Login (2026-10-28)

- Credenciales del ERP: tabla `users` (solo lectura), `username` único, `active = 1`. Clave estilo Ion Auth sin salt
  almacenado: `hash = salt(10) + substr(sha1(salt + clave), 0, 30)` (`verify_password` en `config.php`).
- `POST /api/login.php` → token firmado (HMAC-SHA256, secreto `auth_secret` en `config.local.php`), 24 h, sin tablas
  nuevas. La app lo envía en la cabecera `X-Silog-Token`; `validar_pieza.php` y `upload_doc.php` lo exigen
  (401 `sesion`) y reconsultan `active` en cada petición.
- Bloqueo: 3 fallos por usuario → 5 min (429 `bloqueado`, `retry_after`); además 15 fallos por IP. Estado en archivos del
  temporal del servidor (`silog_auth/`).
- El PDF se guarda como `<id_pieza>-<id_usuario>.pdf` (queda en `docum_file`).
- App: `AuthService` (sesión en `data/sesion.json`, solo token), `LoginScreen`, `AuthGate`; botón «Cerrar sesión» en
  Inicio; si la sesión vence durante un envío el PDF queda en pendientes y se reenvía tras ingresar.
- Las versiones anteriores de la app dejan de funcionar (el servidor exige sesión): instalar el APK nuevo en todos los equipos.

## 14. Flujo lineal, límite de 20 MB y tiempos (2026-10-28)

- **Sin cola de pendientes** (decisión del usuario): se sube y recién después se toma otro documento. Se eliminó la cola
  de `StorageService` y su tarjeta en Inicio. Si falla por red, la pantalla de subida ofrece «Reintentar» (el PDF se conserva
  mientras se siga en ella); si vence la sesión, «Iniciar sesión» (login modal) y el mismo PDF se reenvía solo.
- **Límite de subida: 20 MB por documento** (`AppConfig.maxPdfMb`). Aviso en la galería y en la pantalla de subida, con el
  peso real del PDF antes de subir. Si se pasa: primero reducción normal por página (700 KB c/u máx., piso 1000 px/q58);
  luego reducción forzada (hasta 600 px/q35); si aun así supera, no se sube y se pide quitar páginas (`PdfTooLargeException`).
- **Timeouts:** app 10 min (envío y recepción); servidor `.user.ini` `max_execution_time` y `max_input_time` = 600.
- Dato de campo: 11 páginas ≈ 4,8 MB (~440 KB/página).

## 15. Control de versiones remoto (2026-10-28)

- **Tabla nueva `silog_app_config`** (clave/valor) en `intran23_mis_envios`; no se tocó ninguna tabla existente.
  Valores iniciales: `app_activa=1`, `build_minimo=2`, `mensaje`, `url_descarga` (vacío).
- La app envía `X-Silog-Build` (constante `AppConfig.build`, = al número tras «+» de `pubspec.yaml`: hoy **1.1.0+2**).
  El servidor (`check_app_version()` en login y `require_auth`) responde **426 `version`** si `app_activa=0` o el build < `build_minimo`.
  `GET /api/estado.php` (público) informa si la versión está permitida; la app lo consulta al abrir y al volver a primer plano.
- Pantalla de bloqueo (`BlockedScreen`) cubre toda la app, con el mensaje y, si hay `url_descarga`, botón para copiar el enlace.
- **Cómo operar (SQL):**
  - Dar de baja versiones viejas: `UPDATE silog_app_config SET valor='3' WHERE clave='build_minimo';`
  - Parada de emergencia: `UPDATE silog_app_config SET valor='0' WHERE clave='app_activa';` (volver a `'1'` para reactivar).
  - Mensaje / enlace: filas `mensaje` y `url_descarga`.
  - Al publicar una versión nueva: subir `version:` en pubspec y `AppConfig.build` a la vez; luego subir `build_minimo`.
- Si la tabla no responde, el servidor NO bloquea (se registra el error en el log).
- Galería: aro giratorio con una barrita por página a procesar (`SegmentRing`), compacto en la parte superior.

## 16. Galería con lotes grandes (2026-10-28, misma versión 1.1.0+2)

- Reporte de campo: con lotes de 10-20 páginas no se veía el aro de progreso y el recorte de la hoja salía mal.
  No se reprodujo en pruebas (con 4-8 páginas sintéticas el aro y la detección funcionaban), pero la causa probable en equipos
  reales era la **saturación**: se lanzaban todas las páginas a la vez (10-20 procesos decodificando fotos de varios MP).
- Cambios en `review_screen.dart`: las páginas se procesan **de a 2** (`_maxParallel`), con **un reintento** si una falla;
  el aro aparece desde el primer fotograma y avanza de a una página; un **único aviso** por lote en lugar de uno por página.
- No se tocó `pubspec.yaml` ni `AppConfig.build` (sigue 1.1.0+2): la tabla `silog_app_config` no cambia.

## 17. Sesión persistente y detección de bordes más robusta (misma versión 1.1.0+2)

- **Sesión**: el token sigue durando 24 h (servidor) y ahora se cierra además tras **8 h sin usar la app**
  (ventana deslizante: cada petición y cada vuelta a la app la renuevan). `AuthService.alVolver()` se llama al
  reanudar la app y recupera la sesión del disco si no está en memoria. Se recuerda el **último usuario**
  (`data/usuario.txt`, solo el nombre) para precargarlo en el login. La clave nunca se guarda.
- **Detección** (`doc_vision.dart`): el método original (Otsu) se mantiene como base; se añaden candidatos con
  umbral más bajo (hojas con sombra) y apertura morfológica (hoja pegada a manchas claras). Solo reemplaza al
  original si el candidato es casi un cuadrilátero perfecto (fill ≥ 0,94) y abarca entre 1,08x y 1,5x más;
  en 18 casos sintéticos nunca empeoró y mejoró los de sombra media. Con fondo claro + sombra fuerte el umbral
  global sigue fallando: ahí se usa ✂ para ajustar a mano.

## 18. Captura manual con esquinas a mano (misma versión 1.1.0+2)

Flujo estilo CamScanner: **disparador manual** (se quitó el disparo automático y el análisis en vivo; la cámara
enfoca antes de disparar y el toque enfoca un punto) → pantalla **«Ubica las esquinas»** (`CropScreen`, 4 puntos
grandes que se mueven con el dedo, con lupa; propone las esquinas detectadas pero manda lo que el usuario deje) →
**«Confirmar y procesar»**: recorta/endereza con esos límites, aplica el filtro Documento y reduce tamaño, con aro de
progreso → la página entra **ya terminada** a la galería (`ReviewScreen.initialPages`), que ya no tiene cola de
procesamiento (solo reprocesa al cambiar filtro, girar o re-recortar). Galería del teléfono: mismo paso, foto por foto.
`capture_flow.procesarFoto()` concentra el flujo. Se retoma con «Volver a tomar».
