# Jale

App Android offline-first para trabajadores de oficio. Crea cotizaciones, clientes, abonos y recibos no fiscales; genera PDF y controla saldos aun sin señal.

## Arquitectura

- Flutter 3.44.8 y SQLite v7 mantienen en el teléfono el negocio, clientes, catálogo, cotizaciones y pagos.
- El dictado se transcribe en el dispositivo. FastAPI reserva la cuota y llama al adapter Oficios del gateway central.
- Neon Auth vive en un portal web. La app usa navegador, PKCE y sesiones móviles opacas de 15 minutos con refresh rotatorio de 30 días.
- Neon Postgres conserva identidad, sesiones, derecho Pro, cuota y auditoría técnica. No sincroniza los datos de trabajo.
- Stripe Checkout vende Jale Pro mensual o anual en la distribución directa. Sólo un webhook firmado activa o revoca Pro.
- Play Integrity valida paquete, certificado, versión, dispositivo y hash de la solicitud.
- El gateway central guarda durante 24 horas la salida de IA asociada al request_id para recuperar reintentos sin otra llamada ni otro consumo.

## Modelo comercial

- Cotizaciones manuales ilimitadas, con o sin cuenta.
- Invitado: un uso de IA durante la vida de la instalación.
- Cuenta gratuita: dos usos de IA por mes.
- Pro: IA sin límite visible, con barrera técnica de 500 usos mensuales para revisión de abuso.
- No hay prueba Pro de 15 días.
- Stripe sólo cobra la suscripción. Los abonos que el trabajador registra de sus clientes son datos locales; Jale no procesa esos cobros.

## Desarrollo

    fvm flutter pub get
    fvm flutter analyze
    fvm flutter test
    backend\.venv\Scripts\python.exe -m pytest -q backend

Build directo para Uptodown o descarga propia:

    fvm flutter build apk --release --flavor direct --dart-define=JALE_DISTRIBUTION=direct --dart-define=JALE_API_URL=https://api.jale.mx --dart-define=JALE_AUTH_PORTAL_URL=https://auth.jale.mx/mobile --dart-define=PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=123456789

Build de Google Play, sólo para consumir un derecho Pro ya activo:

    fvm flutter build appbundle --release --flavor play --dart-define=JALE_DISTRIBUTION=play --dart-define=JALE_API_URL=https://api.jale.mx --dart-define=JALE_AUTH_PORTAL_URL=https://auth.jale.mx/mobile --dart-define=PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=123456789

La variante Play usa mx.jale.app.play y no presenta botones ni enlaces de compra de Stripe. La directa usa mx.jale.app. Para activar servicios reales faltan las credenciales descritas en la guía de lanzamiento. El código, migraciones, mocks y pruebas funcionan sin ellas.
