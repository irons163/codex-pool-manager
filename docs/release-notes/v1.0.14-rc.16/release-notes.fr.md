# CodexPoolManager v1.0.14-rc.16

Date de publication : 2026-06-18

## Corrections

- Les comptes OAuth ChatGPT conservent désormais le refresh token, l'ID token et la dernière heure de rafraîchissement dans le token vault.
- La synchronisation d'utilisation réessaie une fois après une réponse 401/403, après avoir rafraîchi l'OAuth access token.
- L'import local de auth.json transporte maintenant aussi le refresh token et l'ID token vers les comptes OAuth gérés.
- Lors de la fusion des résultats de synchronisation, un ancien instantané ne remplace plus des identifiants locaux plus récents.

## Notes

- Cette prerelease sert à valider la stabilité du renouvellement automatique des comptes OAuth avant le déploiement stable.
- Aucune migration de relay API key, config.toml ou auth.json n'est requise.
