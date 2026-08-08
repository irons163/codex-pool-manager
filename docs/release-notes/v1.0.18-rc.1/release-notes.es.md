# CodexPoolManager v1.0.18-rc.1

Fecha de lanzamiento: 2026-08-08

## Correcciones

- El inicio de sesión OAuth ahora lee el ChatGPT Account ID desde la claim JWT anidada de OpenAI (`https://api.openai.com/auth.chatgpt_account_id`).
- La sincronización y el cambio de cuenta pueden recuperar un Account ID faltante desde los tokens id/access guardados.
- Se reconoce el email de perfil anidado en las claims de OpenAI durante el inicio de sesión.

## Nota de prerelease

- Esta prerelease valida la captura del Account ID de OAuth antes del lanzamiento estable.
