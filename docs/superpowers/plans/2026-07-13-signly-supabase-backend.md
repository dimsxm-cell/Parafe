# Signly Supabase Backend Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Signly a persistent Supabase backend — authentication, document/field storage, and file storage — replacing the current fully in-memory, non-persistent demo behavior.

**Architecture:** Signly is a single static HTML file (`Signly/index.html`, no build step, no bundler) deployed to Vercel. We add `supabase-js` via a pinned CDN script tag, wire it to an existing Supabase project, and extend the existing inline `<script>` block with auth (login/signup modal) and persistence (save on submit, list on demand) logic. No new files are introduced except the SQL migration script, following the existing single-file pattern rather than splitting into a build pipeline.

**Tech Stack:** Vanilla JS, Supabase (Postgres + Auth + Storage), `@supabase/supabase-js` v2 (UMD build via unpkg), Vercel (static hosting + CSP headers in `vercel.json`).

## Global Constraints

- No automated test framework exists in this repo (pure static HTML/CSS/JS, no `package.json`, no test runner). All verification steps in this plan are manual: browser dev tools/console, the Supabase dashboard Table/Auth/Storage editors, and the SQL Editor.
- Supabase project URL: `https://ahmoujwfmtipiojocsin.supabase.co`
- Supabase anon/public key: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFobW91andmbXRpcGlvam9jc2luIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM5Mzg4NTcsImV4cCI6MjA5OTUxNDg1N30.TYqKA9kBdNULEEeonW1DiLnBvXsqNO7d7j8PVZ-9Yoo` (safe to expose client-side — protected by RLS, this is the Supabase-documented public key).
- `supabase-js` must be loaded pinned to `@supabase/supabase-js@2.110.3` from `https://unpkg.com/@supabase/supabase-js@2.110.3/dist/umd/supabase.js` with Subresource Integrity `sha384-sihuiVHG7vyEIuePVbLI4QpHu1dbhCZe4Zqp0FuqnFeEnyIhF3koyXoBZyfbFsYs` (verified against the actual file contents), matching the SRI pattern already used for `pdf.js`, `mammoth`, and `pdf-lib` in this file.
- Any new external domain used for `connect-src` in `Signly/vercel.json`'s CSP must be added — the CSP currently only allows `'self'` and `https://api.web3forms.com` for `connect-src`.
- Multi-signer external workflow (inviting other people to sign, per-signer tokens/status) is explicitly out of scope for this plan — see the design spec `docs/superpowers/specs/2026-07-13-signly-supabase-backend-design.md`.
- Follow existing code conventions: vanilla JS inline in `Signly/index.html`, French UI copy, existing CSS class names (`modal-overlay`, `form-group`, `btn-primary`, `modal-icon-btn`, `nav-cta`) reused rather than duplicated.
- Executing the SQL migration (Task 1) requires access to the user's Supabase dashboard SQL Editor — no database credentials are available to an agentic worker in this environment, so that specific step must be performed by the human user, who then reports the verification query output back before the plan continues.

---

### Task 1: Supabase schema migration (table, RLS, storage bucket & policies)

**Files:**
- Create: `Signly/supabase/schema.sql`

**Interfaces:**
- Produces: a `public.documents` table with columns `id, user_id, title, original_filename, storage_path, fields (jsonb), status, created_at, updated_at`, RLS policies scoping all access to `auth.uid() = user_id`, and a private `documents` Storage bucket with per-user-folder policies. Task 4 and Task 5 read/write this table and bucket via `supabaseClient.from('documents')` and `supabaseClient.storage.from('documents')`.

- [ ] **Step 1: Write the migration SQL file**

Create `Signly/supabase/schema.sql`:

```sql
-- Signly — Supabase schema: documents table, RLS, storage bucket & policies

create table if not exists public.documents (
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

drop policy if exists "select own documents" on public.documents;
create policy "select own documents" on public.documents
  for select using (auth.uid() = user_id);

drop policy if exists "insert own documents" on public.documents;
create policy "insert own documents" on public.documents
  for insert with check (auth.uid() = user_id);

drop policy if exists "update own documents" on public.documents;
create policy "update own documents" on public.documents
  for update using (auth.uid() = user_id);

drop policy if exists "delete own documents" on public.documents;
create policy "delete own documents" on public.documents
  for delete using (auth.uid() = user_id);

create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists documents_set_updated_at on public.documents;
create trigger documents_set_updated_at
  before update on public.documents
  for each row execute function public.set_updated_at();

insert into storage.buckets (id, name, public)
values ('documents', 'documents', false)
on conflict (id) do nothing;

drop policy if exists "select own files" on storage.objects;
create policy "select own files" on storage.objects
  for select using (bucket_id = 'documents' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "insert own files" on storage.objects;
create policy "insert own files" on storage.objects
  for insert with check (bucket_id = 'documents' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "update own files" on storage.objects;
create policy "update own files" on storage.objects
  for update using (bucket_id = 'documents' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "delete own files" on storage.objects;
create policy "delete own files" on storage.objects
  for delete using (bucket_id = 'documents' and (storage.foldername(name))[1] = auth.uid()::text);
```

- [ ] **Step 2: Ask the human user to run the migration**

This step cannot be automated from this environment (no database credentials available). Ask the user to:
1. Open `https://ahmoujwfmtipiojocsin.supabase.co` → SQL Editor.
2. Paste the full contents of `Signly/supabase/schema.sql`.
3. Click "Run".

- [ ] **Step 3: Verify via SQL Editor**

Ask the user to run this verification query in the same SQL Editor and paste back the output:

```sql
select tablename, rowsecurity from pg_tables where schemaname = 'public' and tablename = 'documents';
select policyname from pg_policies where schemaname = 'public' and tablename = 'documents' order by policyname;
select id, public from storage.buckets where id = 'documents';
select policyname from pg_policies where schemaname = 'storage' and tablename = 'objects' order by policyname;
```

Expected output:
- Row 1: `documents | true` (RLS enabled)
- 4 policy names: `delete own documents`, `insert own documents`, `select own documents`, `update own documents`
- Row: `documents | false` (bucket exists, not public)
- 4 policy names: `delete own files`, `insert own files`, `select own files`, `update own files`

- [ ] **Step 4: Commit**

```bash
git add Signly/supabase/schema.sql
git commit -m "Add Supabase schema migration for documents table and storage"
```

---

### Task 2: Wire supabase-js into the front-end and update CSP

**Files:**
- Modify: `Signly/vercel.json`
- Modify: `Signly/index.html:1832` (add script tag), `Signly/index.html:1836` (add client init)

**Interfaces:**
- Consumes: none (foundational task).
- Produces: a global `supabaseClient` (initialized `SupabaseClient` instance) available to all later inline `<script>` code in `index.html`. Task 3, 4, 5 call `supabaseClient.auth.*`, `supabaseClient.from('documents')`, and `supabaseClient.storage.from('documents')`.

- [ ] **Step 1: Update the CSP in `Signly/vercel.json`**

Change the `connect-src` directive to also allow the Supabase project:

```json
          "value": "default-src 'self'; script-src 'self' 'unsafe-inline' https://cdnjs.cloudflare.com https://unpkg.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data: blob:; connect-src 'self' https://api.web3forms.com https://ahmoujwfmtipiojocsin.supabase.co; worker-src 'self' blob: https://cdnjs.cloudflare.com; frame-ancestors 'none'; base-uri 'self'; object-src 'none'; form-action 'self' https://api.web3forms.com"
```

(Only the `connect-src` segment changes — `'self' https://api.web3forms.com` becomes `'self' https://api.web3forms.com https://ahmoujwfmtipiojocsin.supabase.co`.)

- [ ] **Step 2: Add the `supabase-js` script tag**

In `Signly/index.html`, immediately after the existing `pdf-lib` script tag (currently the line reading `<script src="https://unpkg.com/pdf-lib@1.17.1/dist/pdf-lib.min.js" ...></script>`), add:

```html
<script src="https://unpkg.com/@supabase/supabase-js@2.110.3/dist/umd/supabase.js" integrity="sha384-sihuiVHG7vyEIuePVbLI4QpHu1dbhCZe4Zqp0FuqnFeEnyIhF3koyXoBZyfbFsYs" crossorigin="anonymous"></script>
```

- [ ] **Step 3: Initialize the Supabase client**

In the same file, right after the existing block:

```js
if (window.pdfjsLib) {
  pdfjsLib.GlobalWorkerOptions.workerSrc = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';
}
```

add:

```js
const SUPABASE_URL = 'https://ahmoujwfmtipiojocsin.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFobW91andmbXRpcGlvam9jc2luIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM5Mzg4NTcsImV4cCI6MjA5OTUxNDg1N30.TYqKA9kBdNULEEeonW1DiLnBvXsqNO7d7j8PVZ-9Yoo';
const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
```

- [ ] **Step 4: Verify the client loads**

Run a local static server from the `Signly` directory and open the page:

```bash
cd Signly && npx --yes serve -l 4173
```

Open `http://localhost:4173` in a browser, open the dev console, and type:

```js
typeof supabaseClient
```

Expected: `"object"` (not `"undefined"`), and no red console errors mentioning `supabase` or a failed script load. Note: the custom CSP headers in `vercel.json` only apply once deployed on Vercel, not on this local server — this step only confirms the script loads and the client constructs successfully.

- [ ] **Step 5: Commit**

```bash
git add Signly/vercel.json Signly/index.html
git commit -m "Wire supabase-js client into Signly front-end"
```

---

### Task 3: Auth modal — sign up, log in, log out

**Files:**
- Modify: `Signly/index.html` (CSS before `</style>` at line 1114, HTML after the document-editor modal's closing `</div>` at line 1359, nav HTML before the `nav-cta` button at line 1128, JS after the Supabase client init added in Task 2)

**Interfaces:**
- Consumes: `supabaseClient` (from Task 2).
- Produces: global `let currentUser` (the Supabase `User` object or `null`), and functions `openAuthModal(mode)`, `closeAuthModal()`, `handleNavAuthClick()`, `updateAuthUI(user)` used by Task 4 (`persistDocument` checks `currentUser`) and Task 5 (`openDocsListModal` requires `currentUser` to be signed in for RLS to return rows).

- [ ] **Step 1: Add auth modal and "Mes documents" nav-item CSS**

In `Signly/index.html`, immediately before the `</style>` closing tag (currently preceded by the `@media (max-width: 760px) { ... }` modal rules block), add:

```css
.auth-modal {
  background: #fff; border-radius: 1rem; width: 100%; max-width: 380px;
  padding: 1.5rem; box-shadow: 0 30px 80px -20px rgba(18,23,43,.35);
}
.auth-modal-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 1rem; }
.auth-modal-tabs { display: flex; gap: .5rem; margin-bottom: 1.1rem; border-bottom: 1px solid var(--bd); }
.auth-tab { flex: 1; background: none; border: none; padding: .6rem 0; font-size: .82rem; font-weight: 600; color: var(--gray); border-bottom: 2px solid transparent; }
.auth-tab.active { color: var(--champ); border-bottom-color: var(--champ); }
.auth-error { background: rgba(239,68,68,.08); color: #EF4444; font-size: .78rem; padding: .6rem .75rem; border-radius: .5rem; margin-bottom: 1rem; }
.nav-auth-btn { background: none; border: none; font-size: .82rem; font-weight: 600; color: var(--ivory); opacity: .72; margin-right: .75rem; }
.nav-auth-btn:hover { opacity: 1; }
.docs-list-modal { background: #fff; border-radius: 1rem; width: 100%; max-width: 460px; max-height: 70vh; overflow-y: auto; padding: 1.5rem; box-shadow: 0 30px 80px -20px rgba(18,23,43,.35); }
.docs-list-item { display: flex; justify-content: space-between; align-items: center; padding: .75rem 0; border-bottom: 1px solid var(--bd); font-size: .85rem; }
.docs-list-empty { color: var(--gray); font-size: .85rem; text-align: center; padding: 1.5rem 0; }
```

- [ ] **Step 2: Add auth modal and docs-list modal HTML**

Immediately after the document-editor modal's closing `</div>` (the `</div>` that closes `<div class="modal-overlay" id="modalOverlay" ...>`), add:

```html
<!-- MODALE AUTHENTIFICATION -->
<div class="modal-overlay" id="authModalOverlay" onclick="if(event.target===this) closeAuthModal()">
  <div class="auth-modal">
    <div class="auth-modal-header">
      <div class="modal-brand">Paraf<span>é</span></div>
      <button type="button" class="modal-icon-btn" title="Fermer" onclick="closeAuthModal()">✕</button>
    </div>
    <div class="auth-modal-tabs">
      <button type="button" class="auth-tab active" id="authTabLogin" onclick="setAuthMode('login')">Se connecter</button>
      <button type="button" class="auth-tab" id="authTabSignup" onclick="setAuthMode('signup')">Créer un compte</button>
    </div>
    <div id="authError" class="auth-error" style="display:none"></div>
    <div class="form-group">
      <label>Email</label>
      <input type="email" id="authEmail" placeholder="ton@email.fr">
    </div>
    <div class="form-group">
      <label>Mot de passe</label>
      <input type="password" id="authPassword" placeholder="••••••••" minlength="6">
    </div>
    <button type="button" class="btn-primary" id="authSubmitBtn" style="width:100%" onclick="submitAuthForm()">Se connecter</button>
  </div>
</div>

<!-- MODALE MES DOCUMENTS -->
<div class="modal-overlay" id="docsListModalOverlay" onclick="if(event.target===this) closeDocsListModal()">
  <div class="docs-list-modal">
    <div class="auth-modal-header">
      <div class="modal-brand">Mes documents</div>
      <button type="button" class="modal-icon-btn" title="Fermer" onclick="closeDocsListModal()">✕</button>
    </div>
    <div id="docsListBody"><div class="docs-list-empty">Chargement...</div></div>
  </div>
</div>
```

- [ ] **Step 3: Add nav buttons**

Immediately before the existing `<button class="nav-cta" onclick="scrollToCTA()">Rejoindre la beta</button>` line, add:

```html
  <button type="button" class="nav-auth-btn" id="navAuthBtn" onclick="handleNavAuthClick()">Se connecter</button>
  <button type="button" class="nav-auth-btn" id="navDocsBtn" onclick="openDocsListModal()" style="display:none">Mes documents</button>
```

- [ ] **Step 4: Add auth JS logic**

Immediately after the `supabaseClient` initialization added in Task 2, add:

```js
// ── AUTHENTIFICATION ─────────────────────────────────────
let currentUser = null;
let authMode = 'login';

function openAuthModal(mode) {
  setAuthMode(mode);
  document.getElementById('authEmail').value = '';
  document.getElementById('authPassword').value = '';
  document.getElementById('authError').style.display = 'none';
  document.getElementById('authModalOverlay').classList.add('show');
  document.body.style.overflow = 'hidden';
}
function closeAuthModal() {
  document.getElementById('authModalOverlay').classList.remove('show');
  document.body.style.overflow = '';
}
function setAuthMode(mode) {
  authMode = mode;
  document.getElementById('authTabLogin').classList.toggle('active', mode === 'login');
  document.getElementById('authTabSignup').classList.toggle('active', mode === 'signup');
  document.getElementById('authSubmitBtn').textContent = mode === 'login' ? 'Se connecter' : 'Créer un compte';
  document.getElementById('authError').style.display = 'none';
}
async function submitAuthForm() {
  const email = document.getElementById('authEmail').value.trim();
  const password = document.getElementById('authPassword').value;
  const errorEl = document.getElementById('authError');
  errorEl.style.display = 'none';
  if (!email || !password) {
    errorEl.textContent = 'Email et mot de passe requis.';
    errorEl.style.display = 'block';
    return;
  }
  const btn = document.getElementById('authSubmitBtn');
  const originalLabel = btn.textContent;
  btn.disabled = true;
  btn.textContent = 'Patiente...';
  const { error } = authMode === 'login'
    ? await supabaseClient.auth.signInWithPassword({ email, password })
    : await supabaseClient.auth.signUp({ email, password });
  btn.disabled = false;
  btn.textContent = originalLabel;
  if (error) {
    errorEl.textContent = error.message;
    errorEl.style.display = 'block';
    return;
  }
  closeAuthModal();
}
function handleNavAuthClick() {
  if (currentUser) {
    supabaseClient.auth.signOut();
  } else {
    openAuthModal('login');
  }
}
function updateAuthUI(user) {
  currentUser = user;
  const navAuthBtn = document.getElementById('navAuthBtn');
  const navDocsBtn = document.getElementById('navDocsBtn');
  navAuthBtn.textContent = user ? 'Se déconnecter' : 'Se connecter';
  navDocsBtn.style.display = user ? 'inline-block' : 'none';
}
supabaseClient.auth.onAuthStateChange((_event, session) => updateAuthUI(session ? session.user : null));
supabaseClient.auth.getSession().then(({ data }) => updateAuthUI(data.session ? data.session.user : null));
```

- [ ] **Step 5: Verify in the browser**

Using the same local server from Task 2 Step 4:
1. Reload the page, click "Se connecter", switch to the "Créer un compte" tab, enter a test email (e.g. `test1@example.com`) and a password of at least 6 characters, submit.
2. Expected: the modal closes, and the nav button now reads "Se déconnecter"; "Mes documents" becomes visible.
3. In the Supabase dashboard → Authentication → Users, confirm the new user appears.
4. Click "Se déconnecter". Expected: nav button reverts to "Se connecter", "Mes documents" hides.
5. Click "Se connecter" again and sign back in with the same credentials. Expected: succeeds, same UI update as step 2.

- [ ] **Step 6: Commit**

```bash
git add Signly/index.html
git commit -m "Add sign up, log in, and log out UI backed by Supabase Auth"
```

---

### Task 4: Persist documents on submit

**Files:**
- Modify: `Signly/index.html` (state declarations near line 1892-1896, `openUploadForm` near line 1901, new `persistDocument` function, `submitUploadForm` near line 1920)

**Interfaces:**
- Consumes: `supabaseClient`, `currentUser` (Task 2, 3); existing globals `fields` (array of placed-field objects), `docState` (object with `storagePath` now added), `currentUploadFile` (the uploaded `File`).
- Produces: `let currentDocumentId` (uuid string or `null`) and `async function persistDocument(status)`, called from `submitUploadForm()`.

- [ ] **Step 1: Add `currentDocumentId` state**

In `Signly/index.html`, change:

```js
let currentUploadFile = null;
let docState = null;
let fields = [];
let fieldIdSeq = 1;
```

to:

```js
let currentUploadFile = null;
let currentDocumentId = null;
let docState = null;
let fields = [];
let fieldIdSeq = 1;
```

- [ ] **Step 2: Reset `currentDocumentId` when a new upload starts**

In `openUploadForm`, change:

```js
async function openUploadForm(file) {
  currentUploadFile = file;
  fields = [];
  fieldIdSeq = 1;
```

to:

```js
async function openUploadForm(file) {
  currentUploadFile = file;
  currentDocumentId = null;
  fields = [];
  fieldIdSeq = 1;
```

- [ ] **Step 3: Add the `persistDocument` function**

Immediately before `function submitUploadForm() {`, add:

```js
async function persistDocument(status) {
  if (!currentUser || !currentUploadFile) return;
  try {
    let storagePath = docState && docState.storagePath;
    if (!storagePath) {
      storagePath = `${currentUser.id}/${Date.now()}_${currentUploadFile.name}`;
      const { error: uploadError } = await supabaseClient.storage
        .from('documents')
        .upload(storagePath, currentUploadFile, { upsert: false });
      if (uploadError) throw uploadError;
      if (docState) docState.storagePath = storagePath;
    }
    const payload = {
      user_id: currentUser.id,
      title: prettifyFileName(currentUploadFile.name),
      original_filename: currentUploadFile.name,
      storage_path: storagePath,
      fields,
      status,
    };
    if (currentDocumentId) {
      const { error } = await supabaseClient.from('documents').update(payload).eq('id', currentDocumentId);
      if (error) throw error;
    } else {
      const { data, error } = await supabaseClient.from('documents').insert(payload).select('id').single();
      if (error) throw error;
      currentDocumentId = data.id;
    }
  } catch (err) {
    console.error('Sauvegarde du document — échec :', err);
  }
}
```

- [ ] **Step 4: Call `persistDocument` from `submitUploadForm`**

Change:

```js
function submitUploadForm() {
  closeUploadForm();
```

to:

```js
function submitUploadForm() {
  persistDocument('completed');
  closeUploadForm();
```

- [ ] **Step 5: Verify in the browser**

Using the same local server:
1. Log in as the test user created in Task 3.
2. Upload a PDF via the drop zone, open the digital form, place at least one "Signature" field on the document.
3. Click "↗ Envoyer pour signature" in the modal topbar.
4. In the Supabase dashboard → Table Editor → `documents`, confirm a new row exists with `status = 'completed'`, `title` matching the uploaded filename, and `fields` containing a JSON array with one object (`type: "signature"`).
5. In the Supabase dashboard → Storage → `documents` bucket, confirm a file exists under a folder named with the test user's UUID.

- [ ] **Step 6: Commit**

```bash
git add Signly/index.html
git commit -m "Persist uploaded documents and placed fields to Supabase on submit"
```

---

### Task 5: "Mes documents" list, and end-to-end RLS verification

**Files:**
- Modify: `Signly/index.html` (new `openDocsListModal` / `closeDocsListModal` functions, placed after the auth functions added in Task 3)

**Interfaces:**
- Consumes: `supabaseClient`, `currentUser` (Task 2, 3), the `documents` table populated by Task 4.
- Produces: `async function openDocsListModal()`, `function closeDocsListModal()`, wired to the `#navDocsBtn` button added in Task 3.

- [ ] **Step 1: Add the docs-list functions**

Immediately after the auth JS block added in Task 3 (after the `supabaseClient.auth.getSession()...` line), add:

```js
// ── MES DOCUMENTS ─────────────────────────────────────────
async function openDocsListModal() {
  document.getElementById('docsListModalOverlay').classList.add('show');
  document.body.style.overflow = 'hidden';
  const bodyEl = document.getElementById('docsListBody');
  bodyEl.innerHTML = '<div class="docs-list-empty">Chargement...</div>';
  const { data, error } = await supabaseClient
    .from('documents')
    .select('id, title, status, created_at')
    .order('created_at', { ascending: false });
  if (error) {
    bodyEl.innerHTML = `<div class="docs-list-empty">Erreur : ${error.message}</div>`;
    return;
  }
  if (!data.length) {
    bodyEl.innerHTML = '<div class="docs-list-empty">Aucun document enregistré pour l\'instant.</div>';
    return;
  }
  bodyEl.innerHTML = data.map(doc => `
    <div class="docs-list-item">
      <span>${doc.title}</span>
      <span>${doc.status === 'completed' ? '✓ Envoyé' : 'Brouillon'} · ${new Date(doc.created_at).toLocaleDateString('fr-FR')}</span>
    </div>
  `).join('');
}
function closeDocsListModal() {
  document.getElementById('docsListModalOverlay').classList.remove('show');
  document.body.style.overflow = '';
}
```

- [ ] **Step 2: Verify the list for the existing test user**

Using the same local server, logged in as the test user from Task 3/4:
1. Click "Mes documents" in the nav.
2. Expected: the modal lists the document persisted in Task 4, showing its title, "✓ Envoyé", and today's date.
3. Close the modal.

- [ ] **Step 3: Verify RLS isolation with a second account**

1. Sign out, sign up a second test account (e.g. `test2@example.com`).
2. Click "Mes documents".
3. Expected: "Aucun document enregistré pour l'instant." — confirms the first user's document is not visible to the second user (RLS is enforced).
4. Upload and submit a document as this second user, open "Mes documents" again, confirm only this user's own document appears (not the first user's).

- [ ] **Step 4: Verify session persistence across reload**

1. While signed in as the second test user, reload the page (`F5`).
2. Expected: the nav button still reads "Se déconnecter" without needing to log in again (Supabase persists the session in `localStorage` by default), and "Mes documents" still shows only this user's document.

- [ ] **Step 5: Commit**

```bash
git add Signly/index.html
git commit -m "Add Mes documents list backed by Supabase, with RLS-isolated access"
```
