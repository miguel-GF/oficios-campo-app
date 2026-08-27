# ADR 0002: MVP offline y suscripción de Google Play

- Estado: aceptado
- Fecha: 2026-08-10
- Reemplaza: ADR 0001 para el lanzamiento inicial

## Decisión

Lanzar Jale sin cuenta ni backend. SQLite será la fuente de verdad, con Auto Backup de Android y respaldo manual cifrado. El plan Gratis permitirá tres documentos finalizados por mes. Jale Pro se venderá como una suscripción de Google Play con planes mensual y anual, provisionalmente a $89 y $799 MXN.

La primera versión no contiene IA. La futura captura por voz incluirá 100 interpretaciones válidas mensuales en Pro; no se ofrecerá “voz ilimitada”. Los créditos adicionales no se implementarán hasta contar con identidad recuperable, verificación remota y demanda observada.

## Consecuencias

La app funciona en campo sin señal, cuesta poco operar y evita fricción de registro. La contrapartida es que el respaldo entre plataformas, la recuperación de derechos y la validación robusta de compras quedan limitados. Introducir sincronización, IA o consumibles exige una migración explícita y no debe comprometer la base local existente.
