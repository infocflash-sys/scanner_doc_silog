# 📱 Doc SILOG

Digitalización de documentación para **SILOG ERP**: una app Android escanea los documentos de una
pieza con la cámara del teléfono, genera un PDF y lo sube al servidor, donde queda asignado a la
pieza.

| Parte | Carpeta | Descripción |
|---|---|---|
| App Android | [`APP/`](APP/README.md) | Cámara en vivo con detección y recorte automático de la hoja, filtros de legibilidad, PDF multipágina y envío sin conexión |
| API del servidor | raíz (`api/`, `upload_doc.php`, `config.php`) | Endpoints PHP que validan la pieza y reciben el PDF |

## 🔄 Flujo

1. El usuario ingresa el **ID de la pieza** en la app.
2. La app consulta `api/validar_pieza.php`: si la pieza no existe se informa; si **ya tiene un PDF**
   asignado, se explica la situación y no se permite subir otro.
3. Escanea las páginas (cámara en vivo o galería), las revisa y genera un **PDF A4**.
4. `upload_doc.php` valida el archivo, lo guarda como `<id>.pdf` y registra el nombre en
   `flash_piezas.docum_file`.

## 🗂️ Estructura

```
Doc_Silog/
├── APP/                       # App Android (Flutter)
├── api/
│   └── validar_pieza.php      # Valida la pieza e informa si ya tiene PDF
├── upload_doc.php             # Recibe y guarda el PDF
├── config.php                 # Utilidades y lectura de configuración
├── config.local.example.php   # Plantilla de credenciales (copiar a config.local.php)
└── .htaccess                  # Bloquea el acceso web a los archivos de configuración
```

## 🚀 Despliegue del servidor

Requisitos: PHP 7.4+, MySQL 5.7+ y HTTPS.

1. Copia al servidor (FTP) `api/`, `upload_doc.php`, `config.php`, `.htaccess` y
   `config.local.example.php`.
2. En el servidor, copia `config.local.example.php` como **`config.local.php`** y completa los datos
   de la base de datos y la ruta de almacenamiento (`target_dir`). Este archivo no se versiona.
3. Comprueba que PHP pueda escribir en `target_dir`.
4. En la app, la URL del servidor se define en `APP/lib/core/config.dart`.

> **Versión web anterior:** este repositorio ya no incluye la página web de escaneo
> (`scanner.php`, `index.php`, `css/`, `js/`). Si esos archivos siguen en el servidor, elimínalos:
> quedarían publicados sin mantenimiento.

## 🔌 API

### `GET /api/validar_pieza.php?id_pieza=<id>`

```json
{
  "status": "success",
  "data": {
    "id": "123456",
    "cliente": "Cliente XYZ",
    "fecha_creacion": "2026-07-08 06:50:04",
    "tiene_pdf": false,
    "docum_file": null
  }
}
```

Errores: `404` con `code: no_encontrada` si la pieza no existe; `400` si el ID es inválido.

### `POST /upload_doc.php`

Campos `multipart/form-data`: `id_pieza` y `pdf_file`.

```json
{ "status": "success", "file": "123456.pdf", "version": 1, "id_pieza": "123456" }
```

| Código | Significado |
|---|---|
| `409` + `code: ya_tiene_pdf` | La pieza ya tiene un PDF asignado: **nunca se sobrescribe**. Para reemplazarlo, un administrador debe eliminarlo primero desde el ERP |
| `413` | El PDF supera el tamaño máximo (25 MB por defecto) |
| `415` | El archivo no es un PDF válido (se revisa la firma `%PDF-`, no solo la extensión) |

## 🔒 Seguridad

- Las credenciales **no están en el código**: se leen de `config.local.php` o de variables de entorno
  (`SILOG_DB_HOST`, `SILOG_DB_NAME`, `SILOG_DB_USER`, `SILOG_DB_PASS`, `SILOG_TARGET_DIR`).
- El guardado es atómico y no sobrescribe; la BD solo se actualiza si `docum_file` sigue vacío.
- El ID de pieza se restringe a `[A-Za-z0-9_-]` (también forma el nombre del archivo).

**Pendiente:** los endpoints todavía **no exigen autenticación**. Antes de exponerlos de forma
amplia conviene añadir un token o login.

> ⚠️ Una versión anterior del historial de git contiene las credenciales de la base de datos.
> Cambia esa contraseña en el servidor.

## 📝 Licencia

Desarrollado para SILOG ERP - Intranet Flash.
