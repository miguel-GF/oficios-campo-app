# Jale — app móvil local-first para servicios de campo

Aplicación Expo/React Native para gestionar clientes, citas, órdenes, evidencias, cobros, seguimiento y notas PDF aun sin conexión.

**Nombre de trabajo:** la especificación original nombró el producto **Jale** y ese es el nombre visible configurado actualmente. “Jale App” no es un nombre distinto; solo es una forma descriptiva de referirse a la aplicación. El nombre comercial definitivo debe validarse antes de reservar la ficha de las tiendas y puede cambiarse sin alterar el dominio funcional.

## Ejecutar

Requiere Node.js 20 o posterior y Expo Go o un development build.

```bash
npm install
cp .env.example .env.local # opcional; la app funciona localmente sin Supabase
npm start
```

## Núcleo local

- Clientes buscables y creación local.
- Citas genéricas asociadas a clientes e inicio/reanudación de visitas.
- Órdenes independientes con conceptos, cantidades, precios, notas, cobro y seguimiento.
- Cámara antes/después, persistencia SQLite y bandeja durable de sincronización.
- Cierre transaccional, pago/recordatorio y nota PDF compartible.
- Sincronizador preparado para una Edge Function de Supabase; sin variables opera explícitamente en modo local.
- Acceso por código de correo, sesión en almacenamiento seguro y onboarding autenticado de negocio cuando Supabase está configurado.
- Push/pull autenticado, subida de evidencias por URL firmada y asistente de agenda con preview/confirmación preparados para credenciales reales.
- Eliminación autenticada de cuenta, datos sincronizados y evidencias remotas.

## Antes de producción

La configuración de infraestructura está en [`docs/infraestructura-fase-1.md`](docs/infraestructura-fase-1.md). Se deben proporcionar credenciales públicas de Supabase, desplegar la Edge Function incluida, conectar la sesión autenticada, configurar el proveedor de voz, sustituir identidad visual y textos legales, y completar pruebas de tienda. Las claves privadas nunca pertenecen a variables `EXPO_PUBLIC_*`.

La especificación de producto está en [`docs/spec-mvp-fase-1.md`](docs/spec-mvp-fase-1.md).

Las decisiones aceptadas sobre la suscripción única de $149 MXN, la oferta de lanzamiento de $99 MXN y el control manual de pagos están en [`docs/adr/0001-modelo-comercial-y-control-de-cobros.md`](docs/adr/0001-modelo-comercial-y-control-de-cobros.md).

La plantilla legible de privacidad está en [`docs/politica-de-privacidad.md`](docs/politica-de-privacidad.md); antes de publicar exige completar responsable, contacto, URL y proveedores definitivos.
