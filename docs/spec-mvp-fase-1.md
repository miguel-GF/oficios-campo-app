# Especificacion del MVP

## Promesa

Jale ayuda a un trabajador de oficio a convertir una explicacion hablada en una cotizacion profesional, darle seguimiento hasta cobrarla y conservar todo en su telefono, incluso sin senal.

## Flujo principal

1. Registrar negocio, oficio, telefono, color e imagen.
2. Dictar el trabajo o capturar conceptos manualmente.
3. Revisar cliente, conceptos, cantidades y precios antes de incorporar el resultado de IA.
   Al confirmar, Jale combina los conceptos con la cotizacion actual; normaliza acentos y palabras, marca coincidencias y no agrega duplicados. Un concepto nuevo se incorpora, y el precio del catalogo solo se usa cuando existe una coincidencia suficientemente clara.
4. Reutilizar conceptos y ultimos precios desde el catalogo personal.
5. Finalizar y compartir un PDF multipagina.
6. Marcar como enviada, aceptada o no aceptada.
7. En una aceptada, registrar abonos y emitir recibos no fiscales.
8. Consultar por cobrar/cobrado y actividad por semana o mes.

Los borradores se guardan automaticamente y al cerrar la pantalla. Una cotizacion con pagos activos no puede cambiar de cliente, total ni pasar a no aceptada. Compartir de nuevo el PDF no rebaja una cotizacion aceptada, con abono o pagada a "enviada". Las anulaciones se conservan para trazabilidad.

## IA y modelo comercial

- Motor: `gpt-5.6-luna` con razonamiento bajo y salida estructurada.
- El audio se transcribe en el dispositivo; el backend recibe texto, no un archivo de audio.
- Sin cuenta: 1 uso IA. Registro por correo: 2 usos IA de bienvenida.
- Primer periodo: 3 cotizaciones manuales. Meses posteriores: 2 IA y 4 manuales.
- Pro: manual e IA sin limite visible; 500 interpretaciones IA mensuales es una barrera antiabuso revisable, no un paquete ni un cobro adicional.
- Un fallo tecnico devuelve la reserva. Reintentar con la misma llave no duplica consumo.

## Datos y seguridad

Clientes, cotizaciones, pagos y PDFs permanecen locales. El respaldo manual se cifra antes de salir del telefono. Supabase/Postgres registra cuenta, cuotas, derecho Pro y auditoria minima de Play; no almacena el texto dictado ni los datos del cliente. OpenAI y Google Play solo se llaman desde FastAPI, nunca con secretos incluidos en el APK.

En produccion, Cloudflare protege el origen y Play Integrity liga cada accion sensible al cuerpo exacto, al paquete oficial y a un dispositivo integro. La app valida compras en el servidor antes de habilitar Pro y mantiene como maximo tres dias el ultimo derecho valido sin conexion.

## Fuera de alcance

CFDI, cobro de trabajos dentro de Jale, web administrativa, equipo multiusuario, sincronizacion completa y respaldo remoto automatico. El esquema reserva espacio para respaldo cifrado futuro, pero no se activa sin una pantalla clara de consentimiento y recuperacion.

## Criterio de lanzamiento

Analisis estatico y pruebas verdes, migraciones verificadas, APK/AAB firmados, productos Play activos y prueba cerrada en telefonos reales. La beta debe demostrar reduccion de tiempo y ausencia de perdida de datos antes de produccion abierta.
