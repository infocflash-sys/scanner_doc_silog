<?php
/**
 * Copia este archivo como config.local.php en el servidor y completa los valores.
 * config.local.php está en .gitignore: nunca se sube al repositorio.
 * Recomendado: bloquear su acceso web (ver .htaccess).
 */
return [
    'db_host'    => 'localhost',
    'db_name'    => 'intran23_mis_envios',
    'db_user'    => 'CAMBIAR',
    'db_pass'    => 'CAMBIAR',
    'target_dir' => '/home/intran23/archivoscompartidos.intranetflash.com/public/archivos/documentacion/',
    // Secreto para firmar sesiones: largo y aleatorio (php -r "echo bin2hex(random_bytes(32));")
    'auth_secret' => 'CAMBIAR',
    'max_bytes'  => 25 * 1024 * 1024,
];
