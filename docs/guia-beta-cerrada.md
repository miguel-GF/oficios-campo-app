# Guía operativa de beta cerrada

Esta guía activa la IA real sin poner secretos en Android. Ejecutar los comandos desde la raíz del repositorio y guardar los valores sensibles en el gestor de secretos correspondiente.

## 1. Supabase

1. Crear un proyecto y activar Auth por correo con OTP.
2. En SQL Editor ejecutar, en orden, las migraciones de `supabase/migrations/`.
3. En la plantilla de correo mostrar el token con `{{ .Token }}`; Jale pide seis dígitos, no un enlace.
4. Copiar `SUPABASE_URL` y `SUPABASE_ANON_KEY` solamente para el build de Flutter. La clave de servicio de Supabase, si se usa, vive únicamente en backend.

## 2. Gateway de IA y backend local

Configurar `backend/.env` a partir de `.env.example`. En la beta el backend de Oficios llama al adapter central; `AI_GATEWAY_TOKEN` debe ser el mismo secreto que `OFICIOS_INTERNAL_TOKEN` del Worker de Oficios:

```text
AI_BACKEND=gateway
AI_GATEWAY_URL=https://oficios-ai-adapter.<subdominio>.workers.dev
AI_GATEWAY_TOKEN=...
AI_GATEWAY_TIMEOUT_SECONDS=25
OPENAI_MODEL=gpt-5.6-luna
DATABASE_URL=postgresql://...?sslmode=require
SUPABASE_URL=https://...supabase.co
SUPABASE_ANON_KEY=...
INSTALLATION_PEPPER=un-secreto-aleatorio-de-32-o-mas-caracteres
ORIGIN_VERIFY_SECRET=otro-secreto-aleatorio-de-32-o-mas-caracteres
REQUIRE_ORIGIN_VERIFY=true
REQUIRE_PLAY_INTEGRITY=true
ENABLE_API_DOCS=false
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON={...}
ANDROID_PACKAGE_NAME=mx.jale.app
PLAY_PRODUCT_ID=jale_pro
```

Verificar antes de desplegar:

```powershell
cd backend
.venv\Scripts\python.exe -m pytest -q
```

## 3. Cloud Run

Crear una imagen y desplegarla con las variables del `.env` como secretos. El servicio puede ser público para que Cloudflare llegue a él, pero FastAPI rechaza toda mutación sin `X-Origin-Verify`.

```bash
gcloud builds submit backend --tag REGION-docker.pkg.dev/PROJECT/jale-api:beta
gcloud run deploy jale-api --image REGION-docker.pkg.dev/PROJECT/jale-api:beta \
  --region REGION --allow-unauthenticated --port 8080
```

No publiques `backend/.env` ni el JSON de Google Play. Crea los valores sensibles como secretos en Secret Manager y pásalos al servicio (los nombres a la izquierda son variables de entorno):

```bash
gcloud run services update jale-api --region REGION \
  --set-env-vars="AI_BACKEND=gateway,AI_GATEWAY_URL=https://oficios-ai-adapter.<subdominio>.workers.dev,AI_GATEWAY_TIMEOUT_SECONDS=25,REQUIRE_ORIGIN_VERIFY=true,REQUIRE_PLAY_INTEGRITY=true,ENABLE_API_DOCS=false,ANDROID_PACKAGE_NAME=mx.jale.app,PLAY_PRODUCT_ID=jale_pro" \
  --set-secrets="AI_GATEWAY_TOKEN=jale-oficios-ai-token:latest,DATABASE_URL=jale-database-url:latest,SUPABASE_URL=jale-supabase-url:latest,SUPABASE_ANON_KEY=jale-supabase-anon:latest,INSTALLATION_PEPPER=jale-installation-pepper:latest,ORIGIN_VERIFY_SECRET=jale-origin-secret:latest,GOOGLE_PLAY_SERVICE_ACCOUNT_JSON=jale-play-service-account:latest"
```

El primer despliegue y la actualización de variables son intencionalmente dos pasos: así la imagen queda separada de los secretos y rotarlos no requiere reconstruirla.

`OPENAI_API_KEY` no es necesario en este modo. Para una migración temporal sin el gateway se puede usar `AI_BACKEND=openai` y la clave directa, pero esa configuración no debe llegar a la beta final.

## 4. Cloudflare Worker

Copiar `cloudflare/wrangler.toml.example` a `wrangler.toml`, poner la URL HTTPS de Cloud Run en `ORIGIN_URL` y desplegar:

```bash
cd cloudflare
npx wrangler login
npx wrangler secret put ORIGIN_VERIFY_SECRET
npx wrangler deploy
```

La beta puede usar el subdominio gratuito `jale-api.<cuenta>.workers.dev`. El APK debe apuntar a esa URL, nunca a Cloud Run. Los bindings `AI_RATE_LIMITER` y `AI_IP_RATE_LIMITER` limitan instalación+IP e IP respectivamente.

## 5. Google Play

1. Crear la aplicación con paquete `mx.jale.app`.
2. Crear la suscripción `jale_pro` con planes base `monthly` y `yearly`.
3. Dar a la cuenta de servicio acceso a la API de Google Play.
4. Configurar Play Integrity para el número de proyecto usado por `PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER`.
5. Crear un upload keystore privado y `android/key.properties` local; nunca subirlos al repositorio.

## 6. Build de beta

```bash
flutter build apk --release \
  --dart-define=JALE_API_URL=https://jale-api.<cuenta>.workers.dev \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable-key> \
  --dart-define=PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=<number>
```

El release solo está listo para Play cuando `apksigner verify` confirme la firma. Para desarrollo local sin Play Integrity se puede usar `REQUIRE_PLAY_INTEGRITY=false` en backend; nunca hacerlo en la beta distribuida por Play.

## 7. Prueba de aceptación

Probar con dos teléfonos reales: una IA anónima, registro por correo, dos IA de bienvenida, tres manuales del primer periodo, cambio de mes, cuatro manuales y dos IA; además compartir PDF, aceptar, abonar, anular pago, marcar no aceptada sin pagos y restaurar un respaldo cifrado.
