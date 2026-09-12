# Backend de beta: cuenta, IA y cobro

## Decisión

- Flutter y SQLite continúan funcionando offline y contienen clientes, cotizaciones y pagos del trabajador.
- Supabase Auth registra al usuario por correo y Supabase Postgres conserva cuotas, derechos Pro y auditoría de consumo.
- FastAPI en Python conserva la autenticación, cuotas y reserva de consumo. En modo `gateway` llama al adapter `oficios.interpret_quote` de la plataforma central; el gateway controla proveedor, modelo, prompt, validación estructurada y presupuesto. El modo `openai` queda solo como transición local.
- Un Worker de Cloudflare expone `jale-api.<cuenta>.workers.dev`, agrega un secreto de origen y permite aplicar rate limiting/WAF sin incluir secretos en Android.
- `workers.dev` funciona como subdominio gratuito para la beta. Un dominio propio requiere comprar/usar uno y conectarlo en Cloudflare; no se debe prometer un dominio personalizado gratis.
- Los respaldos remotos, si se habilitan, serán blobs ya cifrados por el teléfono. El servidor solo conserva tamaño, checksum y ruta.

## Cuotas beta

1. Instalación sin cuenta: una interpretación IA.
2. Al registrar correo: dos créditos de bienvenida.
3. Primer periodo: tres cotizaciones manuales. Meses posteriores: dos interpretaciones IA y cuatro cotizaciones manuales por mes.
4. Pro: se anuncia como IA sin límite, sujeto a uso razonable. El límite técnico inicial es 500 interpretaciones mensuales y genera revisión, no un cobro inesperado.
5. Un fallo o salida inválida de OpenAI devuelve la reserva y no consume crédito.

## Costo controlado

El backend limita el dictado a 2,000 caracteres y la salida a 800 tokens, usa razonamiento bajo y no guarda la respuesta en OpenAI. Como orden de magnitud, con 1,000 tokens de entrada y 300 de salida una interpretación cuesta alrededor de USD 0.00056 usando la tarifa documentada de Luna; el precio real puede cambiar y se debe vigilar desde el dashboard de OpenAI. La cuota y el rate limit de Cloudflare evitan que un script convierta un error de configuración en una factura abierta.

## Seguridad

- Las credenciales de IA y Google Play nunca se incluyen en la app. En modo `gateway`, la clave de OpenAI vive únicamente en la plataforma central; Oficios conserva solo el token de servicio del adapter.
- Google Play recibe un identificador de cuenta obfuscado (hash), nunca el correo ni el UUID legible.
- El backend valida cada bearer token contra Supabase Auth.
- Toda mutación sensible usa credencial de servicio y las tablas tienen RLS sin permisos de escritura para el cliente.
- Cada interpretación lleva `Idempotency-Key`, reserva atómica y una huella de instalación estable; el Worker limita además por instalación + IP sin usar la IP para gastar cuotas.
- El bono de bienvenida queda reclamado por instalación; crear otra cuenta en el mismo teléfono no lo multiplica.
- Cloud Run debe aceptar tráfico únicamente con `X-Origin-Verify`; el valor solo vive en Cloudflare y en el backend.
- El Worker no cachea respuestas de cuenta/IA, elimina cookies de salida y rechaza cuerpos de IA mayores a 64 KiB.
- Play Integrity ya está integrado: liga el hash del cuerpo a un token, valida paquete oficial, antigüedad del veredicto y `MEETS_DEVICE_INTEGRITY`. El `installation_id` y `request_id` del cuerpo deben coincidir con sus encabezados para impedir reutilizar una respuesta en otra instalación o solicitud. En beta local puede quedar desactivado; producción debe usar `REQUIRE_PLAY_INTEGRITY=true`.

## Despliegue

1. Ejecutar la migración SQL en Supabase.
2. En Supabase Auth, usar OTP por correo y editar la plantilla para mostrar `{{ .Token }}`; Jale pide un código de seis dígitos, no un enlace.
3. Desplegar la plataforma central y registrar `AI_GATEWAY_URL` y `AI_GATEWAY_TOKEN` en Cloud Run. El token debe coincidir con `OFICIOS_INTERNAL_TOKEN` del adapter y nunca llegar al APK.
4. Construir `backend/Dockerfile` y desplegar el contenedor.
5. Configurar el Worker con `ORIGIN_URL`, `ORIGIN_VERIFY_SECRET`, `AI_RATE_LIMITER` (30 por instalacion/minuto) y `AI_IP_RATE_LIMITER` (120 por IP/minuto).
6. Activar y vincular Play Integrity en Play Console, dar a la cuenta de servicio acceso a la API y usar `REQUIRE_PLAY_INTEGRITY=true`.
7. Compilar con `JALE_API_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER` como `dart-define`.

`AI_BACKEND=gateway` debe quedar activo en beta y producción. `OPENAI_API_KEY` solo se conserva para una migración controlada o desarrollo aislado; no se necesita cuando el gateway está operativo. `ENABLE_API_DOCS` queda en `false` en producción; solo se activa temporalmente en desarrollo si se necesita Swagger.
