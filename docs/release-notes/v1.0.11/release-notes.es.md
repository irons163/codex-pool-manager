# CodexPoolManager v1.0.11

Fecha de publicación: 2026-06-08

## Cambios destacados

- Se añadieron cuentas relay con API key para cambiar manualmente Codex CLI a providers relay que usan una clave API.
- El flujo de autenticación ahora está separado en dos rutas más claras: cuentas OAuth / suscripción y cuentas relay con API key.
- Se añadió un modo para conservar el historial existente de Codex mientras las solicitudes API se enrutan por la Base URL del relay.
- Se corrigió el cambio de una cuenta relay a una cuenta de suscripción para restaurar correctamente los metadatos OAuth y la configuración del provider.
- Las cuentas relay con API key quedan al final de la lista y se excluyen de la sincronización de uso y del cambio automático.
- Se mejoró el formulario de relay: Base URL ahora es un campo principal obligatorio, el formato API incluye una explicación y Base URL queda vacío por defecto.
- Se añadieron traducciones para la interfaz de cuentas relay y las notas de la versión.

## Notas

- Las cuentas relay con API key no proporcionan datos de uso de una suscripción ChatGPT, por lo que solo admiten cambio manual.
- Si el modo de conservación de historial está activado, se aplicará la próxima vez que cambies a una cuenta relay.
- No se requiere migración manual.
