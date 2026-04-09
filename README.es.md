# Codex Pool Manager

Aplicación para macOS para gestionar múltiples cuentas de Codex, cambiar rápidamente la cuenta activa y ver el uso en un solo panel.

Idiomas: [English](README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md)

## Captura de pantalla

(Captura con datos mock de prueba)

![OpenAI Reset Alert](docs/images/openai-reset-alert.png)

## Funcionalidades

- Gestión de pool multi-cuenta
- Cambio rápido de cuenta activa
- Panel de uso (incluye ventanas de cuentas de pago)
- Espacio OpenAI Reset Alert (monitoreo de señales de reset anticipado en cuentas de pago)
- Importación local de cuentas OAuth
- Copia de seguridad y restauración de datos locales del pool
- Interfaz multilingüe

## Espacios de trabajo

- OpenAI Reset Alert: rastrea reset semanal y reset de 5 horas en cuentas de pago, y alerta si ocurre antes de lo esperado.

## Estructura del proyecto

- `CodexPoolManager/`: código fuente de la app
- `CodexPoolManagerTests/`: pruebas unitarias
- `CodexPoolManagerUITests/`: pruebas UI
- `.github/workflows/release-dmg.yml`: workflow de release DMG
- `scripts/build_and_notarize_dmg.sh`: script de build + notarize

## Requisitos

- macOS
- Xcode 16+

## Ejecución local

```bash
open CodexPoolManager.xcodeproj
```

En Xcode, usa el scheme `CodexPoolManager` para compilar y ejecutar.

## Release DMG

Para release CI notarized DMG, consulta [RELEASE_DMG.md](RELEASE_DMG.md).
