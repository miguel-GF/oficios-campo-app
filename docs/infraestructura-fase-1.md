# Infraestructura del lanzamiento offline

## Aplicacion

Jale usa Flutter y Dart con SQLite local. Los PDF se renderizan en el dispositivo y se comparten mediante Android. La IA y la cuenta son opcionales: el APK nunca contiene la clave de OpenAI ni credenciales de Google Play.

La base `jale.db` vive en el directorio de documentos de la aplicacion. Los respaldos manuales usan archivos `.jale-backup` cifrados con AES-256-GCM y una clave derivada de la contrasena mediante PBKDF2-SHA256; la contrasena nunca se almacena.

## Distribucion y cobro

Usar los comandos de Flutter para generar APK de prueba y AAB de produccion. La aplicacion es `mx.jale.app`; Google Play debe contener la suscripcion `jale_pro` con planes renovables `monthly` y `yearly`.

Google Play Billing se verifica en FastAPI antes de activar Pro y queda ligado a la cuenta de Jale. Supabase conserva cuotas, derechos y auditoría mínima; clientes, cotizaciones y pagos del trabajador siguen en SQLite. Si Play no está disponible, se conserva como máximo tres días el último derecho verificado. Cloudflare Worker oculta el origen y añade el secreto de origen; Play Integrity se exige en producción.

## Lista previa a publicacion

- Sustituir icono y arte de tienda definitivos.
- Completar datos del responsable y URL publica de privacidad.
- Ejecutar `flutter analyze`, `flutter test` y una compilacion Android limpia.
- Probar creacion, cierre forzado, PDF, compartir, cambio de mes, pagos parciales, anulaciones, respaldo/restauracion y perdida de red.
- Confirmar precios y textos de renovacion en Play Console.
- Conservar un respaldo cifrado de prueba y verificarlo en otro dispositivo.
- Ejecutar migración SQL de Supabase y configurar secretos en Cloud Run; activar `REQUIRE_PLAY_INTEGRITY=true`.
- Probar desde el APK oficial la cuota 1 IA → correo + 2 IA → 3 manuales iniciales → 2 IA + 4 manuales en el siguiente periodo.
