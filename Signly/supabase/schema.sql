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
