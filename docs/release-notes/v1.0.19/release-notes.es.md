# CodexPoolManager v1.0.19

Fecha de lanzamiento: 2026-08-28

## Correcciones

- El cambio de cuenta ahora cierra Codex antes de reescribir las credenciales, para que una sesión en uso no se trate como revocada.
- El cambio escribe los tokens refresh/id de la cuenta de destino en lugar de dejar los de la cuenta anterior en `auth.json`.
- Las credenciales también se actualizan en el llavero de Codex y en el espejo `current_account` de las versiones nuevas.
