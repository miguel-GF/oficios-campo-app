# Plan de evolución de Jale

Este documento convierte el MVP en un producto validable sin adelantar costes de servidor ni obligar a los primeros usuarios a crear una cuenta.

## Fase 0 — Base entregada

Android offline-first: negocio, clientes, cotizaciones, PDF, aceptación, pagos, recibos, SQLite, Auto Backup, respaldo cifrado y suscripción Play. Criterio: `typecheck`, pruebas, bundle Android y prebuild correctos.

## Fase 1 — Beta cerrada (2 semanas)

Probar con 10 trabajadores de oficios. Medir manualmente tiempo hasta la primera cotización, documentos compartidos, errores de restauración, fallos de PDF y conversaciones de pago. No añadir analítica SDK. Corregir cualquier pérdida de datos o bloqueo antes de abrir la pista de producción.

## Fase 2 — Lanzamiento offline

Publicar APK/AAB con `jale_pro`, planes `monthly` y `yearly`, textos de renovación, política de privacidad y soporte. Usar como referencia $89 MXN/mes y $799 MXN/año; ajustar solo con evidencia de conversión y retención. Mantener la cuota Gratis en tres documentos finalizados al mes.

## Fase 3 — Voz como incremento

Primero añadir dictado del teclado o reconocimiento del dispositivo. Después enviar únicamente texto a un proveedor de interpretación para convertirlo en conceptos, cantidades y precios con vista previa y confirmación. En Pro incluir 100 interpretaciones válidas por mes; una corrección o intento fallido no debe gastar crédito. Registrar localmente el contador y explicar cuándo se reinicia.

No ofrecer voz ilimitada. Evaluar paquetes de 100 créditos por $29 MXN solo si al menos 5% de usuarios Pro alcanza el límite durante dos meses consecutivos, existe soporte para cobro y hay una identidad recuperable para evitar abuso y restaurar créditos.

## Fase 4 — Identidad y migración opcionales

Antes de sincronizar, introducir cuenta opcional, vincularla con un código de migración y subir primero un respaldo cifrado validado. Conservar SQLite como caché y permitir exportar los datos. Migrar derechos de Play y créditos a un servidor con verificación de tokens; nunca exigir cuenta para abrir datos existentes.

## Puertas de decisión

Cada fase requiere estabilidad del flujo principal, evidencia de uso y una estrategia reversible. Si la voz no reduce tiempo o aumenta conversiones, permanecer en el modo manual offline. Si la sincronización no resuelve una necesidad clara, mantener el producto local y no asumir costes de infraestructura.
