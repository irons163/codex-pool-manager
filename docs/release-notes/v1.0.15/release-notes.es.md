# CodexPoolManager v1.0.15

Fecha de lanzamiento: 2026-07-03

## Novedades

- Las tarjetas de cuenta ahora muestran los créditos de restablecimiento disponibles y el vencimiento estimado de cada crédito.
- Las tarjetas Minimal resumen los créditos con fechas compactas como `2 restablecimientos · 7/30, 8/1`.
- El panel de la barra de menú ahora admite filtro por grupo de cuentas, popovers de aviso compactos, insignias Plus/Pro, detalles de vencimiento de créditos y botones de cambio siempre visibles.
- Se añadieron avisos localizados de novedades tras cambios de versión/build, con una acción en Settings para volver a abrir las notas recientes.
- Se mejoró la estabilidad de renovación automática OAuth y se mantienen release notes en todos los idiomas soportados.
- Las capturas de menu bar del README ahora se renderizan desde el panel SwiftUI real con datos mock no sensibles.

## Notas

- El vencimiento de los créditos se estima sumando 30 días a la sincronización exitosa anterior; el vencimiento real puede diferir.
- Esta versión stable agrupa los cambios validados durante el ciclo prerelease v1.0.14 rc.16 a rc.19.
