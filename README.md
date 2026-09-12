# Jale

App Android offline-first para trabajadores de oficio: cotizaciones profesionales por voz o captura manual, clientes, abonos, recibos no fiscales, PDF y seguimiento del dinero por cobrar.

## Qué incluye el MVP

- Flutter + Dart y SQLite local como fuente de verdad del trabajo.
- Dictado en el dispositivo e interpretación estructurada con `gpt-5.6-luna`; el usuario siempre revisa antes de agregar conceptos.
- Catálogo personal que recuerda conceptos y últimos precios.
- Tablero semanal/mensual, búsqueda y filtros por estado de cobro.
- Cuenta opcional por código al correo con Supabase Auth.
- Suscripción `jale_pro` verificada en el backend con Google Play Billing.
- Respaldo manual cifrado con AES-256-GCM; el respaldo automatico de Android esta desactivado y el servidor no almacena clientes ni cotizaciones en el MVP.
- FastAPI + Postgres para cuentas, cuotas, derechos Pro y auditoría de pagos de suscripción.
- Cloudflare Worker como entrada pública y Play Integrity para solicitudes de producción.

## Cuotas

- Sin cuenta: 1 cotización con IA y 3 cotizaciones manuales durante el primer periodo.
- Al registrar correo: 2 créditos IA de bienvenida.
- Meses posteriores: 2 cotizaciones IA y 4 manuales por mes.
- Pro: IA sin límite visible, con barrera técnica de uso razonable para detectar abuso; las cotizaciones manuales no se limitan.
- Los intentos fallidos de IA y los recibos de pagos existentes no consumen cuota.

## Desarrollo

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Backend:

```bash
cd backend
python -m venv .venv
.venv/Scripts/pip install -r requirements.txt -r requirements-dev.txt
.venv/Scripts/python -m pytest
uvicorn app.main:app --reload
```

La integración remota se configura sin incluir secretos en el APK:

```bash
flutter run \
  --dart-define=JALE_API_URL=https://api.example.com \
  --dart-define=SUPABASE_URL=https://project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=123456789
```

Para publicar se necesita `android/key.properties` y un upload keystore privado (ambos ignorados por Git), configurar `jale_pro` con planes `monthly` y `yearly` en Play Console, aplicar la migración de Supabase y activar Play Integrity.

Consulta la [especificación del MVP](docs/spec-mvp-fase-1.md), la [guía de beta cerrada](docs/guia-beta-cerrada.md), la [arquitectura del backend](docs/arquitectura-backend-beta.md), el [plan de evolución](docs/plan-evolucion.md) y la [política de privacidad](docs/politica-de-privacidad.md).
