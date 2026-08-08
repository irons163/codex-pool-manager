# CodexPoolManager v1.0.18

Date de sortie : 2026-08-09

## Corrections

- La connexion OAuth lit désormais le ChatGPT Account ID depuis la revendication JWT imbriquée OpenAI (`https://api.openai.com/auth.chatgpt_account_id`).
- La synchronisation et le basculement de compte peuvent récupérer un Account ID manquant à partir des jetons id/access stockés.
- L’e-mail de profil imbriqué dans les claims OpenAI est reconnu lors de la connexion.
