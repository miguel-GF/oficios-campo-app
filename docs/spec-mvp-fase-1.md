# Especificación del MVP offline

## Objetivo

Jale permite que albañiles, plomeros, electricistas y otros trabajadores independientes generen una cotización profesional desde el teléfono, la compartan por WhatsApp, registren abonos y emitan recibos no fiscales sin depender de señal o de una cuenta.

## Flujo principal

1. Registrar nombre, oficio y teléfono del negocio.
2. Crear o elegir un cliente.
3. Capturar conceptos, cantidades, precios y notas.
4. Finalizar y compartir el PDF.
5. Marcar la cotización como enviada, aceptada o rechazada.
6. En una cotización aceptada, registrar uno o varios abonos.
7. Compartir un recibo por abono y conservar anulaciones para trazabilidad.

SQLite es la fuente de verdad. Los borradores se guardan automáticamente y volver al historial fuerza un último guardado.

## Reglas comerciales

- Gratis: 3 documentos únicos finalizados por mes. Una cotización cuenta al finalizarse; un recibo cuenta al generarse por primera vez. Recompartir no consume cupo.
- Pro: documentos ilimitados, logo, color institucional y eliminación de la marca “Creado con Jale”.
- Google Play: producto `jale_pro`, planes base `monthly` y `yearly`; precios beta sugeridos de $89 y $799 MXN.
- Cancelar Pro nunca elimina documentos. Si Play no está disponible, se conserva temporalmente el último derecho Pro verificado.

## Fuera de alcance

No hay cuentas, sincronización entre dispositivos, Supabase, agenda, cámara, pagos procesados por Jale, CFDI ni IA. La voz será un incremento posterior: dictado del dispositivo, interpretación de texto y 100 interpretaciones válidas al mes dentro de Pro. Los paquetes extra solo se evaluarán después de contar con identidad recuperable y evidencia de uso.

## Validación de lanzamiento

Beta cerrada con 10 trabajadores durante 2 semanas. Registrar manualmente: tiempo para primera cotización, finalización exitosa, errores de PDF/compartir, restauraciones de respaldo y disposición a pagar. Publicar cuando no existan pérdidas de datos ni fallos bloqueantes en el flujo principal.
