# ADR 0002: offline, identidad y distribución

Estado: aceptado, revisado el 13 de septiembre de 2026.

SQLite conserva todo el trabajo. Neon Auth/Postgres conserva identidad, sesiones, cuota y derecho Pro. La cuenta gratuita recibe dos IA por mes y una instalación anónima recibe una IA de por vida.

Se distribuye primero un APK directo (mx.jale.app) con Stripe. La variante Play (mx.jale.app.play) sirve sólo para iniciar sesión y consumir Pro existente; no ofrece compra externa. Play Billing no forma parte de la arquitectura.
