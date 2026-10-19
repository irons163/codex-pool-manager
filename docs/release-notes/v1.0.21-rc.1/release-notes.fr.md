# CodexPoolManager v1.0.21-rc.1

Date de publication : 2026-10-19

## Modifications

- Sépare les espaces personnels et professionnels partageant une adresse e-mail grâce à leur identifiant de compte, sans réutiliser des identifiants sur la seule base de l'adresse e-mail.
- Vérifie les identifiants Codex locaux plus récents avant de mettre à jour le pool et conserve les identifiants vérifiés si une synchronisation ultérieure échoue ou est annulée.
- Arrête la synchronisation et le changement de compte lorsque les identifiants appartiennent à un autre espace, avec une invitation claire à se reconnecter. Vérifie aussi l'espace lors du renouvellement des jetons.
- Affiche le badge « Entreprise » pour les comptes Team, Business et Enterprise dans les cartes, la barre de menus et la planification.
- Ajoute l'analyse des sessions Codex locales : utilisation des jetons, taux de cache, coût estimé, tendances, activité et détails par modèle et requête.

## Note de préversion

- Cette préversion valide la séparation des espaces et les badges professionnels avant la version stable v1.0.21. Les identifiants révoqués nécessitent toujours une nouvelle connexion.
