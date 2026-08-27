# ADR 0001 — Modelo comercial y control de cobros

> Reemplazado para el lanzamiento inicial por [ADR 0002](0002-mvp-offline-y-suscripcion-play.md).

- **Estado:** aceptado
- **Fecha:** 3 de agosto de 2026
- **Alcance:** lanzamiento de Fase 1

## Contexto

Jale es una herramienta operativa para plomeros, carpinteros y otros oficios. No pretende ser una terminal, agregador de pagos ni intermediario financiero. Existen dos conceptos distintos que deben mantenerse separados:

1. La suscripción que el negocio paga por usar Jale.
2. El control de lo que los clientes le deben al negocio por sus servicios.

## Decisión 1: una sola suscripción Jale

Habrá un único plan funcional, sin niveles ni funciones bloqueadas, vendido mediante Google Play Billing en Android. El mismo plan tendrá dos periodos de facturación:

| Periodo | Precio normal | Oferta de lanzamiento | Ahorro anual |
|---|---:|---:|---:|
| Mensual | $149 MXN | $99 MXN/mes | — |
| Anual | $1,490 MXN | $990 MXN/año durante lanzamiento | 2 meses frente al periodo mensual equivalente |

La oferta de lanzamiento no crea un plan distinto: es una oferta sobre la misma suscripción. Los precios finales, impuestos, elegibilidad, duración de la oferta y moneda localizada se configurarán y verificarán en Google Play Console. Los identificadores internos propuestos son `jale` para la suscripción y `monthly`/`yearly` para sus periodos, sujetos a validar contra la versión vigente de Play Billing.

Cada instalación/cuenta nueva tendrá **15 días de prueba gratuita** sobre el plan completo. No se pedirá tarjeta dentro de Jale. La conversión, renovación y cancelación se realizarán con Google Play; la elegibilidad real de la prueba deberá provenir de la tienda para evitar reinstalaciones o cuentas duplicadas.

La aplicación deberá conservar un modo de gracia corto cuando no pueda consultar la tienda, pero una compra nueva nunca se habilitará únicamente con estado local. El backend verificará la compra, almacenará el derecho de acceso y procesará renovaciones, cancelaciones y reembolsos. No se almacenarán datos de tarjeta en Jale.

## Decisión 2: Jale no procesa pagos de los clientes

Fase 1 solamente controla cuentas por cobrar. Una orden tendrá un total determinista y cero o más registros de pago manuales. Su estado se deriva, no se captura de forma independiente:

- `pending`: suma de pagos igual a cero.
- `partial`: suma de pagos mayor que cero y menor que el total.
- `paid`: suma de pagos igual o mayor que el total.

El usuario podrá registrar efectivo o transferencia, importe y fecha; añadir otro abono; corregir o anular un registro con trazabilidad; y consultar saldo pendiente. El PDF mostrará total, pagado y saldo. El cierre de una orden no exige que esté pagada.

Quedan fuera de Fase 1:

- Links, QR o checkout para que el cliente pague.
- Jale como terminal o agregador.
- Integración con bancos, Stripe o Mercado Pago.
- Comisión por transacción.
- Almacenamiento de tarjeta.
- CFDI y conciliación bancaria.

Si en el futuro se aceptan pagos, se diseñará como un módulo separado y no cambiará retroactivamente el libro operativo de órdenes y abonos.

## Consecuencias

- El mensaje comercial es simple: todas las funciones por una sola suscripción.
- La validación inicial mide disposición de pago a $99 MXN y retención antes de subir a $149 MXN.
- El modelo local `payments` sigue siendo válido, pero la interfaz debe permitir abonos parciales y calcular el estado desde la suma de pagos.
- Google Play es la fuente de verdad de la compra; Supabase conserva el derecho de acceso verificado, no información financiera sensible.
- Antes de implementar Play Billing se deben revisar sus políticas y APIs oficiales vigentes, especialmente reglas de ofertas, periodos base, reconocimiento de compras y verificación del lado servidor.
