# Codex Pool Manager

Codex Pool Manager est une app macOS pour gérer un pool de comptes Codex/OpenAI OAuth depuis un seul panneau de contrôle.

Elle permet de :
- suivre quota et restant par compte,
- changer rapidement le compte actif,
- faire une rotation automatique via une politique intelligente,
- surveiller l'état via Widget et barre de menu,
- conserver des flux backup/export pour la récupération.

Langues : [English](README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md)

## Sommaire

1. [Captures](#captures)
2. [Fonctionnalités clés](#fonctionnalités-clés)
3. [Fonctionnement du switch intelligent](#fonctionnement-du-switch-intelligent)
4. [Widget + barre de menu](#widget--barre-de-menu)
5. [Authentification et import de comptes](#authentification-et-import-de-comptes)
6. [Espaces de travail](#espaces-de-travail)
7. [Installation](#installation)
8. [Build depuis les sources](#build-depuis-les-sources)
9. [Pipeline Release DMG](#pipeline-release-dmg)
10. [Structure du projet](#structure-du-projet)
11. [Tests](#tests)
12. [Dépannage](#dépannage)
13. [Sécurité et confidentialité](#sécurité-et-confidentialité)
14. [Contribution](#contribution)

## Captures

Toutes les captures ci-dessous utilisent des données mock ou non sensibles.

### Tableau principal (Dark, Mock)

![Main Dashboard (Dark, Mock Data)](docs/images/app-screenshot.png)

### Vue d'ensemble (Light, Mock)

![Header Overview (Light, Mock Data)](docs/images/dashboard-light.png)

### Barre de menu (Mock)

![Menu Bar Status](docs/images/menu-bar.png)

### Widget (état vide, Mock)

![Widget Empty State](docs/images/widget-empty-state.png)

### OpenAI Reset Alert (Mock)

![OpenAI Reset Alert](docs/images/openai-reset-alert.png)

## Fonctionnalités clés

### 1) Gestion du pool de comptes

- Ajouter, éditer, dupliquer et supprimer des comptes.
- Gérer les groupes (`Add`, `Rename`, `Delete`).
- La suppression d'un groupe supprime aussi ses comptes.
- Tri et layout pour les pools de grande taille.
- Statistiques (`Accounts`, `Available`, `Pool Usage`) dédupliquées pour éviter les doubles comptages.

### 2) Plusieurs modes de switch

- `Intelligent` : sélection automatique du meilleur compte selon capacité restante et seuils.
- `Manual` : conserve le compte choisi manuellement.
- `Focus` : verrouille le compte courant et désactive la rotation intelligente.

### 3) Sync usage et diagnostic

- Sync usage Codex/OpenAI pour tous les comptes éligibles.
- Gestion des exclusions (token manquant, account id manquant, erreur API/réseau).
- Affichage de l'heure de dernier sync réussi et des erreurs.
- JSON usage brut + logs de switch pour diagnostic.

### 4) Flux OAuth sign-in

- OAuth sign-in in-app puis import direct.
- Flux manuel : copier l'URL d'autorisation, coller l'URL callback, puis importer.
- Découverte locale des fichiers auth sur chemins standards.
- Import des OAuth sessions/accounts locaux dans le pool.

### 5) Intégration desktop

- Notifications macOS (échec/reprise sync, low usage, résultats auto-switch).
- Menu bar extra avec résumé du restant.
- Extension Widget macOS pour vue rapide.

### 6) Backup et restore

- Export snapshot JSON.
- Export refetchable snapshot (sensible ; inclut des champs nécessaires au re-fetch).
- Import snapshot JSON pour migration/recovery.

### 7) UI et localisation

- Dark mode + Light mode.
- Changement de langue dans les settings.
- Formatage des dates selon la locale (app/widget).

### 8) Analytique d'usage et planification Schedule

- Workspace `Schedule` dédié à la planification des resets sur plusieurs comptes.
- Analyse quotidienne/hebdomadaire de l'usage pour comprendre les habitudes.
- Vue de couverture pour repérer les créneaux non couverts entre resets.
- Courbes par compte, événements de seuil et résumés d'anomalies.
- Export des données analytiques en JSON/CSV.

### 9) Monitoring OpenAI reset

- Espace dédié `OpenAI Reset Alert` pour les comptes payants.
- Surveillance conjointe des resets hebdo et 5h.
- Détection des resets plus tôt que prévu (tolérance configurable).
- Notifications desktop et historique d'événements.

## Fonctionnement du switch intelligent

### Éligibilité des comptes

Seuls les comptes **non exclus du sync/scheduling** sont candidats au switch automatique.

Exemples d'exclusion :
- API token manquant,
- ChatGPT account id manquant,
- statut d'erreur de sync.

### Logique paid vs non-paid

- Compte non payant : ratio restant hebdo (`remainingUnits / quota`).
- Compte payant (par défaut) : **restant 5h**.
- Cas spécial compte payant : si restant hebdo = `0%`, la semaine devient la référence.

### Sélection du candidat

Le moteur choisit le meilleur candidat avec le ratio restant intelligent le plus élevé.

Les comptes avec restant hebdo `<= 0` ne sont pas candidats.

### Conditions de déclenchement

En mode `Intelligent`, switch seulement si toutes les conditions sont vraies :

1. candidat valide,
2. compte actif sous le seuil,
3. candidat meilleur que le compte courant,
4. cooldown écoulé.

### Comportement Focus

En mode `Focus`, le compte courant est verrouillé.

Aucun auto-switch intelligent n'est exécuté en focus.

### Seuil low-usage séparé

Deux seuils distincts :

- seuil intelligent : **autorise le switch**,
- seuil low remaining alert : **affiche alerte/notification**.

Ces deux seuils sont indépendants.

## Widget + barre de menu

### Widget

- Lit le snapshot via le bridge local exposé par l'app principale.
- Si aucun snapshot n'est disponible, affiche un état vide explicite.
- Politique de refresh :
  - ~`60s` si snapshot présent,
  - ~`10s` si snapshot absent.

### Barre de menu

- Titre compact (restant %, restant 5h paid, âge de mise à jour).
- Contenu détaillé (compte actif, resets, âge de mise à jour).
- Refresh périodique (~15s) + refresh manuel.

## Authentification et import de comptes

### Chemins de découverte locale

- `~/.codex/auth.json`
- `~/.config/codex/auth.json`
- `~/.openai/auth.json`

### Public OAuth client

Le flux public client est supporté par défaut, avec possibilité d'utiliser votre propre client OAuth.

### Flux callback manuel

Si le callback navigateur ne peut pas être finalisé in-app :

1. cliquer `Copy URL and Manual sign in`,
2. terminer le sign-in dans le navigateur,
3. coller l'URL callback,
4. cliquer `Import`.

## Espaces de travail

### Authentication

- panneau OAuth sign-in
- Advanced OAuth parameters
- scan/import des comptes OAuth locaux

### Runtime Strategy

- sélecteur de mode (`Intelligent`, `Manual`, `Focus`)
- seuil intelligent de switch
- seuil low-usage alert
- panneau de recommandation

### Schedule

- vue timeline des resets sur les comptes gérés
- synthèse d'usage quotidien/hebdomadaire
- détection des gaps de couverture pour planifier l'utilisation
- courbes par compte + événements de seuil/anomalies
- export analytique (`Copy JSON`, `Export CSV`, `Export JSON`)

### OpenAI Reset Alert

- tracking des cibles reset des comptes payants
- configuration de la tolérance d'early-reset
- résumé + enregistrements des signaux détectés
- alertes desktop + gestion des événements

### Settings

- comportement au lancement
- auto-sync toggle + intervalle
- langue
- apparence (system/dark/light)

### Safety

- contrôles backup/export/import
- surface de diagnostic raw data/logs

## Installation

### Option A : Télécharger le DMG prébuild depuis Releases

- `CodexPoolManager-<version>-apple-silicon.dmg`
- `CodexPoolManager-<version>-intel.dmg`

Choisir le DMG adapté à l'architecture du Mac.

### Option B : Exécuter depuis les sources avec Xcode

Voir section suivante.

## Build depuis les sources

### Prérequis

- macOS
- Xcode 16+

### Étapes

```bash
cd /path/to/AIAgentPool
open CodexPoolManager.xcodeproj
```

Dans Xcode :

1. sélectionner le scheme `CodexPoolManager`,
2. choisir le Mac local comme destination,
3. Build and Run.

Pour tester le widget, vérifier que les targets concernées sont signées avec la même Team.

## Pipeline Release DMG

Packaging DMG + notarization automatiques configurés dans :

- `.github/workflows/release-dmg.yml`
- `scripts/build_and_notarize_dmg.sh`

### Points clés

- build `arm64` et `x86_64`,
- nommage des artifacts par version/tag release (pas par hash),
- signature Developer ID Application,
- notarize + staple de chaque DMG,
- upload vers artifacts CI + GitHub Release.

### Secrets GitHub requis

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`
- `APPLE_API_PRIVATE_KEY_BASE64`

Voir [RELEASE_DMG.md](RELEASE_DMG.md) pour la configuration détaillée.

## Structure du projet

```text
AIAgentPool/
├─ CodexPoolManager/                 # App macOS principale
├─ CodexPoolWidget/                  # Extension Widget
├─ CodexPoolWidgetHost/              # Host compagnon pour bridge/tests widget
├─ Domain/Pool/                      # État core, règles de switch, snapshot
├─ Features/PoolDashboard/           # UI + coordinateurs de flux
├─ Infrastructure/Auth/              # OAuth, accès auth file, switch services
├─ Infrastructure/Usage/             # Client/service de sync usage
├─ CodexPoolManagerTests/            # Tests unitaires
├─ CodexPoolManagerUITests/          # Tests UI
├─ .github/workflows/release-dmg.yml # Workflow release
└─ scripts/build_and_notarize_dmg.sh # Script DMG local/CI
```

## Tests

Dans Xcode, ou via CLI :

```bash
xcodebuild \
  -project CodexPoolManager.xcodeproj \
  -scheme CodexPoolManager \
  -destination 'platform=macOS' \
  test
```

## Dépannage

### "Syncing..." reste bloqué

- Vérifier la disponibilité réseau/API.
- Vérifier le callout Sync Error.
- Vérifier token et account id des comptes actifs.
- Relancer un sync manuel après quelques secondes.

### Le widget affiche "No snapshot available"

- Ouvrir CodexPoolManager au moins une fois (le bridge est publié par l'app principale).
- Attendre quelques secondes puis refresh du widget.
- Vérifier que localhost loopback n'est pas bloqué par firewall/règles réseau.

### Le scan OAuth local ne trouve rien

- Utiliser `Choose auth.json` et accorder l'accès manuellement.
- Vérifier la présence des données auth dans un des chemins connus.

### Aucun switch en mode Intelligent

- Vérifier si le compte courant est sous le seuil.
- Vérifier l'intervalle de cooldown.
- Vérifier l'éligibilité des candidats et leurs valeurs restantes.
- En mode Focus, le switch intelligent est désactivé par design.

## Sécurité et confidentialité

- Les exports refetchable peuvent contenir des données sensibles.
- Ne pas partager de logs/exports bruts sans redaction.
- Stocker les snapshots internes dans un emplacement sécurisé.
- Gérer les credentials OAuth/client selon votre politique sécurité.

## Contribution

Issues et PR bienvenus.

Bon scope de PR :
- une seule évolution de comportement par PR,
- couverture de test pour logique domain/coordinator,
- captures avant/après pour les changements UI.

---

Si ce projet vous aide, n'hésitez pas à mettre une étoile au repo.
