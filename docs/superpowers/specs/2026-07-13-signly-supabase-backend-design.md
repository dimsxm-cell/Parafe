# Signly — Intégration backend Supabase (Documents, Auth, Storage)

## Contexte

Signly est actuellement une application front-end statique (HTML/CSS/JS, déployée sur Vercel via `Signly/index.html` et `Signly/signly-modeles.html`). Rien ne persiste : les documents uploadés, les champs placés (signature, texte, date, etc.) et l'état de l'éditeur vivent uniquement dans un tableau JS en mémoire (`fields`) et disparaissent au rechargement de la page. Il n'existe aucun compte utilisateur — le seul point de contact serveur est un formulaire de beta signup envoyé via Web3Forms.

Le CSP actuel (`Signly/vercel.json`) restreint strictement `connect-src` à `'self'` et `https://api.web3forms.com`, et `script-src` à `'self' 'unsafe-inline' https://cdnjs.cloudflare.com https://unpkg.com`.

## Objectif

Donner à Signly un vrai backend persistant via Supabase pour trois besoins : authentification utilisateurs, stockage des documents uploadés, et base de données pour les documents + leurs champs placés.

## Hors périmètre

La gestion multi-signataires externes (envoi par email, token d'accès, statut de signature par personne) est explicitement exclue de cette phase : l'UI actuelle ne propose qu'une auto-signature de démo (`startDemoSign`/`confirmDemoSign`), il n'existe encore aucun flux d'invitation de signataires. Ce sera une phase 2 distincte, à concevoir une fois le besoin produit confirmé.

## Projet Supabase

- URL : `https://ahmoujwfmtipiojocsin.supabase.co`
- Clé publique (anon) fournie par l'utilisateur — utilisée côté client, protégée par RLS (comportement standard Supabase : cette clé est conçue pour être exposée publiquement).
- Le projet Supabase existe déjà côté utilisateur ; aucune CLI Supabase n'est installée sur la machine de dev. La migration SQL sera livrée sous forme de script à coller dans le SQL Editor du dashboard Supabase (pas d'exécution automatisée depuis cet environnement).

## Schéma de données

Table unique `public.documents`, avec les champs placés stockés en JSONB (pas de table normalisée séparée pour les champs — inutile tant qu'on n'a pas besoin de les requêter individuellement) :

```sql
create table public.documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  original_filename text,
  storage_path text,
  fields jsonb not null default '[]'::jsonb,
  status text not null default 'draft' check (status in ('draft','completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.documents enable row level security;

create policy "select own documents" on public.documents
  for select using (auth.uid() = user_id);
create policy "insert own documents" on public.documents
  for insert with check (auth.uid() = user_id);
create policy "update own documents" on public.documents
  for update using (auth.uid() = user_id);
create policy "delete own documents" on public.documents
  for delete using (auth.uid() = user_id);

create or replace function public.set_updated_at()
returns trigger as $$
begin new.updated_at = now(); return new; end;
$$ language plpgsql;

create trigger documents_set_updated_at
  before update on public.documents
  for each row execute function public.set_updated_at();
```

`fields` reprend directement la structure déjà utilisée par le tableau JS `fields` côté client (`type`, `page`, position, style, `required`, `value`, etc.) — aucune transformation de format nécessaire entre l'éditeur et la base.

## Storage

- Bucket privé `documents` (pas d'accès public).
- Policies sur `storage.objects` restreignant chaque utilisateur à son propre préfixe de chemin `{user_id}/...`, via `(storage.foldername(name))[1] = auth.uid()::text`, pour `select`/`insert`/`update`/`delete`.

## Authentification

- Email/mot de passe via Supabase Auth, confirmation email activée (réglage par défaut Supabase — comportement sécurisé, pas de configuration additionnelle nécessaire).
- L'UI réutilise le système de modal déjà présent dans `index.html` pour ajouter les écrans login/signup, plutôt que d'introduire un nouveau pattern.

## Intégration client

- Ajout de `supabase-js` via `unpkg` (déjà whitelisté dans `script-src`), pas de nouveau domaine à autoriser pour les scripts.
- Mise à jour de `Signly/vercel.json` : ajout de `https://ahmoujwfmtipiojocsin.supabase.co` à `connect-src` (nécessaire pour les appels REST/Auth/Storage vers Supabase).
- Initialisation du client Supabase avec l'URL + la clé anon (constantes, pas de secret à protéger côté client).
- Quand un utilisateur connecté charge/édite un document dans l'éditeur, le document et ses `fields` sont sauvegardés en base (upload du fichier source vers Storage + insert/update de la ligne `documents`) au lieu de rester uniquement en mémoire. Au retour sur le site, l'utilisateur retrouve la liste de ses documents.

## Gestion des erreurs

- Erreurs d'auth (identifiants invalides, rate-limit Supabase) affichées via les patterns de message existants dans l'UI.
- Échecs d'upload (taille, réseau) affichés de façon similaire, sans bloquer l'usage démo sans compte (l'éditeur reste utilisable en mode anonyme/local comme aujourd'hui pour un visiteur non connecté).

## Vérification

Pas de suite de tests automatisés sur ce projet (site statique). Vérification manuelle :
1. Exécuter le script SQL dans le SQL Editor Supabase, confirmer la création de la table, des policies et du bucket.
2. Créer deux comptes de test via l'UI, uploader un document sur chacun, confirmer qu'aucun des deux ne voit les documents de l'autre (RLS).
3. Uploader un document, placer des champs, recharger la page connecté : confirmer que le document et ses champs sont bien restaurés depuis Supabase.
