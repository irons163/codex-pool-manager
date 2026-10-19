# CodexPoolManager v1.0.21-rc.1

Fecha de publicación: 2026-10-19

## Cambios

- Separa los espacios personales y empresariales que comparten un correo mediante su ID de cuenta, sin reutilizar credenciales solo por coincidir el correo.
- Valida las credenciales locales de Codex más recientes antes de actualizar el grupo de cuentas y conserva las credenciales verificadas si una sincronización posterior falla o se cancela.
- Detiene la sincronización y el cambio de cuenta cuando las credenciales pertenecen a otro espacio, con una indicación clara para iniciar sesión. También valida el espacio al renovar los tokens.
- Muestra la etiqueta «Empresa» para las cuentas Team, Business y Enterprise en las tarjetas, la barra de menús y la planificación.
- Añade análisis de sesiones locales de Codex con uso de tokens, tasa de aciertos de caché, costo estimado, tendencias, actividad y detalles por modelo y solicitud.

## Nota de versión preliminar

- Esta versión preliminar valida la separación de espacios y las etiquetas empresariales antes de la versión estable v1.0.21. Las credenciales revocadas siguen requiriendo iniciar sesión de nuevo.
