# Jale — app móvil de oficios de campo

Implementación inicial de la **Fase 1** como aplicación móvil multiplataforma con React Native y Expo. No es un sitio web: el mismo proyecto genera aplicaciones Android e iOS.

## Ejecutar

Requiere Node.js 20 o posterior y la app Expo Go en un teléfono.

```bash
npm install
npm start
```

Escanea el QR desde Expo Go. También puedes usar `npm run android` o `npm run ios` con un emulador instalado.

## Incluido en este incremento

- Navegación táctil nativa entre Hoy, Agenda, Orden y Clientes.
- Inicio de visita, edición de renglones y cálculo determinista del total.
- Selección de cobro y seguimiento, búsqueda de clientes y creación local de citas.
- Preview y confirmación para el dictado simulado, más comunicación clara del estado offline.
- Demo completa sin servidor durante la sesión: crear una cita, iniciar una visita, editar el cobro y cerrar la orden actualiza inmediatamente Hoy y el contador de cambios locales.

> **Estado real:** este incremento es un prototipo funcional del flujo, no la Fase 1 terminada. Citas, cierres y evidencia se conservan en SQLite y cada escritura queda en una cola local pendiente de sincronización.

## Siguientes incrementos de Fase 1

Audio/STT, procesamiento real de la cola con Supabase/PowerSync, autenticación OTP, PDF local y share sheet de WhatsApp siguen pendientes. La cámara y la base SQLite ya operan localmente; aún deben agregarse retención de archivos, reintentos y resolución de conflictos. La web administrativa y la página pública pertenecen a la Fase 2.

La especificación canónica está en [`docs/spec-mvp-fase-1.md`](docs/spec-mvp-fase-1.md) y el mockup HTML original se conserva en [`docs/mockups-mvp.html`](docs/mockups-mvp.html).
