# CodexPoolManager v1.0.21-rc.4

Date de publication : 2026-10-19

## Corrections

- Lit les journaux de sessions jusqu'à leur fin au début de l'analyse, sans arrêt à 128 MiB par fichier, pour récupérer les événements situés à la fin des fichiers volumineux.
- Lit par petits blocs et ignore rapidement le contenu des conversations tout en conservant une mémoire tampon limitée pour les métadonnées et la possibilité d'annuler.
- Identifie les types réels de métadonnées plutôt que des mots-clés dans les sorties d'outils, évitant les faux avertissements lorsque celles-ci mentionnent token_count.
- Conserve l'isolation des membres, les badges Entreprise et la prise en charge des dossiers de sessions liés.

## Note de préversion

- Les fichiers illisibles, les sources de bifurcation non résolues et les limites d'événements continuent de signaler des statistiques incomplètes.
