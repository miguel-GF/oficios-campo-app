# Infraestructura de Fase 1

La aplicación es **local-first**: todas las operaciones comerciales se escriben primero en SQLite y funcionan sin credenciales. Supabase se usa únicamente para identidad, respaldo/sincronización y archivos remotos.

## Preparación de Supabase

1. Crear un proyecto y ejecutar `supabase/migrations/202608030001_phase1.sql` con Supabase CLI.
2. Desplegar las funciones con `supabase functions deploy bootstrap`, `sync`, `pull`, `evidence-upload`, `interpret`, `account` y `entitlement`. Todas validan JWT. Nunca poner `service_role` en Expo.
3. Copiar `.env.example` a `.env.local` y completar URL y clave pública anon.
4. Habilitar Email OTP en Auth y definir sus plantillas. La app solicita/verifica el código mediante la API de Supabase y conserva refresh/access tokens con `expo-secure-store`. OTP por SMS queda como alternativa futura con costo independiente.
5. Las evidencias deben copiarse al almacenamiento permanente del dispositivo antes de encolarse y subirse a `evidence/<business_id>/<order_id>/` desde la función.
6. Configurar secretos del asistente únicamente en Supabase: `supabase secrets set OPENAI_API_KEY=... OPENAI_MODEL=...`. La app envía texto dictado, recibe JSON estricto, muestra preview y solo escribe tras confirmación.

## Contrato pendiente de credenciales

`POST /functions/v1/sync` recibe `{ idempotencyKey, table, entityId, operation, payload }`, valida tablas, asigna el negocio autenticado y registra un recibo idempotente. Después del push, `/pull` devuelve el snapshot del negocio. `evidence-upload` emite URLs firmadas de vida corta; los binarios nunca atraviesan la base de datos.

## Publicación

Antes de publicar se deben reemplazar nombre legal, iconos, splash, URLs de privacidad/soporte y confirmar los identificadores `mx.jale.app`. Generar los binarios firmados con EAS Build, completar los formularios de seguridad de datos de ambas tiendas y ejecutar pruebas internas en dispositivos reales.
