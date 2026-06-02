create extension if not exists pgcrypto;

create table if not exists public.chat_rooms (
  id uuid primary key default gen_random_uuid(),
  name text,
  room_type text not null default 'dm',
  type text not null default 'dm',
  created_by uuid references auth.users(id) on delete set null,
  last_message text default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.chat_rooms
  add column if not exists name text,
  add column if not exists room_type text not null default 'dm',
  add column if not exists type text not null default 'dm',
  add column if not exists created_by uuid references auth.users(id) on delete set null,
  add column if not exists last_message text default '',
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create table if not exists public.chat_room_members (
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  sender_id uuid references auth.users(id) on delete set null,
  content text,
  message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.chat_messages
  add column if not exists sender_id uuid references auth.users(id) on delete set null,
  add column if not exists content text,
  add column if not exists message text,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create table if not exists public.chat_message_reads (
  message_id uuid not null references public.chat_messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

create index if not exists chat_room_members_user_idx
  on public.chat_room_members(user_id);

create index if not exists chat_room_members_room_idx
  on public.chat_room_members(room_id);

create index if not exists chat_messages_room_created_idx
  on public.chat_messages(room_id, created_at);

create index if not exists chat_messages_sender_idx
  on public.chat_messages(sender_id);

create index if not exists chat_rooms_updated_idx
  on public.chat_rooms(updated_at desc);

create or replace function public.is_chat_room_member(
  target_room_id uuid,
  target_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.chat_room_members crm
    where crm.room_id = target_room_id
      and crm.user_id = target_user_id
  );
$$;

create or replace function public.touch_chat_room()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.chat_rooms
  set
    updated_at = now(),
    last_message = coalesce(new.content, new.message, last_message)
  where id = new.room_id;

  return new;
end;
$$;

drop trigger if exists trg_touch_chat_room_on_message on public.chat_messages;

create trigger trg_touch_chat_room_on_message
after insert on public.chat_messages
for each row
execute function public.touch_chat_room();

create or replace function public.get_or_create_dm(other_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  existing_room_id uuid;
  new_room_id uuid;
begin
  if current_user_id is null then
    raise exception 'not authenticated';
  end if;

  if other_user_id is null then
    raise exception 'other_user_id required';
  end if;

  if other_user_id = current_user_id then
    raise exception 'cannot create dm with self';
  end if;

  select room.id
  into existing_room_id
  from public.chat_rooms room
  join public.chat_room_members mine
    on mine.room_id = room.id
   and mine.user_id = current_user_id
  join public.chat_room_members other_member
    on other_member.room_id = room.id
   and other_member.user_id = other_user_id
  where coalesce(room.room_type, room.type, 'dm') = 'dm'
  order by room.created_at asc
  limit 1;

  if existing_room_id is not null then
    return existing_room_id;
  end if;

  insert into public.chat_rooms (
    name,
    room_type,
    type,
    created_by,
    last_message,
    updated_at
  )
  values (
    null,
    'dm',
    'dm',
    current_user_id,
    '',
    now()
  )
  returning id into new_room_id;

  insert into public.chat_room_members (room_id, user_id)
  values
    (new_room_id, current_user_id),
    (new_room_id, other_user_id)
  on conflict do nothing;

  return new_room_id;
end;
$$;

alter table public.chat_rooms enable row level security;
alter table public.chat_room_members enable row level security;
alter table public.chat_messages enable row level security;
alter table public.chat_message_reads enable row level security;

drop policy if exists chat_rooms_select_member on public.chat_rooms;
create policy chat_rooms_select_member
on public.chat_rooms
for select
to authenticated
using (public.is_chat_room_member(id, auth.uid()));

drop policy if exists chat_rooms_insert_auth on public.chat_rooms;
create policy chat_rooms_insert_auth
on public.chat_rooms
for insert
to authenticated
with check (created_by = auth.uid() or created_by is null);

drop policy if exists chat_rooms_update_member on public.chat_rooms;
create policy chat_rooms_update_member
on public.chat_rooms
for update
to authenticated
using (public.is_chat_room_member(id, auth.uid()))
with check (public.is_chat_room_member(id, auth.uid()));

drop policy if exists chat_room_members_select_related on public.chat_room_members;
create policy chat_room_members_select_related
on public.chat_room_members
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_chat_room_member(room_id, auth.uid())
);

drop policy if exists chat_room_members_insert_creator on public.chat_room_members;
create policy chat_room_members_insert_creator
on public.chat_room_members
for insert
to authenticated
with check (
  user_id = auth.uid()
  or exists (
    select 1
    from public.chat_rooms room
    where room.id = room_id
      and room.created_by = auth.uid()
  )
);

drop policy if exists chat_room_members_delete_self_or_creator on public.chat_room_members;
create policy chat_room_members_delete_self_or_creator
on public.chat_room_members
for delete
to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1
    from public.chat_rooms room
    where room.id = room_id
      and room.created_by = auth.uid()
  )
);

drop policy if exists chat_messages_select_member on public.chat_messages;
create policy chat_messages_select_member
on public.chat_messages
for select
to authenticated
using (public.is_chat_room_member(room_id, auth.uid()));

drop policy if exists chat_messages_insert_member on public.chat_messages;
create policy chat_messages_insert_member
on public.chat_messages
for insert
to authenticated
with check (
  sender_id = auth.uid()
  and public.is_chat_room_member(room_id, auth.uid())
);

drop policy if exists chat_messages_update_sender on public.chat_messages;
create policy chat_messages_update_sender
on public.chat_messages
for update
to authenticated
using (sender_id = auth.uid())
with check (sender_id = auth.uid());

drop policy if exists chat_message_reads_select_member on public.chat_message_reads;
create policy chat_message_reads_select_member
on public.chat_message_reads
for select
to authenticated
using (
  exists (
    select 1
    from public.chat_messages message
    where message.id = message_id
      and public.is_chat_room_member(message.room_id, auth.uid())
  )
);

drop policy if exists chat_message_reads_upsert_self on public.chat_message_reads;
create policy chat_message_reads_upsert_self
on public.chat_message_reads
for all
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

grant execute on function public.is_chat_room_member(uuid, uuid) to authenticated;
grant execute on function public.get_or_create_dm(uuid) to authenticated;

do $$
begin
  if exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) then
    begin
      alter publication supabase_realtime add table public.chat_rooms;
    exception
      when duplicate_object then null;
    end;

    begin
      alter publication supabase_realtime add table public.chat_room_members;
    exception
      when duplicate_object then null;
    end;

    begin
      alter publication supabase_realtime add table public.chat_messages;
    exception
      when duplicate_object then null;
    end;

    begin
      alter publication supabase_realtime add table public.chat_message_reads;
    exception
      when duplicate_object then null;
    end;
  end if;
end $$;
