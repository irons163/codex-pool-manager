# CodexPoolManager v1.0.16

Fecha de lanzamiento: 2026-07-11

## Novedades destacadas

- Las fechas de vencimiento de los créditos de restablecimiento ahora usan directamente los valores `expires_at` exactos devueltos por la API de detalles de la cuenta de Codex, en lugar de estimarse a partir de la última sincronización correcta.
- Las tarjetas de cuenta, el panel de la barra de menús y las alertas de restablecimiento muestran las fechas exactas de la API cuando están disponibles.
- Las fechas proporcionadas por la API ya no muestran la advertencia de fecha estimada; esta aparece únicamente cuando se necesita la estimación de respaldo.
- El origen de las fechas se conserva en las instantáneas de cuenta para distinguir las fechas exactas de la API de las estimaciones después de reiniciar la app.
- El README y todas las localizaciones compatibles ahora explican de forma coherente las fechas exactas de la API y las estimaciones de respaldo.

## Fiabilidad y compatibilidad

- La estimación existente se usa automáticamente cuando no se pueden obtener los detalles de la cuenta o las fechas de vencimiento.
- Las instantáneas creadas por versiones anteriores siguen siendo compatibles y se tratan de forma conservadora como datos estimados.
- Esta versión estable reúne los cambios validados en v1.0.15-rc.1.
