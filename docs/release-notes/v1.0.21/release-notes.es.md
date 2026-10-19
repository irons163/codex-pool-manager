# CodexPoolManager v1.0.21

Fecha de publicación: 2026-10-19

## Mejoras

- Añade análisis del uso local de Codex: tokens, tasa de aciertos de caché, costes estimados, tendencias, historial de actividad y desglose por modelo y solicitud.
- Muestra una etiqueta Business para las cuentas Team, Business y Enterprise en las tarjetas, la barra de menús y la programación.
- Mantiene «Informar de un problema» al pie de la barra lateral, con opciones de GitHub y correo desde la aplicación. Los informes se envían a `feedback@codexpool.zero2codex.dev` sin abrir un cliente de correo.
- La dirección de respuesta es opcional y las versiones de la aplicación y del sistema solo se adjuntan si se seleccionan. Los reintentos sin cambios no generan envíos duplicados.

## Correcciones

- Separa los espacios personales y empresariales que comparten correo y distingue a los miembros de un mismo espacio al recuperar inicios de sesión, importar, renovar credenciales, sincronizar el uso y cambiar de cuenta.
- Resalta una sola tarjeta como cuenta actual y rechaza credenciales de otro espacio o miembro.
- Admite carpetas de sesiones enlazadas y procesa los registros grandes completos omitiendo el cuerpo de las conversaciones. Recupera eventos de uso que faltaban y evita avisos incorrectos de estadísticas incompletas.

## Actualización

- Si una cuenta anterior indica que el espacio o el usuario no coincide, vuelve a iniciar sesión en esa cuenta para sustituir las credenciales guardadas.
