# CodexPoolManager v1.0.20-rc.7

Fecha de publicación: 2026-10-05

## Cambios

- Guarda las credenciales OAuth renovadas antes de consultar el uso, para que un error o una cancelación posterior no descarte los tokens rotados.
- Distingue el rechazo confirmado de credenciales de los errores de red, los límites de solicitudes, los errores del servicio y la ausencia de un token de renovación, en lugar de indicar que cualquier fallo es una sesión caducada.
- Impide que un resultado de renovación tardío sobrescriba las credenciales reimportadas o restaure cuentas eliminadas.
- Cambia la etiqueta de OpenAI Reset Alert a «Se retirará pronto» en todos los idiomas disponibles. La función sigue disponible en esta versión preliminar.
- Añade pruebas de regresión para la rotación de tokens, la clasificación de errores, la cancelación y los resultados de renovación obsoletos.

## Nota de prerelease

- Esta versión preliminar valida la fiabilidad de la renovación OAuth antes de la versión estable 1.0.20. Las credenciales realmente revocadas siguen requiriendo iniciar sesión de nuevo.
