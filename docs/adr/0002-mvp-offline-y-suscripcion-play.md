# ADR 0002: MVP offline y suscripción de Google Play

- Estado: aceptado
- Fecha: 2026-08-10
- Reemplaza: ADR 0001 para el lanzamiento inicial

## Decisión

Mantener SQLite como fuente de verdad del trabajo y lanzar la cuenta como una capacidad opcional del MVP. El plan Gratis usa 1 IA de invitado, 2 IA de bienvenida tras correo, 3 manuales en el primer periodo y 2 IA + 4 manuales después. Jale Pro se vende como suscripción de Google Play; el backend verifica y liga el derecho a la cuenta.

La voz transcribe en el dispositivo y `gpt-5.6-luna` convierte el texto en salida estructurada revisable. Pro se comunica como IA sin límite visible con una barrera técnica de uso razonable. Cloudflare protege el origen, Supabase lleva cuotas/auditoría y Play Integrity protege el cuerpo de cada petición en producción. Los respaldos remotos solo se considerarán como blobs ya cifrados y con consentimiento explícito.

## Consecuencias

La app funciona en campo sin señal y evita fricción de registro; los datos de clientes siguen locales. La contrapartida es que las cuotas IA y los derechos Pro requieren internet, y una cuenta para recuperarlos. Introducir sincronización o consumibles exige evidencia de demanda y no debe comprometer la base local existente.
