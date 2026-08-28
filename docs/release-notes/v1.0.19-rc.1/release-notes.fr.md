# CodexPoolManager v1.0.19-rc.1

Date de sortie : 2026-08-28

## Corrections

- Le basculement de compte ferme désormais Codex avant de réécrire les identifiants, pour qu’une session en cours ne soit pas traitée comme révoquée.
- Le basculement écrit les jetons refresh/id du compte cible au lieu de laisser ceux du compte précédent dans `auth.json`.
- Les identifiants sont aussi mis à jour dans le trousseau Codex et le miroir `current_account` utilisé par les versions récentes.

## Note de prerelease

- Cette prerelease valide le basculement de compte avec le nouveau flux de connexion Codex avant la version stable.
