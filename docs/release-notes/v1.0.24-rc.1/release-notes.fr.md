# CodexPoolManager v1.0.24-rc.1

Date de sortie : 2026-11-05

## Nouvelles fonctionnalités

- Ajout du mode de bascule « Ordre défini » : réorganisez les comptes dans la page Stratégie d'exécution et alternez dans cet ordre, en revenant au premier après le dernier.
- Le seuil de bascule s'applique aussi à ce mode ; les comptes exclus de la synchronisation et les comptes Relay sont ignorés automatiquement.

## Améliorations

- Dans le tri par usage restant, les comptes expirés ou exclus de la synchronisation passent sous les comptes sains, tandis que le compte actif reste en premier.
- Les comptes professionnels utilisent un badge violet pour les distinguer des comptes personnels.

## Corrections

- Distinction entre identifiants révoqués et autres erreurs de synchronisation, avec récupération automatique après rotation du jeton.

## Suppressions

- Suppression de l'espace `OpenAI Reset Alert`, de ses notifications, de son état de surveillance et de ses réglages associés.
