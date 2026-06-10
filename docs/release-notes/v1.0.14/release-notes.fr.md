# CodexPoolManager v1.0.14

Date de publication : 2026-06-10

## Corrections

- Empêché `save()` de purger le coffre de jetons. Auparavant, un instantané en mémoire obsolète ou vide (par exemple une sauvegarde au démarrage) pouvait supprimer définitivement des clés d'API relais et ChatGPT (OAuth) encore valides, sans récupération possible car l'instantané persisté est masqué. Les jetons ne sont désormais supprimés que via la suppression explicite d'un compte ou d'un groupe.
- Résolution directe des API key relais depuis le token vault actif par ID de compte avant le changement, afin qu'un snapshot masqué ne soit plus interprété comme une API key manquante.
- Restauration des API key relais depuis le token vault persistant avant le changement de compte lorsque l'état en mémoire du dashboard ne contient que le snapshot masqué.
- Normalisation du payload stdin de l'API key relais avant d'appeler `codex login --with-api-key` : les clés vides sont rejetées avant de lancer Codex CLI, et les clés valides sont envoyées comme bytes indépendants avec un saut de ligne final.
- Renforcement du passage aux comptes relais API key en prenant un instantané des données du compte, du provider et de l'API key avant le flux async. Cette correction cible le crash observé dans la build release v1.0.13.
- Contournement du crash release restant lors du passage à un compte relais en envoyant des bytes d'API key déjà préparés au flux de connexion Codex CLI, au lieu de refaire un trim de la chaîne API key dans la closure async de connexion.
- Déplacement du calcul d'état du formulaire relais API key hors du rendu SwiftUI body afin d'éviter des trims de chaînes supplémentaires pendant les mises à jour de la vue.

## Notes

- Aucune migration de compte, API key, auth.json ou config.toml n'est requise.
- Cette prerelease sert à valider la hotfix du changement de compte relais API key avant le déploiement stable.
- GitHub Release inclut maintenant les dSYM correspondants afin de faciliter le diagnostic des crashs release avec des journaux symboliqués.
