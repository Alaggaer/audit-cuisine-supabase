# Audit Cuisine v23 — préparation Supabase

Ce dépôt contient les éléments de configuration et le schéma SQL de la version v23. **L'application web complète (`index.html`) n'est pas encore publiée dans ce dépôt.** Ne pas activer GitHub Pages à ce stade.

## Fichiers présents
- `supabase-config.js` : URL et clé publishable du projet Supabase.
- `sw.js` : service worker v23.
- `backend/supabase-schema.sql` : schéma de base de données et politiques RLS.

## À compléter avant publication
1. Ajouter le fichier applicatif complet `index.html` de la livraison v23.
2. Vérifier que le chargement de `supabase-config.js` et du client Supabase est correct.
3. Vérifier l'exécution du schéma SQL dans Supabase.
4. Activer GitHub Pages sur la branche principale, dossier /(root), seulement après ajout de l'application.
5. Tester avec deux comptes distincts et vérifier l'isolation des données via RLS.

## Configuration Supabase
La clé `sb_publishable_` est conçue pour être utilisée côté navigateur. Ne jamais ajouter de clé `sb_secret_`, `service_role` ou mot de passe dans ce dépôt. La sécurité dépend des politiques Row Level Security (RLS).

## Validation
L'exécution réelle du SQL, les paramètres Auth, les tests multi-comptes et les essais iPhone/Safari restent à valider dans l'environnement réel.
