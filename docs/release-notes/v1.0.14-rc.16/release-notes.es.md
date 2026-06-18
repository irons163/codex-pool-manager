# CodexPoolManager v1.0.14-rc.16

Fecha de publicación: 2026-06-18

## Correcciones

- Las cuentas OAuth de ChatGPT ahora conservan refresh token, ID token y la última hora de renovación en el token vault.
- La sincronización de uso reintenta una vez después de una respuesta 401/403, renovando primero el OAuth access token.
- La importación local de auth.json ahora incorpora también refresh token e ID token en las cuentas OAuth administradas.
- Al combinar resultados de sincronización, una instantánea antigua ya no sobrescribe credenciales locales más recientes.

## Notas

- Esta prerelease valida la estabilidad de renovación automática de cuentas OAuth antes del despliegue stable.
- No se requiere migrar relay API key, config.toml ni auth.json.
