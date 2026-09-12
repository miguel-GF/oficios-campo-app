# Roadmap de Jale

## Ahora — MVP innovador

El producto base ya cubre el ciclo completo: crear por voz o manualmente, revisar, cotizar, compartir, registrar aceptación, cobrar por abonos y ver el avance semanal o mensual. La IA usa precios dictados; nunca inventa un precio silenciosamente. SQLite conserva el trabajo aun sin señal, mientras el backend solo administra identidad, cuotas y la suscripción.

Puerta de salida: análisis y pruebas verdes, APK instalable, configuración de producción documentada y cero errores bloqueantes conocidos.

## Siguiente — Beta cerrada (10 trabajadores, 2 semanas)

Medir con entrevistas y observación:

- tiempo hasta la primera cotización compartida;
- porcentaje de dictados aceptados sin editar y campos que más se corrigen;
- cotizaciones aceptadas y dinero recuperado con seguimiento;
- fallos de micrófono, PDF, restauración y dispositivos de gama baja;
- conversión después del crédito gratis y disposición a pagar.

Primero se corrige cualquier riesgo de pérdida de datos, cobro incorrecto o bloqueo. No se agrega analítica invasiva al APK; el backend ya permite contar consumo técnico sin almacenar el texto completo.

## Después — Lanzamiento en Play

Configurar Supabase, Cloud Run, Cloudflare, dominio, Play Billing, RTDN y Play Integrity. Completar ficha, capturas, política de privacidad, Data Safety, pruebas cerradas exigidas por Google y soporte. El precio se decide con la beta; no se codifica en la app y siempre se muestra el precio localizado que devuelve Play.

## Evolución — Recuperación y colaboración

Prioridad recomendada:

1. respaldo remoto opt-in de un blob ya cifrado en el teléfono;
2. restauración en un teléfono nuevo y control de versiones/espacio;
3. agenda y recordatorios de seguimiento;
4. sincronización multi-dispositivo solo si los usuarios realmente la piden;
5. catálogo asistido por oficio a partir de datos propios, sin compartir datos identificables entre usuarios.

No se debe convertir Jale en procesador de pagos ni CFDI dentro de este alcance. Los abonos registrados son control del trabajador; los únicos pagos procesados por la plataforma son las suscripciones de Google Play.
