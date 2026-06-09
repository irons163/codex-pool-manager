# CodexPoolManager v1.0.14

Date de publication : 2026-06-09

## Corrections

- Renforcement du passage aux comptes relais API key en prenant un instantané des données du compte, du provider et de l'API key avant le flux async. Cette correction cible le crash observé dans la build release v1.0.13.
- Déplacement du calcul d'état du formulaire relais API key hors du rendu SwiftUI body afin d'éviter des trims de chaînes supplémentaires pendant les mises à jour de la vue.

## Notes

- Aucune migration de compte, API key, auth.json ou config.toml n'est requise.
- Cette prerelease sert à valider la hotfix du changement de compte relais API key avant le déploiement stable.
