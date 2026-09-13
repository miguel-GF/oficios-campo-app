# ADR 0001: modelo comercial y control de cobros

Estado: aceptado, revisado el 13 de septiembre de 2026.

Jale Pro es una sola suscripción con periodos mensual y anual, sin trial, cobrada por Stripe en la distribución directa. El webhook Stripe es la fuente de verdad del derecho Pro.

Las cotizaciones manuales son ilimitadas. Los pagos locales representan abonos en efectivo, transferencia u otro método entre trabajador y cliente. Jale calcula pagado/saldo y emite recibos no fiscales, pero no mueve ese dinero ni genera CFDI.
