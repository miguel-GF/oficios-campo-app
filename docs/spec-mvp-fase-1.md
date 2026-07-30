# Spec canónica — MVP app móvil para oficios de campo

**Versión:** 0.1 · **Fecha original:** 29 jul 2026 · **Estado:** borrador para validación con usuarios reales

> Este documento preserva como referencia canónica inicial la especificación entregada para construir Jale. Los cambios de alcance posteriores deben registrarse mediante ADR o una nueva versión, no modificando silenciosamente estos principios.

## 1. Visión y principios

Herramienta móvil, voice-first y offline-first para técnicos de oficios a domicilio: fumigadores, técnicos de A/C, plomeros, electricistas e instaladores. Reemplaza al cuaderno y WhatsApp; no compite con ERPs.

1. **La voz le gana al menú.** Toda operación frecuente debe poder hacerse dictando; la UI táctil sirve como respaldo y confirmación.
2. **El catálogo emerge del uso.** No se exige dar de alta artículos o servicios antes de trabajar.
3. **Estructurado por dentro, libre por fuera.** El usuario habla natural; se guardan concepto, cantidad y precio como datos tipados.
4. **Cero fiscal en MVP.** Se generan notas de venta no fiscales. CFDI es un módulo opcional de fase 2.5.
5. **Offline-first.** Los datos y operaciones funcionan sin señal y sincronizan después.
6. **La IA interpreta, el código ejecuta.** Validaciones, cálculos y persistencia son deterministas. Dinero y escrituras siempre tienen preview y confirmación.

Usuario objetivo v1: negocios de 1–5 técnicos; el técnico/dueño es el usuario primario. Administración web llega en fase 2.

## 2. Pantallas del MVP

### 2.1 Hoy

- Header con fecha, negocio y estado de sincronización.
- Cards ordenadas por hora: cliente, servicio, dirección corta y estado.
- Acciones de un toque: navegar, llamar y WhatsApp.
- “Iniciar visita” cambia a `en_curso` y abre la orden.
- Vacío con “Agendar” y micrófono global.
- Visitas vencidas aparecen arriba con “pendiente de cerrar”. Pull-to-refresh fuerza sync.

### 2.2 Agenda

- Semana por defecto y vista mensual; desplazamiento horizontal.
- Voz: “Agéndame a la señora Martha el jueves 10 am…” → resolución del cliente → preview → confirmar/editar.
- Captura táctil mínima: cliente, fecha/hora, servicio libre y duración predeterminada de 60 minutos.
- Cliente inline exige solo nombre; teléfono es opcional y la dirección puede completarse después.
- Reprogramar, cancelar y generar mensaje prellenado mediante share intent, sin WhatsApp API.
- Homónimos se desambiguan en UI; un parse incompleto cae al formulario prellenado.

### 2.3 Orden de trabajo

Wizard vertical en una pantalla, diseñado para cerrar una visita en menos de dos minutos:

1. Evidencia opcional: múltiples fotos antes/después.
2. Dictado de trabajo → preview con renglones editables de concepto, cantidad, precio e importe. Si solo hay total, se crea un renglón.
3. Seguimiento: 1/3/6 meses o fecha manual y nota.
4. Cobro: efectivo, transferencia o pendiente; monto recibido por defecto igual al total.
5. Cerrar: nota PDF con logo, folio, negocio, cliente, renglones, total y leyenda “Este documento no es un comprobante fiscal”; compartir a WhatsApp; visita `terminada`.

Dinero usa `decimal(12,2)` e IVA incluido por defecto sin desglose. Tras tres usos del mismo concepto normalizado se sugiere guardarlo como servicio frecuente.

### 2.4 Clientes

- Buscar por nombre, teléfono o colonia; ordenar alfabéticamente o por recientes.
- Ficha con teléfonos, direcciones y notas.
- Timeline de órdenes con conceptos, total, fotos y pago.
- Facturación histórica, visitas, saldo y próximo seguimiento.
- Llamar, WhatsApp, agendar o crear orden directa.

### 2.5 Transversales

- Onboarding menor a dos minutos: teléfono/OTP, negocio, oficio y logo opcional.
- Ajustes: negocio, técnicos, MXN, IVA incluido y exportación.
- Voz global para consultas locales y acciones. Lecturas no requieren confirmación; escrituras sí.
- Fuera de alcance: CFDI, inventario, nómina, cotizaciones formales, tarjeta, multi-sucursal, reportes avanzados, reservas públicas y web admin.

## 3. Modelo de datos

Convenciones: UUID v7 generable offline, `created_at`, `updated_at`, `deleted_at`, `sync_status` (`synced|pending|conflict`) y `device_updated_at`; todas las tablas del tenant incluyen `negocio_id` y RLS.

| Tabla | Campos esenciales |
|---|---|
| `negocios` | nombre, oficio, teléfono, logo, IVA incluido, plan; datos fiscales futuros |
| `usuarios` | negocio, nombre, teléfono, rol (`dueno|tecnico|admin`), activo |
| `clientes` | negocio, nombre obligatorio, teléfono E.164, notas; datos fiscales futuros |
| `direcciones` | cliente, etiqueta, calle libre, lat/lng, referencias |
| `citas` | negocio, cliente, dirección, técnico, inicio, duración, servicio, estado, origen, orden |
| `ordenes` | negocio, cliente, técnico, cita, folio, estado, subtotal, total, notas/dictado, cierre |
| `orden_renglones` | orden, concepto, normalizado, cantidad, precio, importe, servicio |
| `servicios` | negocio, nombre, precio predeterminado, veces usado |
| `pagos` | orden, negocio, método, monto, fecha; saldo = total − suma de pagos |
| `adjuntos` | orden, tipo (`foto_antes|foto_despues|nota_pdf`), URL/local URI |
| `recordatorios` | negocio, cliente, orden origen, fecha, nota, estado |
| `eventos_voz` | negocio, usuario, transcripción, intención JSON, resultado y modo |

Los importes se recalculan y verifican en código/servidor; nunca se confía en el importe propuesto por IA.

## 4. Voz e IA

```text
Audio → STT → LLM con contexto → JSON estricto → validador determinista
      → PREVIEW → confirmación humana → escritura local → cola de sync
```

Intenciones v1: `crear_cita`, `crear_orden_renglones`, `registrar_pago` y `consulta`. Se rechazan montos negativos, citas pasadas y clientes inexistentes sin `crear_nuevo`. El matching fuzzy nunca elige solo entre homónimos.

### Degradación offline

| Situación | Comportamiento |
|---|---|
| Con señal | STT + LLM + preview en 2–3 segundos |
| Sin señal, dictado simple frecuente | STT on-device + reglas de alta confianza |
| Sin señal, complejo/ambiguo | Audio en cola; se procesa al reconectar y requiere confirmación |
| Sin señal, cualquier operación | Captura táctil, SQLite, cobro y PDF funcionan completamente |

Los audios se reintentan, se eliminan al confirmar o tras 30 días y jamás cierran una orden automáticamente. La UI usa lenguaje simple como “se enviará cuando haya señal”. `eventos_voz.modo` distingue `online`, `local_rules` y `diferido`.

## 5. Stack recomendado

- React Native + Expo + TypeScript para Android/iOS.
- SQLite local y PowerSync/ElectricSQL sobre Postgres.
- Supabase: Postgres, OTP, Storage, RLS y Edge Functions.
- Funciones TS para folios, verificación monetaria y acceso al LLM.
- PDF local mediante Expo Print; share intent/deep link para WhatsApp.
- Expo Notifications, PostHog y Sentry.
- Fase 2: Next.js compartiendo tipos/backend. Fase 2.5: PAC para CFDI 4.0.

## 6. Criterios de éxito

- Cerrar fotos + dictado + cobro + PDF en menos de 2 minutos.
- Al menos 70% de órdenes por voz confirmadas sin edición.
- Cinco negocios beta por cuatro semanas; tres dispuestos a pagar $299–499 MXN/mes.
- Sin señal: ver agenda, crear cita táctil, cerrar orden táctil y generar PDF.

## 7. Roadmap

| Fase | Alcance |
|---|---|
| 1 | Cuatro pantallas, voz, PDF y offline |
| 1.5 | Multi-técnico, invitación y asignación |
| 2 | Web admin, reservas públicas y recordatorios automáticos |
| 2.5 | CFDI 4.0 opcional y complemento de pago |
| 3 | Directorio/marketplace solo con densidad suficiente |
