# CodexPoolManager v1.0.16

Date de sortie : 2026-07-11

## Points forts

- Les dates d'expiration des crédits de réinitialisation utilisent désormais directement les valeurs `expires_at` exactes renvoyées par l'API de détails du compte Codex, au lieu d'être estimées à partir de la dernière synchronisation réussie.
- Les cartes de compte, le tableau de bord de la barre des menus et les alertes de réinitialisation affichent les dates exactes de l'API lorsqu'elles sont disponibles.
- Les dates fournies par l'API n'affichent plus l'avertissement de date estimée ; celui-ci apparaît uniquement lorsque l'estimation de secours est nécessaire.
- La provenance des dates est conservée dans les instantanés de compte afin de distinguer les dates exactes de l'API des estimations après un redémarrage.
- Le README et toutes les localisations prises en charge expliquent désormais de manière cohérente les dates exactes de l'API et les estimations de secours.

## Fiabilité et compatibilité

- L'estimation existante est utilisée automatiquement lorsque les détails du compte ou les dates d'expiration ne peuvent pas être récupérés.
- Les instantanés créés par les versions précédentes restent compatibles et sont traités avec prudence comme des données estimées.
- Cette version stable regroupe les changements validés dans v1.0.15-rc.1.
