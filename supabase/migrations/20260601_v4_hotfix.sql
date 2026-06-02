-- V4 hotfix: chat open / favorite order / RLS recursion fix

-- favorite 별칭 정렬 오류 수정
drop function if exists public.get_my_friends();
create or replace function public.get_my_friends()
returns table (
  user_id uuid,
  email text,
  nickname text,
  avatar_url text,
  status_message text,
  birthday date,
  favorite boolean,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end as user_id,
    p.email,
    p.nickname,
    p.avatar_url,
    p.status_message,
    p.birthday,
    case when f.requester_id = auth.uid() then coalesce(f.favorite_by_requester, false) else coalesce(f.favorite_by_addressee, false) end as favorite,
    f.created_at
  from public.friendships f
  join public.profiles p
    on p.id = case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
  where f.status = 'accepted'
    and (f.requester_id = auth.uid() or f.addressee_id = auth.uid())
  order by 7 desc, p.nickname asc;
$$;

-- chat_room_members 무한재귀 RLS 제거
do $$
declare
  p record;
begin
  for p in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('chat_room_members', 'chat_rooms', 'chat_messages')
  loop
    execute format('drop policy if exists %I on %I.%I', p.policyname, p.schemaname, p.tablename);
  end loop;
end $$;

drop function if exists public.is_room_member(uuid);
create or replace function public.is_room_member(p_room_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.chat_room_members m
    where m.room_id = p_room_id
      and m.user_id = auth.uid()
  );
$$;

grant execute on function public.is_room_member(uuid) to authenticated;
grant execute on function public.is_room_member(uuid) to anon;

alter table if exists public.chat_room_members enable row level security;
alter table if exists public.chat_rooms enable row level security;
alter table if exists public.chat_messages enable row level security;

create policy chat_room_members_select_safe
on public.chat_room_members
for select
using (user_id = auth.uid() or public.is_room_member(room_id));

create policy chat_room_members_insert_safe
on public.chat_room_members
for insert
with check (auth.uid() is not null);

create policy chat_room_members_update_safe
on public.chat_room_members
for update
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy chat_room_members_delete_safe
on public.chat_room_members
for delete
using (user_id = auth.uid());

create policy chat_rooms_select_safe
on public.chat_rooms
for select
using (public.is_room_member(id));

create policy chat_rooms_insert_safe
on public.chat_rooms
for insert
with check (auth.uid() is not null);

create policy chat_rooms_update_safe
on public.chat_rooms
for update
using (public.is_room_member(id));

create policy chat_messages_select_safe
on public.chat_messages
for select
using (public.is_room_member(room_id));

create policy chat_messages_insert_safe
on public.chat_messages
for insert
with check (sender_id = auth.uid() and public.is_room_member(room_id));

create policy chat_messages_update_safe
on public.chat_messages
for update
using (sender_id = auth.uid());
