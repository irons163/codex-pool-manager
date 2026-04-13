# Codex Pool Manager

Codex Pool Manager es una app para macOS para operar un pool de cuentas Codex/OpenAI OAuth desde un solo panel de control.

Te ayuda a:
- seguir cuota y restante por cuenta,
- cambiar rápido la cuenta activa,
- rotar cuentas automáticamente con política inteligente,
- monitorear estado desde Widget y barra de menú,
- mantener flujos de backup/export para recuperación.

Idiomas: [English](README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md)

## Índice

1. [Capturas](#capturas)
2. [Funciones clave](#funciones-clave)
3. [Cómo funciona el cambio inteligente](#cómo-funciona-el-cambio-inteligente)
4. [Widget + barra de menú](#widget--barra-de-menú)
5. [Autenticación e importación de cuentas](#autenticación-e-importación-de-cuentas)
6. [Espacios de trabajo](#espacios-de-trabajo)
7. [Instalación](#instalación)
8. [Compilar desde código fuente](#compilar-desde-código-fuente)
9. [Pipeline de Release DMG](#pipeline-de-release-dmg)
10. [Estructura del proyecto](#estructura-del-proyecto)
11. [Pruebas](#pruebas)
12. [Solución de problemas](#solución-de-problemas)
13. [Notas de seguridad y privacidad](#notas-de-seguridad-y-privacidad)
14. [Contribuir](#contribuir)

## Capturas

Todas las capturas usan datos mock o no sensibles.

### Dashboard principal (Dark, Mock)

![Main Dashboard (Dark, Mock Data)](docs/images/app-screenshot.png)

### Resumen superior (Light, Mock)

![Header Overview (Light, Mock Data)](docs/images/dashboard-light.png)

### Estado en barra de menú (Mock)

![Menu Bar Status](docs/images/menu-bar.png)

### Widget (estado vacío, Mock)

![Widget Empty State](docs/images/widget-empty-state.png)

### OpenAI Reset Alert (Mock)

![OpenAI Reset Alert](docs/images/openai-reset-alert.png)

## Funciones clave

### 1) Gestión del pool de cuentas

- Agregar, editar, duplicar y eliminar cuentas.
- Gestionar grupos (`Add`, `Rename`, `Delete`).
- Al borrar un grupo, se eliminan también sus cuentas.
- Orden y layouts para pools grandes.
- Estadísticas (`Accounts`, `Available`, `Pool Usage`) con deduplicación para evitar doble conteo.

### 2) Múltiples modos de cambio

- `Intelligent`: selecciona automáticamente la mejor cuenta según capacidad restante y umbrales.
- `Manual`: mantiene la cuenta elegida manualmente.
- `Focus`: fija la cuenta actual y desactiva la rotación inteligente.

### 3) Sync de uso y diagnóstico

- Sincroniza uso de Codex/OpenAI para cuentas elegibles.
- Maneja exclusiones de sync (token faltante, account id faltante, error API/red).
- Muestra hora del último sync exitoso y detalles de error.
- Incluye JSON de uso en bruto y logs de cambio para diagnóstico.

### 4) Flujos OAuth sign-in

- OAuth sign-in dentro de la app e importación directa.
- Flujo manual: copiar URL de autorización, pegar URL callback e importar.
- Descubrimiento local de auth en rutas comunes.
- Importa OAuth sessions/accounts locales al pool administrado.

### 5) Integración de escritorio

- Notificaciones nativas macOS (fallo/recuperación de sync, low usage, auto-switch).
- Extra de barra de menú con resumen en vivo del restante.
- Widget de macOS para vistazo rápido.

### 6) Backup y restore

- Exportar snapshot JSON.
- Exportar snapshot refetchable (sensible; incluye campos para re-fetch).
- Importar snapshot JSON para migración/recuperación.

### 7) UI y localización

- Dark mode + Light mode.
- Cambio de idioma desde settings.
- Formato de tiempo según locale en app/widget.

### 8) Analítica de uso y planificación en Schedule

- Workspace `Schedule` para planificar resets entre múltiples cuentas.
- Análisis diario/semanal de uso para entender hábitos de consumo.
- Vista de cobertura para detectar ventanas sin cobertura entre resets.
- Líneas de tendencia por cuenta, eventos de umbral y resumen de anomalías.
- Exportación de analítica en JSON/CSV.

### 9) Monitoreo de reset de OpenAI

- Workspace dedicado `OpenAI Reset Alert` para cuentas de pago.
- Monitorea juntos reset semanal y reset de 5 horas.
- Detecta reset anticipado (con tolerancia configurable).
- Notificaciones desktop e historial de eventos.

## Cómo funciona el cambio inteligente

### Elegibilidad de cuentas

Solo cuentas **no excluidas de sync/scheduling** se consideran para cambio automático.

Razones típicas de exclusión:
- falta API token,
- falta ChatGPT account id,
- estado de error de sync.

### Lógica paid vs no-paid

- Cuenta no pagada: usa ratio restante semanal (`remainingUnits / quota`).
- Cuenta pagada (por defecto): usa **restante de 5 horas**.
- Caso especial pagada: si restante semanal = `0%`, se toma semanal como referencia.

### Selección de candidato

El motor elige el mejor candidato por mayor ratio restante inteligente.

Cuentas con restante semanal `<= 0` no son elegibles.

### Condiciones de disparo

En modo `Intelligent`, solo cambia si se cumplen todas:

1. hay candidato válido,
2. la cuenta activa está bajo el umbral,
3. el candidato es mejor que la actual,
4. expiró el cooldown.

### Comportamiento Focus

En `Focus`, la cuenta actual queda fijada.

No hay auto-switch inteligente en Focus.

### Umbral low-usage separado

Hay dos umbrales independientes:

- umbral inteligente: **cuándo se permite cambiar**,
- umbral de low remaining alert: **cuándo mostrar aviso/notificación**.

## Widget + barra de menú

### Widget

- Lee snapshot desde un bridge local expuesto por la app principal.
- Si no hay snapshot, muestra estado vacío amigable.
- Política de refresh:
  - ~`60s` con snapshot,
  - ~`10s` sin snapshot.

### Barra de menú

- Título compacto con estado (restante %, paid 5h left, edad de actualización).
- Menú con detalles de cuenta activa, resets y edad de actualización.
- Refresh periódico (~15s) y refresh manual.

## Autenticación e importación de cuentas

### Rutas de descubrimiento local

- `~/.codex/auth.json`
- `~/.config/codex/auth.json`
- `~/.openai/auth.json`

### Public OAuth client

Por defecto soporta flujo de public client y también parámetros de tu propio OAuth client.

### Flujo callback manual

Si el callback del navegador no puede completarse dentro de la app:

1. clic en `Copy URL and Manual sign in`,
2. completar sign-in en navegador,
3. pegar callback URL,
4. clic en `Import`.

## Espacios de trabajo

### Authentication

- panel OAuth sign-in
- Advanced OAuth parameters
- escaneo/import de cuentas OAuth locales

### Runtime Strategy

- selector de modo (`Intelligent`, `Manual`, `Focus`)
- umbral de cambio inteligente
- umbral de low-usage alert
- panel de recomendación

### Schedule

- vista timeline de resets para cuentas gestionadas
- resumen analítico diario/semanal de uso
- detección de gaps de cobertura para planificar mejor
- líneas por cuenta y eventos de umbral/anomalías
- exportación de analítica (`Copy JSON`, `Export CSV`, `Export JSON`)

### OpenAI Reset Alert

- tracking de objetivos de reset en cuentas de pago
- configuración de tolerancia de early-reset
- resumen y registros de señales detectadas
- alertas desktop y gestión de eventos

### Settings

- comportamiento al iniciar
- toggle e intervalo de auto-sync
- idioma
- apariencia (system/dark/light)

### Safety

- controles de backup/export/import
- superficie de diagnóstico para datos/logs en bruto

## Instalación

### Opción A: Descargar DMG prebuild desde Releases

- `CodexPoolManager-<version>-apple-silicon.dmg`
- `CodexPoolManager-<version>-intel.dmg`

Elige el DMG según la arquitectura de tu Mac.

### Opción B: Ejecutar desde código fuente en Xcode

Ver siguiente sección.

## Compilar desde código fuente

### Requisitos

- macOS
- Xcode 16+

### Pasos

```bash
cd /path/to/AIAgentPool
open CodexPoolManager.xcodeproj
```

En Xcode:

1. seleccionar el scheme `CodexPoolManager`,
2. elegir tu Mac local como destination,
3. Build and Run.

Si también pruebas widget, firma los targets relacionados con la misma Team.

## Pipeline de Release DMG

Empaquetado DMG + notarization automatizado en:

- `.github/workflows/release-dmg.yml`
- `scripts/build_and_notarize_dmg.sh`

### Puntos clave

- build de `arm64` y `x86_64`,
- nombre de artifacts por versión/tag release (no hash),
- firma con certificado Developer ID Application,
- notarize + staple para cada DMG,
- upload a artifacts de workflow y assets de GitHub Release.

### GitHub secrets requeridos

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`
- `APPLE_API_PRIVATE_KEY_BASE64`

Para setup detallado, ver [RELEASE_DMG.md](RELEASE_DMG.md).

## Estructura del proyecto

```text
AIAgentPool/
├─ CodexPoolManager/                 # target principal macOS app
├─ CodexPoolWidget/                  # target widget extension
├─ CodexPoolWidgetHost/              # host companion para bridge/tests del widget
├─ Domain/Pool/                      # estado core, reglas de switch, snapshot model
├─ Features/PoolDashboard/           # UI + coordinadores de flujo
├─ Infrastructure/Auth/              # OAuth, acceso a auth file, servicios de switch
├─ Infrastructure/Usage/             # cliente/servicio de sync de uso
├─ CodexPoolManagerTests/            # tests unitarios
├─ CodexPoolManagerUITests/          # tests UI
├─ .github/workflows/release-dmg.yml # workflow release
└─ scripts/build_and_notarize_dmg.sh # script DMG local/CI
```

## Pruebas

En Xcode o por línea de comandos:

```bash
xcodebuild \
  -project CodexPoolManager.xcodeproj \
  -scheme CodexPoolManager \
  -destination 'platform=macOS' \
  test
```

## Solución de problemas

### "Syncing..." se queda bloqueado

- Confirmar disponibilidad de red/API.
- Revisar callout de Sync Error.
- Verificar token y account id válidos en cuentas activas.
- Reintentar sync manual tras unos segundos.

### Widget muestra "No snapshot available"

- Abrir CodexPoolManager al menos una vez (la app principal publica el bridge).
- Esperar unos segundos y refrescar widget.
- Verificar que firewall/reglas de red no bloqueen localhost loopback.

### El escaneo OAuth local no encuentra nada

- Usar `Choose auth.json` y conceder permiso manualmente.
- Verificar que exista auth en una de las rutas conocidas.

### No cambia cuenta en modo Intelligent

- Revisar si la cuenta actual está bajo el umbral.
- Revisar intervalo de cooldown.
- Revisar elegibilidad de candidatos y valores restantes.
- En Focus, el cambio inteligente está desactivado por diseño.

## Notas de seguridad y privacidad

- Los exports refetchable pueden incluir datos sensibles.
- No compartas logs/exports en bruto sin redacción.
- Guarda snapshots internos en almacenamiento seguro.
- Maneja credenciales OAuth/client según tu política de seguridad.

## Contribuir

Issues y PRs bienvenidos.

Alcance recomendado de PR:
- un cambio de comportamiento por PR,
- cobertura de tests para lógica de domain/coordinator,
- capturas before/after para cambios de UI.

---

Si este proyecto te ayuda, considera darle una estrella al repo.
