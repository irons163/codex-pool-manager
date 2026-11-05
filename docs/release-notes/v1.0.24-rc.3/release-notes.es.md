# CodexPoolManager v1.0.24-rc.3

Fecha de lanzamiento: 2026-11-05

## Novedades

- Se añadió el modo de cambio «Orden definido»: ordena las cuentas en la página de estrategia y rota por ese orden, volviendo a la primera después de la última.
- El umbral de cambio también se aplica a este modo; las cuentas excluidas de sincronización y las de Relay se omiten automáticamente.

## Mejoras

- En el orden por uso restante, las cuentas caducadas o excluidas de la sincronización quedan debajo de las cuentas sanas, mientras la cuenta activa permanece primero.
- Las cuentas de empresa usan una insignia morada para distinguirlas de las personales.
- La lista de orden de cambio ahora admite arrastrar y soltar; los botones arriba/abajo siguen disponibles.

## Correcciones

- Se distinguen las credenciales revocadas de otros errores de sincronización y se recupera automáticamente tras la rotación del token.
- Se corrigió la verificación de actualizaciones de Sparkle: la clave pública EdDSA está integrada y los archivos de release se firman.

## Eliminaciones

- Se eliminó el espacio `OpenAI Reset Alert`, junto con sus notificaciones, estado de monitorización y ajustes relacionados.

## Notas

- Las versiones creadas antes de incluir la clave pública de Sparkle deben instalar esta versión manualmente una vez. Las actualizaciones posteriores se verifican automáticamente.
