# Audit Cuisine v23 — multi-restaurants avec Supabase

Application d'audit cuisine multi-établissements, avec authentification Supabase, rôles et synchronisation des audits.

## Fichiers
- `index.html` : application web.
- `supabase-config.js` : configuration publique du projet Supabase.
- `sw.js` : service worker et cache versionné.
- `backend/supabase-schema.sql` : schéma SQL et politiques RLS.

## Déploiement GitHub Pages
1. Dans Settings > Pages, choisir Deploy from a branch, puis la branche principale et le dossier /(root).
2. Vérifier que `index.html`, `supabase-config.js` et `sw.js` sont à la racine.
3. Vérifier l'exécution du schéma SQL dans Supabase.
4. Tester avec deux comptes distincts et confirmer l'isolation des données via RLS.

## Configuration Supabase
La clé `sb_publishable_` est conçue pour être utilisée côté navigateur. Ne jamais ajouter de clé `sb_secret_`, `service_role` ou mot de passe dans ce dépôt.
Les données sont protégées par les politiques Row Level Security (RLS), qui doivent être activées et vérifiées.

## Limites de validation
L'exécution effective du SQL, les paramètres Auth, les tests multi-comptes, ainsi que les essais iPhone/Safari doivent être vérifiés dans l'environnement réel avant une mise en production.
