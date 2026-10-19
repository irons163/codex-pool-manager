# CodexPoolManager v1.0.21-rc.2

Date de publication : 2026-10-19

## Corrections

- Résout les liens symboliques avant de parcourir les dossiers de sessions, afin de rétablir les statistiques lorsque les données Codex sont stockées sur un disque externe ou dans un dossier lié.
- Ne parcourt chaque dossier physique qu'une seule fois lorsque sessions et archived_sessions pointent vers le même emplacement, évitant les doublons et l'atteinte prématurée des limites de lecture.
- Conserve les corrections des identifiants d'espace de travail et les badges « Entreprise » de rc.1.

## Note de préversion

- Les fichiers volumineux peuvent toujours atteindre les limites de lecture existantes. Les statistiques partielles restent explicitement signalées.
