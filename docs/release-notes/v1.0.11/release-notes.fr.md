# CodexPoolManager v1.0.11

Date de publication : 2026-06-08

## Nouveautés principales

- Ajout des comptes relais avec API key pour basculer manuellement Codex CLI vers des providers relais utilisant une clé API.
- Séparation plus claire des parcours d’authentification : comptes OAuth / abonnement et comptes relais avec API key.
- Ajout d’un mode de conservation de l’historique qui garde visible l’historique Codex existant tout en envoyant les requêtes API vers la Base URL du relais.
- Correction du retour d’un compte relais vers un compte abonnement afin de restaurer proprement les métadonnées OAuth et la configuration provider.
- Les comptes relais avec API key sont placés en fin de liste et exclus de la synchronisation d’usage ainsi que du basculement automatique.
- Amélioration du formulaire relais : Base URL est maintenant un champ principal obligatoire, le format API a une explication intégrée, et Base URL reste vide par défaut.
- Ajout des traductions de l’interface des comptes relais et des notes de version.

## Notes

- Les comptes relais avec API key ne fournissent pas les données d’usage d’un abonnement ChatGPT ; ils sont donc uniquement disponibles en basculement manuel.
- Si le mode de conservation de l’historique est activé, il s’applique lors du prochain basculement vers un compte relais.
- Aucune migration manuelle n’est requise.
