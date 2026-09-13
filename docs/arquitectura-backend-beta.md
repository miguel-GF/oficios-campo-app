# Arquitectura del backend

## Componentes

- Neon Auth autentica en un portal web controlado por Jale.
- FastAPI intercambia una clave de un solo uso protegida con PKCE por un access token opaco de 15 minutos y refresh rotatorio de 30 días.
- Neon Postgres contiene cuentas, códigos de intercambio, sesiones, derechos, cuotas, instalaciones, uso IA y eventos Stripe.
- Cloudflare Worker añade X-Origin-Verify, limita IA por instalación/IP y oculta Cloud Run.
- El adapter Oficios fija la app y función; el cliente no puede elegir proveedor, prompt ni modelo.
- Stripe Checkout y Billing Portal se crean en FastAPI. El webhook firmado es la única vía que cambia el derecho Pro.

## Idempotencia

El cliente guarda localmente cuerpo y request_id hasta tener una respuesta final. FastAPI reserva cuota dentro de una transacción. Un registro pendiente reciente responde REQUEST_IN_PROGRESS; uno pendiente por más de dos minutos se recupera con la misma llave. El gateway devuelve durante 24 horas una salida ya terminada con cached=true, sin volver a llamar al proveedor.

## Autenticación web

El portal recibe code_challenge, redirect_uri y state, autentica con Neon Auth y llama a POST /internal/auth/codes usando X-Auth-Bridge. Debe redirigir exactamente a:

    jale://auth/callback?code=<one-time-code>&state=<original-state>

El endpoint interno nunca se expone en el Worker público. Sólo acepta identidades obtenidas de la sesión de Neon Auth. No se envían contraseñas ni tokens Neon al APK.

## Producción

Aplicar backend/migrations/001_neon.sql, configurar todas las variables de backend/.env.example, desplegar el gateway real y exigir integridad. /health devuelve 503 hasta que la configuración y Postgres estén listos.
