# CodexPoolManager v1.0.14

Fecha de publicación: 2026-06-10

## Correcciones

- Se restauran las API key relay desde el token vault persistido antes de cambiar de cuenta cuando el estado en memoria del dashboard solo contiene el snapshot redactado.
- Se normalizó el payload stdin de la API key relay antes de llamar a `codex login --with-api-key`: las keys vacías se rechazan antes de lanzar Codex CLI, y las keys válidas se envían como bytes propios con un salto de línea final.
- Se reforzó el cambio a cuentas relay API key tomando una instantánea de los datos de la cuenta, el provider y la API key antes del flujo async. Esta corrección apunta al crash observado en la build release de v1.0.13.
- Se evitó el crash de release al cambiar a una cuenta relay pasando bytes ya preparados de la API key al login de Codex CLI, en lugar de volver a hacer trim del string dentro del closure async de login.
- Se movió la comprobación de disponibilidad del formulario relay API key fuera del renderizado de SwiftUI body para evitar trims de strings adicionales durante las actualizaciones de la vista.

## Notas

- No se requiere migrar cuentas, API key, auth.json ni config.toml.
- Esta prerelease sirve para validar la hotfix de cambio de relay API key antes del lanzamiento stable.
- GitHub Release ahora incluye los dSYM correspondientes para facilitar el diagnóstico de crashes de release con registros simbolicados.
