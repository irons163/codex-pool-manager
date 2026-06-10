# CodexPoolManager v1.0.14

Date de publication : 2026-06-10

## Corrections

- Diagnostic renforcé pour l'authentification relay API key : version/build de l'app, longueurs reçues par le login service et étapes d'écriture auth.json, sans exposer la valeur de l'API key.
- La clé d'API du token vault est désormais transmise directement à la requête de changement de compte relais, afin qu'un état SwiftUI obsolète ou masqué ne fasse plus passer une clé existante pour manquante.
- Les comptes à clé d'API relais enregistrent désormais leur clé dans le coffre de jetons dès l'ajout, de sorte que basculer vers un compte relais juste après l'avoir créé n'échoue plus avec une erreur « clé d'API manquante ».
- Empêché `save()` de purger le coffre de jetons. Auparavant, un instantané en mémoire obsolète ou vide (par exemple une sauvegarde au démarrage) pouvait supprimer définitivement des clés d'API relais et ChatGPT (OAuth) encore valides, sans récupération possible car l'instantané persisté est masqué. Les jetons ne sont désormais supprimés que via la suppression explicite d'un compte ou d'un groupe.
- Résolution directe des API key relais depuis le token vault actif par ID de compte avant le changement, afin qu'un snapshot masqué ne soit plus interprété comme une API key manquante.
- Restauration des API key relais depuis le token vault persistant avant le changement de compte lorsque l'état en mémoire du dashboard ne contient que le snapshot masqué.
- Le changement de compte relais API key écrit désormais directement le `auth.json` API-key de Codex au lieu d'invoquer Codex CLI via stdin, ce qui évite les échecs de transmission stdin propres aux builds release qui faisaient passer une clé existante pour manquante.
- Renforcement du passage aux comptes relais API key en prenant un instantané des données du compte, du provider et de l'API key avant le flux async. Cette correction cible le crash observé dans la build release v1.0.13.
- Déplacement du calcul d'état du formulaire relais API key hors du rendu SwiftUI body afin d'éviter des trims de chaînes supplémentaires pendant les mises à jour de la vue.
- Ajout d'un journal de diagnostic de changement relais sans données sensibles : il enregistre les ID de compte, les longueurs de jeton et les étapes du changement sans stocker les valeurs d'API key, afin de localiser précisément les rapports release-only où la clé semble manquante.

## Notes

- Aucune migration de compte, API key, auth.json ou config.toml n'est requise.
- Cette prerelease sert à valider la hotfix du changement de compte relais API key avant le déploiement stable.
- GitHub Release inclut maintenant les dSYM correspondants afin de faciliter le diagnostic des crashs release avec des journaux symboliqués.
