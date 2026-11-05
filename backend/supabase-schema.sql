-- Audit Cuisine : base multi-restaurants / multi-auditeurs
-- À exécuter une seule fois dans Supabase > SQL Editor.
-- RLS activée, aucune lecture anonyme. Les fonctions SECURITY DEFINER
-- évitent les récursions de politiques sur restaurant_members.

create extension if not exists pgcrypto;

create table if not exists public.restaurants (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 160),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.restaurant_members (
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','auditor','reader')),
  created_at timestamptz not null default now(),
  primary key (restaurant_id, user_id)
);

create table if not exists public.audits (
  id text primary key,
  restaurant_id uuid not null references public.restaurants(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  auditor_name text,
  audit_date date not null default current_date,
  status text not null default 'draft' check (status in ('draft','finalized')),
  payload jsonb not null,
  revision integer not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  finalized_at timestamptz
);

create index if not exists restaurant_members_user_idx on public.restaurant_members(user_id);
create index if not exists audits_restaurant_date_idx on public.audits(restaurant_id, audit_date desc);
create index if not exists audits_updated_at_idx on public.audits(updated_at desc);

create or replace function public.is_restaurant_member(p_restaurant_id uuid)
returns boolean language sql stable security definer
set search_path = '' as $$
  select exists (
    select 1 from public.restaurant_members m
    where m.restaurant_id = p_restaurant_id and m.user_id = (select auth.uid())
  );
$$;

create or replace function public.has_restaurant_role(p_restaurant_id uuid, p_roles text[])
returns boolean language sql stable security definer
set search_path = '' as $$
  select exists (
    select 1 from public.restaurant_members m
    where m.restaurant_id = p_restaurant_id
      and m.user_id = (select auth.uid())
      and m.role = any(p_roles)
  );
$$;

revoke all on function public.is_restaurant_member(uuid) from public;
revoke all on function public.has_restaurant_role(uuid,text[]) from public;
grant execute on function public.is_restaurant_member(uuid) to authenticated;
grant execute on function public.has_restaurant_role(uuid,text[]) to authenticated;

alter table public.restaurants enable row level security;
alter table public.restaurant_members enable row level security;
alter table public.audits enable row level security;

revoke all on public.restaurants from anon, authenticated;
revoke all on public.restaurant_members from anon, authenticated;
revoke all on public.audits from anon, authenticated;
grant select on public.restaurants to authenticated;
grant select on public.restaurant_members to authenticated;
grant select, insert, update, delete on public.audits to authenticated;

drop policy if exists restaurants_member_select on public.restaurants;
create policy restaurants_member_select on public.restaurants
for select to authenticated
using (public.is_restaurant_member(id));

drop policy if exists memberships_member_select on public.restaurant_members;
create policy memberships_member_select on public.restaurant_members
for select to authenticated
using (public.is_restaurant_member(restaurant_id));

drop policy if exists memberships_admin_insert on public.restaurant_members;
create policy memberships_admin_insert on public.restaurant_members
for insert to authenticated
with check (public.has_restaurant_role(restaurant_id, array['admin']::text[]));

drop policy if exists memberships_admin_update on public.restaurant_members;
create policy memberships_admin_update on public.restaurant_members
for update to authenticated
using (public.has_restaurant_role(restaurant_id, array['admin']::text[]))
with check (public.has_restaurant_role(restaurant_id, array['admin']::text[]));

drop policy if exists memberships_admin_delete on public.restaurant_members;
create policy memberships_admin_delete on public.restaurant_members
for delete to authenticated
using (public.has_restaurant_role(restaurant_id, array['admin']::text[]));

drop policy if exists audits_member_select on public.audits;
create policy audits_member_select on public.audits
for select to authenticated
using (public.is_restaurant_member(restaurant_id));

drop policy if exists audits_writer_insert on public.audits;
create policy audits_writer_insert on public.audits
for insert to authenticated
with check (
  created_by = (select auth.uid())
  and public.has_restaurant_role(restaurant_id, array['admin','auditor']::text[])
);

drop policy if exists audits_writer_update on public.audits;
create policy audits_writer_update on public.audits
for update to authenticated
using (
  public.has_restaurant_role(restaurant_id, array['admin']::text[])
  or (status = 'draft' and public.has_restaurant_role(restaurant_id, array['auditor']::text[]))
)
with check (
  public.has_restaurant_role(restaurant_id, array['admin']::text[])
  or public.has_restaurant_role(restaurant_id, array['auditor']::text[])
);

drop policy if exists audits_admin_delete on public.audits;
create policy audits_admin_delete on public.audits
for delete to authenticated
using (public.has_restaurant_role(restaurant_id, array['admin']::text[]));

create or replace function public.audit_before_update()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  new.revision := old.revision + 1;
  if new.status = 'finalized' and old.status <> 'finalized' then
    new.finalized_at := coalesce(new.finalized_at, now());
  elsif new.status = 'draft' then
    new.finalized_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audit_before_update on public.audits;
create trigger trg_audit_before_update
before update on public.audits
for each row execute function public.audit_before_update();

create or replace function public.create_restaurant_with_admin(p_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare new_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentification requise'; end if;
  if p_name is null or length(trim(p_name)) = 0 then raise exception 'Nom du restaurant obligatoire'; end if;
  insert into public.restaurants(name, created_by)
  values (trim(p_name), auth.uid()) returning id into new_id;
  insert into public.restaurant_members(restaurant_id, user_id, role)
  values (new_id, auth.uid(), 'admin');
  return new_id;
end;
$$;
revoke all on function public.create_restaurant_with_admin(text) from public;
grant execute on function public.create_restaurant_with_admin(text) to authenticated;

create or replace function public.add_restaurant_member(p_restaurant_id uuid, p_email text, p_role text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare target_user uuid;
begin
  if not public.has_restaurant_role(p_restaurant_id, array['admin']::text[]) then
    raise exception 'Droits administrateur requis';
  end if;
  if p_role not in ('admin','auditor','reader') then raise exception 'Rôle invalide'; end if;
  select id into target_user from auth.users where lower(email) = lower(trim(p_email)) limit 1;
  if target_user is null then raise exception 'Aucun compte trouvé pour cet e-mail. La personne doit d’abord créer son compte.'; end if;
  insert into public.restaurant_members(restaurant_id,user_id,role)
  values (p_restaurant_id,target_user,p_role)
  on conflict (restaurant_id,user_id) do update set role = excluded.role;
  return target_user;
end;
$$;
revoke all on function public.add_restaurant_member(uuid,text,text) from public;
grant execute on function public.add_restaurant_member(uuid,text,text) to authenticated;
