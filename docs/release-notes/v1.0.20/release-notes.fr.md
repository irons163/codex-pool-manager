# CodexPoolManager v1.0.20

Date de publication : 2026-10-05

Cette version stable regroupe les modifications de la barre de menus, de l’espace de travail et du renouvellement OAuth de v1.0.20-rc.1 à rc.7.

## Améliorations

- Utilise une icône Codex monochrome native de 18 points qui suit l’apparence du système. Le texte d’utilisation est conservé et le temps écoulé en fin de libellé est supprimé.
- Améliore l’affichage de l’élément de la barre de menus au démarrage et élargit la liste des comptes dans son tableau de bord.
- Permet de faire glisser la barre de titre existante de l’espace de travail pour régler la hauteur du panneau entre 10 % et 90 % de la fenêtre. Mémorise la hauteur choisie et affiche un curseur de redimensionnement vertical.
- Ajoute un lien de signalement des problèmes sur GitHub dans les réglages.

## Corrections

- Enregistre les identifiants OAuth renouvelés avant de récupérer l’utilisation, afin qu’une erreur ou une annulation ultérieure ne perde pas les jetons remplacés.
- Distingue les identifiants refusés des erreurs réseau, des limites de requêtes, des erreurs de service et de l’absence de refresh token.
- Empêche un renouvellement terminé tardivement d’écraser des identifiants réimportés ou de restaurer des comptes supprimés.

## Remarques

- Le badge OpenAI Reset Alert affiche désormais « Bientôt retiré » ; la fonctionnalité reste disponible dans cette version.
- Les identifiants révoqués nécessitent toujours une nouvelle connexion.
