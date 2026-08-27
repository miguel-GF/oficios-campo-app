# Infraestructura del lanzamiento offline

## Aplicación

El MVP usa Expo 57, React Native, TypeScript y SQLite. Los PDF se renderizan en el dispositivo y se comparten mediante Android. No existe API propia, base de datos remota ni secreto de servidor.

Android Auto Backup incluye únicamente la base SQLite y `files/branding/`. SecureStore queda fuera del respaldo automático. Además, la app exporta archivos `.jale-backup` cifrados con AES-256-GCM y una clave derivada de la contraseña; la contraseña nunca se almacena.

## Distribución y cobro

Usar EAS para APK de beta y AAB de producción. El proyecto fija NDK 28.2.13676358 para reproducir builds en máquinas con el Android SDK ya instalado. Play Console debe contener:

- aplicación `mx.jale.app`;
- suscripción `jale_pro`;
- planes base renovables `monthly` y `yearly`;
- pista de prueba con cuentas licenciadas para validar compra, restauración, cancelación y operación sin red.

No se deben probar compras con Expo Go. La verificación local es una concesión explícita para la primera versión sin servidor. Antes de incorporar IA, sincronización o compras consumibles, agregar identidad recuperable y validación de compras en backend.

## Lista previa a publicación

- Sustituir icono y arte de tienda definitivos.
- Completar datos del responsable y URL pública de privacidad.
- Ejecutar `npm run typecheck`, `npm test` y una compilación Android limpia.
- Probar creación, cierre forzado, PDF, compartir, cambio de mes, pagos parciales, anulaciones, respaldo/restauración y pérdida de red.
- Confirmar precios y textos de renovación en Play Console.
- Conservar un respaldo cifrado de prueba y verificarlo en otro dispositivo.
