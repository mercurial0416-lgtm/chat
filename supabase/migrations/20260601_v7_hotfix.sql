-- v6 hotfix: repair recursive RLS and core RPCs without deleting data
create extension if not exists pgcrypto;

alter table if exists public.profiles
  add column if not exists email text,
  add column if not exists nickname text not null default '익명',
  add column if not exists avatar_url text,
  add column if not exists status_message text default '',
  add column if not exists birthday date,
  add column if not exists dark_mode boolean not null default false,
  add column if not exists font_size text not null default 'normal';

alter table if exists public.friendships
  add column if not exists favorite_by_requester boolean not null default false,
  add column if not exists favorite_by_addressee boolean not null default false;

alter table if exists public.chat_rooms
  add column if not exists room_type text not null default 'direct',
  add column if not exists title text,
  add column if not exists avatar_url text,
  add column if not exists direct_key text,
  add column if not exists created_by uuid,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create unique index if not exists chat_rooms_direct_key_unique_idx on public.chat_rooms(direct_key) where direct_key is not null;

alter table if exists public.chat_room_members
  add column if not exists role text not null default 'member',
  add column if not exists muted boolean not null default false,
  add column if not exists pinned boolean not null default false,
  add column if not exists last_read_at timestamptz,
  add column if not exists joined_at timestamptz not null default now();

alter table if exists public.chat_messages
  add column if not exists message_type text not null default 'text',
  add column if not exists image_url text,
  add column if not exists file_url text,
  add column if not exists file_name text,
  add column if not exists file_size bigint,
  add column if not exists audio_url text,
  add column if not exists reply_to_message_id uuid,
  add column if not exists shared_latitude double precision,
  add column if not exists shared_longitude double precision,
  add column if not exists edited_at timestamptz,
  add column if not exists deleted_at timestamptz;

create table if not exists public.app_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade,
  type text not null default 'general',
  title text not null default '알림',
  body text,
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade,
  endpoint text unique,
  subscription jsonb,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references public.profiles(id) on delete cascade,
  title text not null,
  memo text,
  start_at timestamptz not null,
  end_at timestamptz,
  all_day boolean not null default false,
  color text not null default '#FEE500',
  share_mode text not null default 'private',
  group_room_id uuid references public.chat_rooms(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.work_shift_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  mode text not null default 'normal',
  shift_team int default 1,
  anchor_date date not null default date '2026-01-01',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.location_share_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid references public.profiles(id) on delete cascade,
  receiver_id uuid references public.profiles(id) on delete cascade,
  status text not null default 'pending',
  duration_minutes int not null default 60,
  created_at timestamptz not null default now(),
  responded_at timestamptz
);

create table if not exists public.location_share_sessions (
  id uuid primary key default gen_random_uuid(),
  request_id uuid references public.location_share_requests(id) on delete set null,
  user_a uuid references public.profiles(id) on delete cascade,
  user_b uuid references public.profiles(id) on delete cascade,
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  stopped_at timestamptz
);

create table if not exists public.live_locations (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  latitude double precision not null,
  longitude double precision not null,
  accuracy double precision,
  heading double precision,
  speed double precision,
  updated_at timestamptz not null default now()
);

insert into storage.buckets (id, name, public) values ('chat_uploads', 'chat_uploads', true) on conflict (id) do update set public = true;

do $$
declare p record;
begin
  for p in select schemaname, tablename, policyname from pg_policies where schemaname='public' and tablename in ('chat_room_members','chat_rooms','chat_messages') loop
    execute format('drop policy if exists %I on %I.%I', p.policyname, p.schemaname, p.tablename);
  end loop;
end $$;

drop function if exists public.is_room_member(uuid);
create or replace function public.is_room_member(p_room_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$ select exists(select 1 from public.chat_room_members m where m.room_id=p_room_id and m.user_id=auth.uid()); $$;

grant execute on function public.is_room_member(uuid) to authenticated, anon;

alter table public.chat_room_members enable row level security;
alter table public.chat_rooms enable row level security;
alter table public.chat_messages enable row level security;

create policy chat_room_members_select_safe on public.chat_room_members for select using (user_id=auth.uid() or public.is_room_member(room_id));
create policy chat_room_members_insert_safe on public.chat_room_members for insert with check (auth.uid() is not null);
create policy chat_room_members_update_safe on public.chat_room_members for update using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy chat_room_members_delete_safe on public.chat_room_members for delete using (user_id=auth.uid());
create policy chat_rooms_select_safe on public.chat_rooms for select using (public.is_room_member(id));
create policy chat_rooms_insert_safe on public.chat_rooms for insert with check (auth.uid() is not null);
create policy chat_rooms_update_safe on public.chat_rooms for update using (public.is_room_member(id));
create policy chat_messages_select_safe on public.chat_messages for select using (public.is_room_member(room_id));
create policy chat_messages_insert_safe on public.chat_messages for insert with check (sender_id=auth.uid() and public.is_room_member(room_id));
create policy chat_messages_update_safe on public.chat_messages for update using (sender_id=auth.uid());

alter table public.profiles enable row level security;
drop policy if exists profiles_select_all on public.profiles;
drop policy if exists profiles_insert_own on public.profiles;
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_select_all on public.profiles for select using (auth.uid() is not null);
create policy profiles_insert_own on public.profiles for insert with check (id=auth.uid());
create policy profiles_update_own on public.profiles for update using (id=auth.uid()) with check (id=auth.uid());

alter table public.push_subscriptions enable row level security;
drop policy if exists push_own on public.push_subscriptions;
create policy push_own on public.push_subscriptions for all using (user_id=auth.uid()) with check (user_id=auth.uid());

drop function if exists public.get_my_friends();
create or replace function public.get_my_friends()
returns table(user_id uuid,email text,nickname text,avatar_url text,status_message text,birthday date,favorite boolean,created_at timestamptz)
language sql security definer set search_path=public as $$
  select case when f.requester_id=auth.uid() then f.addressee_id else f.requester_id end,
         p.email,p.nickname,p.avatar_url,p.status_message,p.birthday,
         case when f.requester_id=auth.uid() then coalesce(f.favorite_by_requester,false) else coalesce(f.favorite_by_addressee,false) end,
         f.created_at
  from friendships f
  join profiles p on p.id=case when f.requester_id=auth.uid() then f.addressee_id else f.requester_id end
  where f.status='accepted' and (f.requester_id=auth.uid() or f.addressee_id=auth.uid())
  order by 7 desc, p.nickname asc;
$$;

drop function if exists public.get_friend_requests();
create or replace function public.get_friend_requests()
returns table(friendship_id uuid,user_id uuid,email text,nickname text,avatar_url text,status_message text,created_at timestamptz)
language sql security definer set search_path=public as $$
  select f.id,p.id,p.email,p.nickname,p.avatar_url,p.status_message,f.created_at
  from friendships f join profiles p on p.id=f.requester_id
  where f.addressee_id=auth.uid() and f.status='pending'
  order by f.created_at desc;
$$;

drop function if exists public.get_my_chat_rooms();
create or replace function public.get_my_chat_rooms()
returns table(room_id uuid,room_type text,title text,avatar_url text,last_message text,last_message_at timestamptz,unread_count bigint,pinned boolean,muted boolean)
language sql security definer set search_path=public as $$
  select r.id,r.room_type,
    case when r.room_type='direct' then coalesce(op.nickname,'채팅') else coalesce(r.title,'그룹채팅') end,
    case when r.room_type='direct' then op.avatar_url else r.avatar_url end,
    case when lm.deleted_at is not null then '삭제된 메시지' when lm.message_type='image' then '사진' when lm.message_type='file' then coalesce(lm.file_name,'파일') when lm.message_type='voice' then '음성 메시지' when lm.message_type='location' then '위치' else coalesce(lm.body,'') end,
    coalesce(lm.created_at,r.created_at),
    (select count(*) from chat_messages cm where cm.room_id=r.id and cm.sender_id is distinct from auth.uid() and cm.created_at>coalesce(my.last_read_at,'1970-01-01'::timestamptz)),
    my.pinned,my.muted
  from chat_room_members my
  join chat_rooms r on r.id=my.room_id
  left join lateral (select m.* from chat_messages m where m.room_id=r.id order by m.created_at desc limit 1) lm on true
  left join lateral (select p.* from chat_room_members om join profiles p on p.id=om.user_id where om.room_id=r.id and om.user_id<>auth.uid() limit 1) op on true
  where my.user_id=auth.uid()
  order by my.pinned desc, coalesce(lm.created_at,r.created_at) desc;
$$;

drop function if exists public.get_room_members(uuid);
create or replace function public.get_room_members(p_room_id uuid)
returns table(user_id uuid,email text,nickname text,avatar_url text,status_message text,role text,muted boolean,pinned boolean,last_read_at timestamptz,joined_at timestamptz)
language sql security definer set search_path=public as $$
  select p.id,p.email,p.nickname,p.avatar_url,p.status_message,m.role,m.muted,m.pinned,m.last_read_at,m.joined_at
  from chat_room_members m join profiles p on p.id=m.user_id
  where m.room_id=p_room_id and public.is_room_member(p_room_id)
  order by case m.role when 'owner' then 0 when 'admin' then 1 else 2 end, p.nickname asc;
$$;

drop function if exists public.get_or_create_direct_room(uuid);
create or replace function public.get_or_create_direct_room(p_other_user_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_me uuid:=auth.uid(); v_key text; v_room uuid;
begin
  if v_me is null then raise exception 'login required'; end if;
  v_key:=least(v_me::text,p_other_user_id::text)||':'||greatest(v_me::text,p_other_user_id::text);
  select id into v_room from chat_rooms where direct_key=v_key;
  if v_room is null then
    insert into chat_rooms(room_type,direct_key,created_by) values('direct',v_key,v_me) returning id into v_room;
  end if;
  insert into chat_room_members(room_id,user_id,role) values(v_room,v_me,'member') on conflict do nothing;
  insert into chat_room_members(room_id,user_id,role) values(v_room,p_other_user_id,'member') on conflict do nothing;
  return v_room;
end; $$;

create or replace function public.mark_room_read(p_room_id uuid) returns void language sql security definer set search_path=public as $$ update chat_room_members set last_read_at=now() where room_id=p_room_id and user_id=auth.uid(); $$;
create or replace function public.edit_message(p_message_id uuid,p_body text) returns void language sql security definer set search_path=public as $$ update chat_messages set body=p_body,edited_at=now() where id=p_message_id and sender_id=auth.uid() and deleted_at is null and message_type='text'; $$;
create or replace function public.delete_message(p_message_id uuid) returns void language sql security definer set search_path=public as $$ update chat_messages set body=null,deleted_at=now() where id=p_message_id and sender_id=auth.uid() and deleted_at is null; $$;
create or replace function public.set_room_pinned(p_room_id uuid,p_pinned boolean) returns void language sql security definer set search_path=public as $$ update chat_room_members set pinned=p_pinned where room_id=p_room_id and user_id=auth.uid(); $$;
create or replace function public.set_room_muted(p_room_id uuid,p_muted boolean) returns void language sql security definer set search_path=public as $$ update chat_room_members set muted=p_muted where room_id=p_room_id and user_id=auth.uid(); $$;
create or replace function public.leave_room(p_room_id uuid) returns void language sql security definer set search_path=public as $$ delete from chat_room_members where room_id=p_room_id and user_id=auth.uid(); $$;

create or replace function public.get_my_notifications()
returns table(id uuid,type text,title text,body text,data jsonb,read_at timestamptz,created_at timestamptz)
language sql security definer set search_path=public as $$ select id,type,title,body,data,read_at,created_at from app_notifications where user_id=auth.uid() order by created_at desc limit 100; $$;
create or replace function public.mark_notification_read(p_id uuid) returns void language sql security definer set search_path=public as $$ update app_notifications set read_at=coalesce(read_at,now()) where id=p_id and user_id=auth.uid(); $$;

create or replace function public.get_calendar_events(p_from timestamptz,p_to timestamptz)
returns table(id uuid,owner_id uuid,owner_nickname text,owner_avatar_url text,title text,memo text,start_at timestamptz,end_at timestamptz,all_day boolean,color text,share_mode text,group_room_id uuid,repeat_rule text,reminder_minutes int[],created_at timestamptz)
language sql security definer set search_path=public as $$
  select e.id,e.owner_id,p.nickname,p.avatar_url,e.title,e.memo,e.start_at,e.end_at,e.all_day,e.color,e.share_mode,e.group_room_id,null::text,null::int[],e.created_at
  from calendar_events e join profiles p on p.id=e.owner_id
  where e.start_at<p_to and coalesce(e.end_at,e.start_at)>=p_from and (e.owner_id=auth.uid() or e.share_mode in ('friends','public'))
  order by e.start_at asc;
$$;

create or replace function public.save_calendar_event(p_id uuid,p_title text,p_start_at timestamptz,p_end_at timestamptz,p_all_day boolean,p_memo text,p_color text,p_share_mode text,p_group_room_id uuid,p_specific_user_ids uuid[])
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if p_id is null then
    insert into calendar_events(owner_id,title,start_at,end_at,all_day,memo,color,share_mode,group_room_id) values(auth.uid(),p_title,p_start_at,p_end_at,coalesce(p_all_day,false),p_memo,coalesce(p_color,'#FEE500'),coalesce(p_share_mode,'private'),p_group_room_id) returning id into v_id;
  else
    update calendar_events set title=p_title,start_at=p_start_at,end_at=p_end_at,all_day=coalesce(p_all_day,false),memo=p_memo,color=coalesce(p_color,'#FEE500'),share_mode=coalesce(p_share_mode,'private'),group_room_id=p_group_room_id,updated_at=now() where id=p_id and owner_id=auth.uid() returning id into v_id;
  end if;
  return v_id;
end; $$;
create or replace function public.delete_calendar_event(p_id uuid) returns void language sql security definer set search_path=public as $$ delete from calendar_events where id=p_id and owner_id=auth.uid(); $$;
create or replace function public.save_work_shift_settings(p_mode text,p_shift_team int,p_anchor_date date) returns void language sql security definer set search_path=public as $$ insert into work_shift_settings(user_id,mode,shift_team,anchor_date) values(auth.uid(),coalesce(p_mode,'normal'),p_shift_team,coalesce(p_anchor_date,date '2026-01-01')) on conflict(user_id) do update set mode=excluded.mode,shift_team=excluded.shift_team,anchor_date=excluded.anchor_date,updated_at=now(); $$;

create or replace function public.request_location_share(p_receiver_id uuid,p_duration_minutes int) returns uuid language plpgsql security definer set search_path=public as $$ declare v_id uuid; begin insert into location_share_requests(requester_id,receiver_id,duration_minutes) values(auth.uid(),p_receiver_id,greatest(15,least(coalesce(p_duration_minutes,60),480))) returning id into v_id; return v_id; end; $$;
create or replace function public.respond_location_share(p_request_id uuid,p_accept boolean) returns uuid language plpgsql security definer set search_path=public as $$ declare r location_share_requests%rowtype; s uuid; begin select * into r from location_share_requests where id=p_request_id and receiver_id=auth.uid() and status='pending'; if r.id is null then raise exception 'request not found'; end if; if p_accept then update location_share_requests set status='accepted',responded_at=now() where id=p_request_id; insert into location_share_sessions(request_id,user_a,user_b,expires_at) values(p_request_id,r.requester_id,r.receiver_id,now()+make_interval(mins=>r.duration_minutes)) returning id into s; return s; else update location_share_requests set status='rejected',responded_at=now() where id=p_request_id; return null; end if; end; $$;
create or replace function public.stop_location_share(p_session_id uuid) returns void language sql security definer set search_path=public as $$ update location_share_sessions set stopped_at=now() where id=p_session_id and (user_a=auth.uid() or user_b=auth.uid()); $$;
create or replace function public.upsert_live_location(p_latitude double precision,p_longitude double precision,p_accuracy double precision,p_heading double precision,p_speed double precision) returns void language sql security definer set search_path=public as $$ insert into live_locations(user_id,latitude,longitude,accuracy,heading,speed,updated_at) values(auth.uid(),p_latitude,p_longitude,p_accuracy,p_heading,p_speed,now()) on conflict(user_id) do update set latitude=excluded.latitude,longitude=excluded.longitude,accuracy=excluded.accuracy,heading=excluded.heading,speed=excluded.speed,updated_at=now(); $$;
create or replace function public.get_visible_locations() returns table(session_id uuid,user_id uuid,nickname text,avatar_url text,latitude double precision,longitude double precision,accuracy double precision,heading double precision,speed double precision,updated_at timestamptz,expires_at timestamptz,stopped_at timestamptz) language sql security definer set search_path=public as $$ select s.id,p.id,p.nickname,p.avatar_url,l.latitude,l.longitude,l.accuracy,l.heading,l.speed,l.updated_at,s.expires_at,s.stopped_at from location_share_sessions s join profiles p on p.id=case when s.user_a=auth.uid() then s.user_b else s.user_a end left join live_locations l on l.user_id=p.id where (s.user_a=auth.uid() or s.user_b=auth.uid()) and s.stopped_at is null and s.expires_at>now() order by l.updated_at desc nulls last; $$;
create or replace function public.get_location_requests() returns table(id uuid,requester_id uuid,requester_nickname text,requester_avatar_url text,receiver_id uuid,receiver_nickname text,status text,duration_minutes int,created_at timestamptz) language sql security definer set search_path=public as $$ select r.id,r.requester_id,rp.nickname,rp.avatar_url,r.receiver_id,ap.nickname,r.status,r.duration_minutes,r.created_at from location_share_requests r join profiles rp on rp.id=r.requester_id join profiles ap on ap.id=r.receiver_id where r.requester_id=auth.uid() or r.receiver_id=auth.uid() order by r.created_at desc limit 100; $$;
