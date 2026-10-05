# CodexPoolManager v1.0.20

Fecha de publicación: 2026-10-05

Esta versión estable reúne los cambios de la barra de menús, el espacio de trabajo y la renovación de OAuth desde v1.0.20-rc.1 hasta rc.7.

## Mejoras

- Usa un icono de Codex monocromo nativo de 18 puntos que sigue la apariencia del sistema. Conserva el texto de uso y elimina el tiempo transcurrido al final.
- Mejora la visualización del elemento de la barra de menús al iniciar y amplía la lista de cuentas de su panel.
- Permite arrastrar la barra de título original del espacio de trabajo para ajustar la altura del panel entre el 10 % y el 90 % de la ventana. Recuerda la altura elegida y muestra un cursor de ajuste vertical.
- Añade un enlace para informar de problemas en GitHub desde Ajustes.

## Correcciones

- Guarda las credenciales OAuth renovadas antes de obtener el uso, para evitar perder los tokens rotados si después ocurre un error o una cancelación.
- Distingue las credenciales rechazadas de los fallos de red, los límites de solicitudes, los errores de servicio y la ausencia de refresh token.
- Impide que una renovación completada con retraso sobrescriba credenciales reimportadas o restaure cuentas eliminadas.

## Notas

- La etiqueta de OpenAI Reset Alert ahora dice «Se retirará pronto»; la función sigue disponible en esta versión.
- Las credenciales revocadas aún requieren volver a iniciar sesión.
