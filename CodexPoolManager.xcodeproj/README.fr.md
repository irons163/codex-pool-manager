# Codex Pool Manager

Application macOS pour gérer plusieurs comptes Codex, basculer rapidement le compte actif et suivre l'utilisation depuis un tableau de bord unique.

Langues : [English](README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md)

## Fonctionnalités

- Gestion d'un pool multi-comptes
- Changement rapide du compte actif
- Tableau de bord d'usage (y compris fenêtres des comptes payants)
- Import local de comptes OAuth
- Sauvegarde/restauration des données locales du pool
- Interface multilingue

## Structure du projet

- `CodexPoolManager/` : code source de l'app
- `CodexPoolManagerTests/` : tests unitaires
- `CodexPoolManagerUITests/` : tests UI
- `.github/workflows/release-dmg.yml` : workflow de release DMG
- `scripts/build_and_notarize_dmg.sh` : script build + notarize

## Prérequis

- macOS
- Xcode 16+

## Exécution locale

```bash
open CodexPoolManager.xcodeproj
```

Dans Xcode, utilisez le scheme `CodexPoolManager` pour compiler et lancer.

## Release DMG

Pour la release CI notarized DMG, voir [RELEASE_DMG.md](RELEASE_DMG.md).
