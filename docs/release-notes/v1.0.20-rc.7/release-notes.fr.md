# CodexPoolManager v1.0.20-rc.7

Date de publication : 2026-10-05

## Modifications

- Enregistre les identifiants OAuth renouvelés avant de récupérer l’utilisation, afin qu’une erreur ou une annulation ultérieure ne fasse pas perdre les nouveaux jetons.
- Distingue le rejet confirmé des identifiants, les erreurs réseau, les limites de requêtes, les erreurs de service et l’absence de jeton de renouvellement, au lieu de signaler toute erreur comme une connexion expirée.
- Empêche un résultat de renouvellement tardif d’écraser des identifiants réimportés ou de restaurer un compte supprimé.
- Remplace le badge OpenAI Reset Alert par « Bientôt retiré » dans toutes les langues prises en charge. La fonctionnalité reste disponible dans cette préversion.
- Ajoute des tests de régression pour la rotation des jetons, la classification des erreurs, l’annulation et les résultats de renouvellement obsolètes.

## Note de préversion

- Cette préversion valide la fiabilité du renouvellement OAuth avant la version stable 1.0.20. Des identifiants effectivement révoqués nécessitent toujours une nouvelle connexion.
