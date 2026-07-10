# CodexPoolManager v1.0.15-rc.1

Fecha de lanzamiento: 2026-07-11

## Mejoras

- Las fechas de vencimiento de los créditos de restablecimiento ahora usan directamente los valores `expires_at` devueltos por el endpoint de detalles de la cuenta de Codex, en lugar de estimarse a partir de la última sincronización correcta.
- Las tarjetas de cuenta y las alertas de restablecimiento muestran las fechas exactas de la API cuando están disponibles.
- Las fechas proporcionadas por la API ya no muestran la advertencia de fecha estimada; esta aparece únicamente cuando se necesita la estimación de respaldo.
- El origen de las fechas se conserva en las instantáneas de cuenta para distinguir las fechas exactas de la API de las estimaciones después de reiniciar la app.
- El README y todas las localizaciones compatibles ahora explican de forma coherente las fechas exactas de la API y las estimaciones de respaldo.

## Compatibilidad

- La estimación existente sigue disponible cuando no se pueden obtener los detalles de la cuenta o las fechas de vencimiento.
- Las instantáneas creadas por versiones anteriores siguen siendo compatibles y se tratan de forma conservadora como datos estimados.

## Nota de prerelease

- Esta prerelease valida la sincronización de las fechas de vencimiento exactas y el respaldo cuando no hay datos antes del próximo lanzamiento estable.
