# CodexPoolManager v1.0.21-rc.4

Fecha de publicación: 2026-10-19

## Correcciones

- Lee cada registro de sesión hasta el final existente al iniciar el análisis, sin detenerse a los 128 MiB por archivo, y recupera los eventos al final de registros grandes.
- Lee en bloques pequeños y omite pronto el contenido de conversaciones, manteniendo un búfer limitado para metadatos y la posibilidad de cancelar.
- Identifica tipos reales de metadatos en lugar de palabras clave en las salidas de herramientas, evitando avisos incorrectos cuando estas mencionan token_count.
- Conserva la separación de miembros, las etiquetas Empresa y el soporte para carpetas de sesiones enlazadas.

## Nota de versión preliminar

- Los archivos ilegibles, las fuentes de bifurcación sin resolver y los límites de eventos siguen mostrando el aviso de estadísticas incompletas.
