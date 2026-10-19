# CodexPoolManager v1.0.21-rc.2

Fecha de publicación: 2026-10-19

## Correcciones

- Resuelve los enlaces simbólicos antes de buscar sesiones y restablece las estadísticas cuando los registros de Codex están en un disco externo o en una carpeta enlazada.
- Recorre cada carpeta física una sola vez cuando sessions y archived_sessions apuntan a la misma ubicación, evitando trabajo duplicado y alcanzar antes de tiempo los límites de lectura.
- Conserva las correcciones de credenciales de espacios de trabajo y las etiquetas «Empresa» de rc.1.

## Nota de versión preliminar

- Los registros grandes pueden seguir alcanzando los límites de lectura existentes. Las estadísticas parciales siguen indicándose claramente.
