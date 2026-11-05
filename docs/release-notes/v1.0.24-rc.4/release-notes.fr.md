# CodexPoolManager v1.0.24-rc.4

Date de sortie : 2026-11-05

## Nouvelles fonctionnalités

- Ajout du mode de bascule « Ordre défini » : réorganisez les comptes dans la page Stratégie d'exécution et alternez dans cet ordre, en revenant au premier après le dernier.
- Le seuil de bascule s'applique aussi à ce mode ; les comptes exclus de la synchronisation et les comptes Relay sont ignorés automatiquement.

## Améliorations

- Dans le tri par usage restant, les comptes expirés ou exclus de la synchronisation passent sous les comptes sains, tandis que le compte actif reste en premier.
- Les comptes professionnels utilisent un badge violet pour les distinguer des comptes personnels.
- La liste d'ordre de bascule prend désormais en charge le glisser-déposer ; les boutons haut/bas restent disponibles.
- La liste d'ordre de bascule est désormais triée selon la disponibilité réelle : les comptes sains passent avant ceux épuisés, et les comptes exclus restent en dernier.
- Les lignes affichent maintenant le forfait et l'espace de travail (personnel/organisation), pour distinguer les comptes partageant la même adresse e-mail.

## Corrections

- Distinction entre identifiants révoqués et autres erreurs de synchronisation, avec récupération automatique après rotation du jeton.
- Correction de la vérification des mises à jour Sparkle : la clé publique EdDSA est intégrée et les archives de release sont signées.

## Suppressions

- Suppression de l'espace `OpenAI Reset Alert`, de ses notifications, de son état de surveillance et de ses réglages associés.

## Remarques

- Les versions créées avant l'intégration de la clé publique Sparkle doivent installer cette version manuellement une fois. Les mises à jour suivantes sont vérifiées automatiquement.
