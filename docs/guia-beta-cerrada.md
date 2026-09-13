# Guía de lanzamiento

## Neon

1. Crear el proyecto Neon y habilitar Neon Auth.
2. Aplicar backend/migrations/001_neon.sql sobre la rama de producción.
3. Desplegar un portal HTTPS que use Neon Auth y cumpla el contrato de arquitectura-backend-beta.md.
4. Guardar DATABASE_URL y AUTH_BRIDGE_SECRET sólo en el backend/portal.

## Stripe

1. Crear un producto Jale Pro con un precio recurrente mensual y otro anual, sin trial.
2. Copiar sus IDs en STRIPE_MONTHLY_PRICE_ID y STRIPE_YEARLY_PRICE_ID.
3. Configurar el webhook HTTPS /v1/billing/stripe/webhook.
4. Suscribir customer.subscription.created, updated y deleted.
5. Guardar claves Stripe en Secret Manager. Nunca se incluyen en Flutter.

## IA central

En api-consumo-ia, aplicar migraciones D1, sustituir IDs de producción y cargar secretos con Wrangler:

    npm.cmd run check
    npm.cmd run build:production
    npx wrangler secret put OPENAI_API_KEY -c wrangler.production.jsonc
    npx wrangler secret put CF_AIG_TOKEN -c wrangler.production.jsonc
    npx wrangler secret put INTERNAL_HMAC_SECRET -c wrangler.production.jsonc
    npx wrangler secret put OFICIOS_INTERNAL_TOKEN -c consumer/oficios.production.wrangler.jsonc

OFICIOS_INTERNAL_TOKEN debe coincidir con AI_GATEWAY_TOKEN de FastAPI.

## FastAPI y Cloudflare

Crear backend/.env desde el ejemplo, desplegar el contenedor y configurar el Worker con ORIGIN_URL, ORIGIN_VERIFY_SECRET, AI_RATE_LIMITER y AI_IP_RATE_LIMITER. El webhook Stripe puede atravesar el Worker porque se valida con su firma propia.

## Integridad y firma

Registrar directa mx.jale.app y Play mx.jale.app.play con sus certificados y códigos de versión. La directa acepta UNRECOGNIZED_VERSION sólo si paquete, certificado, versión, dispositivo y hash son correctos. Play exige además PLAY_RECOGNIZED y LICENSED.

Crear android/key.properties y el keystore fuera de Git. Generar primero APK directo firmado para Uptodown/descarga propia. El AAB Play no muestra compra Stripe.

## Aceptación

Probar en dos teléfonos: 1 IA invitado, login Neon, 2 IA mensuales, manuales ilimitadas, timeout y reintento con igual ID, alta/cancelación Stripe por webhook, tres días offline Pro, PDF, sobrepago rechazado, cierre forzado, borrado total y respaldo de más de 100 clientes.
