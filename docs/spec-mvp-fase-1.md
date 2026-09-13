# Especificación del MVP

Jale convierte una explicación hablada o una captura manual en una cotización profesional, permite seguirla hasta cobrarla y conserva el trabajo en el teléfono aun sin señal.

## Flujo

1. Registrar negocio, oficio, teléfono, color e imagen.
2. Dictar el trabajo o capturar conceptos manualmente.
3. Revisar cliente, cantidades y precios antes de incorporar la salida de IA.
4. Reutilizar conceptos y últimos precios del catálogo.
5. Finalizar y compartir un PDF multipágina.
6. Marcar la cotización enviada, aceptada o no aceptada.
7. Registrar abonos en una aceptada y emitir recibos no fiscales.
8. Consultar por cobrar, cobrado y actividad semanal o mensual.

Los autoguardados se serializan. Una cotización con pagos activos no puede cambiar cliente ni total. SQLite rechaza de forma atómica pagos no positivos, pagos en cotizaciones no aceptadas y sobrepagos. La restauración cifra el archivo, valida relaciones y totales, reemplaza todo en una transacción y recalcula folios.

## IA y Pro

- Invitado: un uso IA por instalación.
- Cuenta Neon: dos usos IA por mes.
- Manual: ilimitado.
- Pro: IA sin límite visible y revisión técnica al llegar a 500 usos mensuales.
- Stripe ofrece mensual y anual, sin periodo de prueba.
- Un fallo confirmado devuelve la reserva. Un timeout conserva el request_id; el reintento recupera la salida cacheada si la llamada original terminó.

## Datos

SQLite es la fuente de verdad de clientes, cotizaciones, conceptos y abonos. Neon almacena cuenta, sesiones, cuota, derecho Pro y auditoría. El gateway conserva la salida estructurada hasta 24 horas para idempotencia; no conserva audio y OpenAI se invoca con almacenamiento desactivado.

Quedan fuera CFDI, cobro de trabajos con tarjeta, sincronización completa, equipos y respaldo remoto automático.
