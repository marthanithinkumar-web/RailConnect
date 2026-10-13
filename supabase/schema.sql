-- RailConnect initial schema (Postgres / Supabase)
-- Run this migration only after creating your own Supabase project.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'RailConnect traveller' check (char_length(display_name) between 2 and 60),
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(nullif(left(trim(new.raw_user_meta_data ->> 'display_name'), 60), ''), 'RailConnect traveller'))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_railconnect on auth.users;
create trigger on_auth_user_created_railconnect
after insert on auth.users
for each row execute procedure public.handle_new_user();

create table if not exists public.journeys (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  origin text not null check (char_length(trim(origin)) between 2 and 100),
  destination text not null check (char_length(trim(destination)) between 2 and 100),
  travel_date date not null,
  travel_style text not null default 'Flexible plans' check (travel_style in ('Flexible plans','Daytime travel','Night travel','First-time route','Group coordination')),
  notes text check (notes is null or char_length(notes) <= 500),
  status text not null default 'active' check (status in ('active','cancelled')),
  created_at timestamptz not null default now(),
  constraint different_cities check (lower(trim(origin)) <> lower(trim(destination))
  )
);
create index if not exists journeys_search_idx on public.journeys (status, travel_date, origin, destination);
create index if not exists journeys_owner_idx on public.journeys (user_id, created_at desc);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  journey_id uuid not null references public.journeys(id) on delete cascade,
  requester_id uuid not null references public.profiles(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint different_conversation_members check (requester_id <> owner_id),
  constraint one_conversation_per_requester_journey unique (journey_id, requester_id)
);
create index if not exists conversations_requester_idx on public.conversations (requester_id, created_at desc);
create index if not exists conversations_owner_idx on public.conversations (owner_id, created_at desc);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists messages_conversation_idx on public.messages (conversation_id, created_at);

-- Keep public profile display names non-sensitive. Never put email or phone in this table.
alter table public.profiles enable row level security;
alter table public.journeys enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;

drop policy if exists "Profiles readable to signed-in users" on public.profiles;
create policy "Public display names readable" on public.profiles for select to anon, authenticated using (true);
drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile" on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

drop policy if exists "Active journeys public read" on public.journeys;
create policy "Active journeys public read" on public.journeys for select to anon, authenticated using (status = 'active' or (select auth.uid()) = user_id);
drop policy if exists "Users create own journeys" on public.journeys;
create policy "Users create own journeys" on public.journeys for insert to authenticated with check (
  (select auth.uid()) = user_id and travel_date >= (now() at time zone 'UTC')::date
);
drop policy if exists "Users update own journeys" on public.journeys;
create policy "Users update own journeys" on public.journeys for update to authenticated
using ((select auth.uid()) = user_id)
with check (
  (select auth.uid()) = user_id
  and (status = 'cancelled' or travel_date >= (now() at time zone 'UTC')::date)
);
drop policy if exists "Users delete own journeys" on public.journeys;
create policy "Users delete own journeys" on public.journeys for delete to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Members read own conversations" on public.conversations;
create policy "Members read own conversations" on public.conversations for select to authenticated using ((select auth.uid()) in (requester_id, owner_id));
drop policy if exists "Requester starts own conversations" on public.conversations;
create policy "Requester starts own conversations" on public.conversations for insert to authenticated with check (
  (select auth.uid()) = requester_id and requester_id <> owner_id
  and exists (select 1 from public.journeys j where j.id = journey_id and j.user_id = owner_id and j.status = 'active')
);
-- Conversation creation is performed through the validated RPC below; clients cannot update membership.
-- Date validation is enforced by RLS as well as the browser, so direct API requests
-- cannot publish a past journey or reactivate one with a past travel date.
drop policy if exists "Members read conversation messages" on public.messages;
create policy "Members read conversation messages" on public.messages for select to authenticated using (
  exists (select 1 from public.conversations c where c.id = conversation_id and (select auth.uid()) in (c.requester_id,c.owner_id))
);
drop policy if exists "Members send messages" on public.messages;
create policy "Members send messages" on public.messages for insert to authenticated with check (
  (select auth.uid()) = sender_id and exists (
    select 1 from public.conversations c where c.id = conversation_id and (select auth.uid()) in (c.requester_id,c.owner_id)
  )
);

create or replace function public.start_conversation(p_journey_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_owner uuid;
  v_id uuid;
begin
  if v_user is null then raise exception 'Sign in to message another traveller.'; end if;
  select user_id into v_owner from public.journeys where id = p_journey_id and status = 'active';
  if v_owner is null then raise exception 'This journey is no longer available.'; end if;
  if v_owner = v_user then raise exception 'You cannot message your own journey.'; end if;
  insert into public.conversations (journey_id, requester_id, owner_id)
  values (p_journey_id, v_user, v_owner)
  on conflict (journey_id, requester_id) do update set journey_id = excluded.journey_id
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.start_conversation(uuid) from public;
grant execute on function public.start_conversation(uuid) to authenticated;

grant select on public.journeys to anon, authenticated;
grant insert, update, delete on public.journeys to authenticated;
grant select on public.profiles to anon, authenticated;
grant update on public.profiles to authenticated;
grant select, insert on public.conversations to authenticated;
grant select, insert on public.messages to authenticated;

-- Existing auth users also receive a profile row (safe to run repeatedly).
insert into public.profiles (id, display_name)
select id, coalesce(nullif(left(trim(raw_user_meta_data ->> 'display_name'),60),''),'RailConnect traveller')
from auth.users on conflict (id) do nothing;
