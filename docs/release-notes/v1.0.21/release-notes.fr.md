# CodexPoolManager v1.0.21

Date de publication : 2026-10-19

## Améliorations

- Ajout de l’analyse de l’utilisation locale de Codex : tokens, taux de succès du cache, coûts estimés, tendances, historique d’activité et répartition par modèle et requête.
- Affichage d’un badge Business pour les comptes Team, Business et Enterprise dans les cartes, la barre de menus et la planification.
- Maintien de « Signaler un problème » en bas de la barre latérale, avec GitHub et l’envoi d’e-mails dans l’application. Les signalements sont envoyés à `feedback@codexpool.zero2codex.dev` sans ouvrir de logiciel de messagerie.
- L’adresse de réponse est facultative et les versions de l’application et du système sont jointes uniquement si l’option est cochée. Une nouvelle tentative sans modification ne provoque pas d’envoi en double.

## Corrections

- Séparation des espaces personnels et professionnels partageant une adresse e-mail, et distinction des membres d’un même espace lors de la récupération de connexion, de l’importation, du renouvellement des identifiants, de la synchronisation et du changement de compte.
- Une seule carte est mise en évidence comme compte actuel ; les identifiants d’un autre espace ou membre sont refusés.
- Prise en charge des dossiers de sessions liés et lecture complète des gros journaux en ignorant le corps des conversations. Rétablissement des événements manquants et suppression des faux avertissements de statistiques incomplètes.

## Mise à jour

- Si un ancien compte signale un espace ou un utilisateur différent, reconnectez-vous à ce compte pour remplacer ses anciens identifiants en cache.
