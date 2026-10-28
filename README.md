# 📱 Doc_Silog - Escáner de Documentos

Sistema web profesional de captura y escaneo de documentos integrado con SILOG ERP.

## 🎯 Características

- ✅ Captura de múltiples fotografías desde cámara móvil/webcam
- ✅ Mejora automática de imagen (contraste, brillo, conversión B&N)
- ✅ Generación de PDF unificado desde múltiples fotos
- ✅ Subida automática con versionado (evita sobreescrituras)
- ✅ Integración con base de datos SILOG
- ✅ Diseño responsive (móvil, tablet, desktop)
- ✅ Interfaz limpia con identidad visual SILOG

## 🏗️ Estructura

```
Doc_Silog/
├── index.php              # Redirect a scanner.php
├── scanner.php            # Interfaz principal de escaneo
├── upload_doc.php         # Endpoint de subida de PDFs
├── api/
│   └── validar_pieza.php  # Validación de pieza en BD
├── css/
│   └── style.css          # Estilos responsive
├── js/
│   └── scanner.js         # Lógica de captura y galería
└── README.md
```

## 🚀 Instalación

### Requisitos
- PHP 7.4+
- MySQL 5.7+
- Acceso FTP al servidor
- Servidor con HTTPS

### Pasos

1. **Descarga los archivos**
```bash
git clone https://github.com/tu-usuario/Doc_Silog.git
cd Doc_Silog
```

2. **Configura la base de datos**
   - Crea `config.local.php` a partir de `config.local.example.php`

3. **Sube vía FTP**
```
/home/intran23/files.intranetflash.com/
├── index.php
├── scanner.php
├── upload_doc.php
├── api/ (carpeta)
├── css/ (carpeta)
└── js/ (carpeta)
```

4. **Accede a**
```
https://files.intranetflash.com/scanner.php
```

## 📋 Flujo de Uso

1. Usuario ingresa **ID de Pieza** desde ERP
2. Sistema valida pieza en BD
3. Selecciona **Cámara Móvil** o **Webcam**
4. Captura múltiples **fotos del documento**
5. Confirma cada captura (preview + mejora automática)
6. Gestiona galería (eliminar, reordenar)
7. Genera **PDF unificado**
8. Sube automáticamente con **versionado**
9. Actualiza BD con nombre de archivo

## 🔌 API Endpoints

### GET `/api/validar_pieza.php`
Valida existencia de pieza en BD

**Parámetros:**
- `id_pieza` (string): ID de la pieza

**Respuesta:**
```json
{
  "status": "success",
  "data": {
    "id": "123456",
    "cliente": "Cliente XYZ",
    "fecha_creacion": "2026-07-08"
  }
}
```

### POST `/upload_doc.php`
Sube PDF y actualiza BD

**Parámetros:**
- `id_pieza` (string): ID de la pieza
- `pdf_file` (file): Archivo PDF

**Respuesta:**
```json
{
  "status": "success",
  "file": "123456.pdf",
  "version": 1,
  "id_pieza": "123456"
}
```

## 📦 Una pieza, un PDF

Si la pieza ya tiene `docum_file`, `validar_pieza.php` lo informa (`tiene_pdf`) y
`upload_doc.php` responde **409** con `code: ya_tiene_pdf`; nunca se sobrescribe.
Para reemplazarlo, un administrador debe eliminarlo primero desde el ERP.

## ⚙️ Configuración

### Credenciales y almacenamiento
Las credenciales **no** van en el código. Copia `config.local.example.php` como
`config.local.php` en el servidor y completa los datos de BD y la ruta de almacenamiento
(`target_dir`). `config.local.php` está en `.gitignore` y bloqueado por `.htaccess`.

## 🎨 Personalización

### Colores (CSS)
En `css/style.css` (líneas 2-13):
```css
--primary: #2d7a3e;        /* Verde SILOG */
--primary-dark: #1f5629;
--warning: #ffc107;        /* Botón amarillo */
```

### Textos
En `scanner.php`, edita los `<h1>` y etiquetas de botones

## 🔒 Seguridad

⚠️ **NOTA IMPORTANTE:** Esta versión NO incluye autenticación. 

**Recomendaciones antes de producción:**
- [ ] Implementar sesiones de usuario
- [ ] Validar tipo MIME de archivos
- [ ] Sanitizar nombres de archivo
- [ ] Agregar rate limiting
- [ ] Encriptar conexión (HTTPS)
- [ ] Usar CSRF tokens
- [ ] Control de acceso a PDFs

## 🐛 Troubleshooting

### "Error cámara: Permission denied"
- Navegador no tiene permisos
- Verificar HTTPS activo
- Permitir acceso en navegador

### "Pieza no encontrada"
- ID incorrecto
- Pieza no existe en BD
- Verificar conexión a BD

### "Error al guardar archivo"
- Permisos insuficientes en carpeta
- Espacio en disco lleno
- Ruta incorrecta

## 📝 Licencia

Desarrollado para SILOG ERP - Intranet Flash

## 👨‍💻 Autor

Generado con Claude Code

---

**Última actualización:** Julio 2026
