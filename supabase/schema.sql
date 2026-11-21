-- TextChat schema (already applied to the Supabase project). Prefixed tc_ so it
-- can't clash with other tables.

create table public.tc_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  name text not null default '',
  created_at timestamptz not null default now()
);

create table public.tc_chats (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references auth.users(id) on delete cascade,
  user_b uuid not null references auth.users(id) on delete cascade,
  last_message text,
  last_time timestamptz,
  created_at timestamptz not null default now(),
  constraint tc_chats_ordered check (user_a < user_b),
  constraint tc_chats_unique unique (user_a, user_b)
);
create index tc_chats_user_b_idx on public.tc_chats(user_b);

create table public.tc_messages (
  id bigint generated always as identity primary key,
  chat_id uuid not null references public.tc_chats(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index tc_messages_chat_idx on public.tc_messages(chat_id, created_at desc);

alter table public.tc_profiles enable row level security;
alter table public.tc_chats enable row level security;
alter table public.tc_messages enable row level security;

create policy tc_profiles_select on public.tc_profiles for select to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1 from public.tc_chats c
      where (c.user_a = (select auth.uid()) and c.user_b = tc_profiles.id)
         or (c.user_b = (select auth.uid()) and c.user_a = tc_profiles.id)
    )
  );
create policy tc_profiles_update on public.tc_profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy tc_chats_select on public.tc_chats for select to authenticated
  using ((select auth.uid()) in (user_a, user_b));

create policy tc_messages_select on public.tc_messages for select to authenticated
  using (exists (select 1 from public.tc_chats c
                 where c.id = tc_messages.chat_id
                   and (select auth.uid()) in (c.user_a, c.user_b)));
create policy tc_messages_insert on public.tc_messages for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and exists (select 1 from public.tc_chats c
                where c.id = tc_messages.chat_id
                  and (select auth.uid()) in (c.user_a, c.user_b))
  );

create function public.tc_handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.tc_profiles (id, email, name)
  values (new.id, lower(new.email), coalesce(new.raw_user_meta_data->>'name', ''))
  on conflict (id) do nothing;
  return new;
end $$;
revoke execute on function public.tc_handle_new_user() from public, anon, authenticated;

create trigger tc_on_auth_user_created
  after insert on auth.users
  for each row execute function public.tc_handle_new_user();

create function public.tc_touch_chat() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.tc_chats
     set last_message = new.body, last_time = new.created_at
   where id = new.chat_id;
  return new;
end $$;
revoke execute on function public.tc_touch_chat() from public, anon, authenticated;

create trigger tc_messages_touch_chat
  after insert on public.tc_messages
  for each row execute function public.tc_touch_chat();

create function public.tc_find_user(p_email text)
returns table (id uuid, email text, name text)
language sql security definer set search_path = '' stable as $$
  select p.id, p.email, p.name from public.tc_profiles p
  where p.email = lower(trim(p_email)) and auth.uid() is not null
  limit 1;
$$;
revoke execute on function public.tc_find_user(text) from public, anon;
grant execute on function public.tc_find_user(text) to authenticated;

create function public.tc_start_chat(p_other uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  a uuid; b uuid; cid uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_other is null or p_other = me then raise exception 'invalid user'; end if;
  if not exists (select 1 from public.tc_profiles where id = p_other) then
    raise exception 'user not found';
  end if;
  a := least(me, p_other); b := greatest(me, p_other);
  insert into public.tc_chats (user_a, user_b) values (a, b)
  on conflict (user_a, user_b) do nothing;
  select id into cid from public.tc_chats where user_a = a and user_b = b;
  return cid;
end $$;
revoke execute on function public.tc_start_chat(uuid) from public, anon;
grant execute on function public.tc_start_chat(uuid) to authenticated;

alter publication supabase_realtime add table public.tc_messages;
alter publication supabase_realtime add table public.tc_chats;

-- ---- Read receipts (added later) ----
alter table public.tc_messages add column if not exists read_at timestamptz;

create or replace function public.tc_mark_read(p_chat uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not exists (
    select 1 from public.tc_chats c
    where c.id = p_chat and auth.uid() in (c.user_a, c.user_b)
  ) then
    raise exception 'not a member of this chat';
  end if;
  update public.tc_messages
     set read_at = now()
   where chat_id = p_chat
     and sender_id <> auth.uid()
     and read_at is null;
end $$;
revoke execute on function public.tc_mark_read(uuid) from public, anon;
grant execute on function public.tc_mark_read(uuid) to authenticated;
