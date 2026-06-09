# CodexPoolManager v1.0.12

Fecha de publicación: 2026-06-09

## Correcciones

- Se corrigió un crash de la build Release v1.0.11 que podía ocurrir poco después del inicio.
- Se restauró la ruta de inicio production del dashboard, manteniendo el aislamiento de preferencias XCTest para las pruebas app-hosted.
- Se redujo un warning MainActor solo de debug en los helpers de cobertura del dashboard.

## Notas

- No se requiere migrar cuentas, API key, auth.json ni config.toml.
- Se recomienda esta hotfix para todos los usuarios de v1.0.11.
