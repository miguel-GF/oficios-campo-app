# Jale

Aplicación Android offline-first para que trabajadores de oficio creen cotizaciones, registren abonos y compartan cotizaciones o recibos no fiscales en PDF.

## Alcance del MVP

- Alta local del negocio y clientes.
- Cotizaciones con conceptos, cantidades, precios, notas y estados.
- Historial, búsqueda, pagos parciales, anulaciones y saldo pendiente.
- PDF compartible mediante el menú nativo, incluido WhatsApp.
- SQLite como fuente de verdad, respaldo automático de Android y respaldo manual cifrado.
- Plan Gratis con 3 documentos finalizados por mes; Jale Pro con documentos ilimitados, logo y color institucional.

No requiere cuenta, Supabase ni variables de entorno. La conexión solo se necesita para comprar o validar Jale Pro en Google Play.

## Desarrollo

Requiere Node.js 22.13 o posterior y un development build; Expo Go no incluye el módulo de compras.

```bash
npm install
npm run android
npm run typecheck
npm test
```

`npm run prebuild` regenera los proyectos nativos. `npm run build:preview` crea un APK de prueba con EAS y `npm run build:production` crea el AAB de tienda.

## Configuración de Google Play

Crear la suscripción `jale_pro` con planes base `monthly` y `yearly`. Los precios visibles de respaldo son $89 MXN/mes y $799 MXN/año; Google Play conserva la autoridad sobre precio, renovación y estado. Las compras deben probarse desde una pista de Play Console.

Consulta [la especificación del MVP](docs/spec-mvp-fase-1.md), [la infraestructura](docs/infraestructura-fase-1.md) y [la política de privacidad](docs/politica-de-privacidad.md) antes de publicar.

El camino de beta, voz y eventual migración de cuentas está en [el plan de evolución](docs/plan-evolucion.md).
