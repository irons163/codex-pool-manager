# CodexPoolManager v1.0.14

Fecha de publicación: 2026-06-10

## Correcciones

- Se evita el cierre async de inyección de dependencias de producción para el inicio de sesión con API key de relay, de modo que el servicio recibe la clave ya validada en lugar de un Data vacío en builds release.
- Se añadieron diagnósticos más profundos para la auth relay API key: versión/build de la app, longitudes recibidas por el login service y etapas sanitizadas de escritura de auth.json, sin exponer valores de API key.
- Ahora se pasa la API key del token vault directamente al request de cambio de cuenta relay, evitando que un estado SwiftUI obsoleto o redactado haga parecer faltante una key existente.
- Las cuentas con clave de API de relay ahora guardan su clave en el almacén de tokens inmediatamente al añadirlas, de modo que cambiar a una cuenta de relay recién creada ya no falla con un error de «falta la clave de API».
- Se evitó que `save()` purgara el almacén de tokens. Antes, una instantánea en memoria obsoleta o vacía (por ejemplo, un guardado durante el arranque) podía borrar permanentemente claves de API de relay y de ChatGPT (OAuth) aún válidas, sin posibilidad de recuperación porque la instantánea persistida está ofuscada. Ahora los tokens solo se eliminan mediante la eliminación explícita de una cuenta o un grupo.
- Se resuelven las API key relay directamente desde el token vault activo por ID de cuenta antes de cambiar, para que los snapshots redactados ya no se interpreten como keys faltantes.
- Se restauran las API key relay desde el token vault persistido antes de cambiar de cuenta cuando el estado en memoria del dashboard solo contiene el snapshot redactado.
- El cambio de cuentas relay API key ahora escribe directamente el `auth.json` API-key de Codex en lugar de invocar Codex CLI mediante stdin, evitando fallos de entrega stdin en builds release que hacían parecer faltante una key existente.
- Se reforzó el cambio a cuentas relay API key tomando una instantánea de los datos de la cuenta, el provider y la API key antes del flujo async. Esta corrección apunta al crash observado en la build release de v1.0.13.
- Se movió la comprobación de disponibilidad del formulario relay API key fuera del renderizado de SwiftUI body para evitar trims de strings adicionales durante las actualizaciones de la vista.
- Se añadió un diagnóstico de cambio relay sin datos sensibles: registra ID de cuenta, longitudes de token y etapas del cambio sin guardar valores de API key, para ubicar con precisión los reportes release-only donde la key parece faltar.

## Notas

- No se requiere migrar cuentas, API key, auth.json ni config.toml.
- Esta prerelease sirve para validar la hotfix de cambio de relay API key antes del lanzamiento stable.
- GitHub Release ahora incluye los dSYM correspondientes para facilitar el diagnóstico de crashes de release con registros simbolicados.
