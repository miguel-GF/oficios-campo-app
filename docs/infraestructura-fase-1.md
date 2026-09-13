# Infraestructura del lanzamiento

Jale usa SQLite local para el trabajo y Neon Postgres para identidad, sesiones, cuotas, Pro y auditoría. FastAPI corre con un pool Postgres asíncrono y /health comprueba configuración más una consulta real. Cloudflare limita el tráfico y el gateway central controla modelo, prompt, esquema, costo e idempotencia.

Stripe procesa únicamente Jale Pro. La base local payments registra efectivo o transferencia entre trabajador y cliente, sin enviar esos datos al servidor.

Hay dos distribuciones Android. direct (mx.jale.app) abre Stripe Checkout y se publica como APK firmado. play (mx.jale.app.play) sólo sincroniza y consume un derecho existente; no contiene una llamada, botón o enlace de compra externa.

Antes de publicar: migraciones aplicadas, secretos cargados, certificados/versiones autorizados, webhook Stripe verificado, análisis, pruebas Flutter/Python/Worker, ambos builds Android y restauración real en otro teléfono.
