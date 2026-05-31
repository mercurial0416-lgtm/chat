create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  nickname text not null default '익명',
  avatar_url text,
  status_message text default '',
  birthday date,
  dark_mode boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending',
  favorite_by_requester boolean not null default false,
  favorite_by_addressee boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint no_self_friend check (requester_id <> addressee_id)
);

create unique index if not exists friendships_pair_idx on public.friendships(least(requester_id, addressee_id), greatest(requester_id, addressee_id));

create table if not exists public.chat_rooms (
  id uuid primary key default gen_random_uuid(),
  room_type text not null default 'direct',
  title text,
  avatar_url text,
  direct_key text unique,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.chat_room_members (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member',
  muted boolean not null default false,
  pinned boolean not null default false,
  last_read_at timestamptz,
  joined_at timestamptz not null default now(),
  unique(room_id, user_id)
);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  sender_id uuid references public.profiles(id) on delete set null,
  body text,
  message_type text not null default 'text',
  image_url text,
  file_url text,
  file_name text,
  shared_latitude double precision,
  shared_longitude double precision,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists chat_messages_room_created_idx on public.chat_messages(room_id, created_at desc);

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique,
  subscription jsonb not null,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  memo text,
  start_at timestamptz not null,
  end_at timestamptz,
  all_day boolean not null default false,
  color text not null default '#fee500',
  share_mode text not null default 'private',
  group_room_id uuid references public.chat_rooms(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.location_share_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending',
  duration_minutes int not null default 60,
  created_at timestamptz not null default now(),
  responded_at timestamptz
);

create table if not exists public.location_share_sessions (
  id uuid primary key default gen_random_uuid(),
  request_id uuid references public.location_share_requests(id) on delete set null,
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  stopped_at timestamptz,
  created_at timestamptz not null default now()
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

insert into storage.buckets(id, name, public) values ('chat_uploads','chat_uploads',true) on conflict(id) do update set public = true;

create or replace function public.is_room_member(p_room_id uuid)
returns boolean language sql security definer set search_path = public as $$
  select exists(select 1 from public.chat_room_members m where m.room_id = p_room_id and m.user_id = auth.uid());
$$;

drop function if exists public.get_my_friends();
create or replace function public.get_my_friends()
returns table(user_id uuid,email text,nickname text,avatar_url text,status_message text,birthday date,favorite boolean,created_at timestamptz)
language sql security definer set search_path=public as $$
  select case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end,
         p.email,p.nickname,p.avatar_url,p.status_message,p.birthday,
         case when f.requester_id = auth.uid() then coalesce(f.favorite_by_requester,false) else coalesce(f.favorite_by_addressee,false) end,
         f.created_at
  from friendships f
  join profiles p on p.id = case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
  where f.status='accepted' and (f.requester_id=auth.uid() or f.addressee_id=auth.uid())
  order by 7 desc, p.nickname asc;
$$;

create or replace function public.get_friend_requests()
returns table(friendship_id uuid,user_id uuid,email text,nickname text,avatar_url text,status_message text,created_at timestamptz)
language sql security definer set search_path=public as $$
  select f.id,p.id,p.email,p.nickname,p.avatar_url,p.status_message,f.created_at
  from friendships f join profiles p on p.id=f.requester_id
  where f.addressee_id=auth.uid() and f.status='pending'
  order by f.created_at desc;
$$;

create or replace function public.send_friend_request(p_addressee_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_me uuid:=auth.uid(); v_id uuid;
begin
  if v_me is null then raise exception 'login required'; end if;
  if v_me = p_addressee_id then raise exception 'self request'; end if;
  select id into v_id from friendships where least(requester_id,addressee_id)=least(v_me,p_addressee_id) and greatest(requester_id,addressee_id)=greatest(v_me,p_addressee_id) limit 1;
  if v_id is not null then update friendships set requester_id=v_me, addressee_id=p_addressee_id, status='pending', updated_at=now() where id=v_id and status <> 'accepted'; return v_id; end if;
  insert into friendships(requester_id, addressee_id, status) values(v_me,p_addressee_id,'pending') returning id into v_id;
  return v_id;
end; $$;

create or replace function public.accept_friend_request(p_friendship_id uuid)
returns void language sql security definer set search_path=public as $$
  update friendships set status='accepted', updated_at=now() where id=p_friendship_id and addressee_id=auth.uid() and status='pending';
$$;
create or replace function public.reject_friend_request(p_friendship_id uuid)
returns void language sql security definer set search_path=public as $$
  update friendships set status='rejected', updated_at=now() where id=p_friendship_id and addressee_id=auth.uid() and status='pending';
$$;
create or replace function public.delete_friend(p_user_id uuid)
returns void language sql security definer set search_path=public as $$
  delete from friendships where status='accepted' and ((requester_id=auth.uid() and addressee_id=p_user_id) or (requester_id=p_user_id and addressee_id=auth.uid()));
$$;

create or replace function public.get_or_create_direct_room(p_other_user_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_me uuid:=auth.uid(); v_key text; v_room uuid;
begin
  if v_me is null then raise exception 'login required'; end if;
  v_key := least(v_me::text,p_other_user_id::text)||':'||greatest(v_me::text,p_other_user_id::text);
  select id into v_room from chat_rooms where direct_key=v_key;
  if v_room is null then
    insert into chat_rooms(room_type,direct_key,created_by) values('direct',v_key,v_me) returning id into v_room;
  end if;
  insert into chat_room_members(room_id,user_id,role) values(v_room,v_me,'member') on conflict do nothing;
  insert into chat_room_members(room_id,user_id,role) values(v_room,p_other_user_id,'member') on conflict do nothing;
  return v_room;
end; $$;

create or replace function public.create_group_room(p_title text, p_member_ids uuid[])
returns uuid language plpgsql security definer set search_path=public as $$
declare v_me uuid:=auth.uid(); v_room uuid; v_uid uuid;
begin
  insert into chat_rooms(room_type,title,created_by) values('group',coalesce(nullif(trim(p_title),''),'그룹채팅'),v_me) returning id into v_room;
  insert into chat_room_members(room_id,user_id,role) values(v_room,v_me,'owner') on conflict do nothing;
  foreach v_uid in array coalesce(p_member_ids,array[]::uuid[]) loop
    if v_uid<>v_me then insert into chat_room_members(room_id,user_id,role) values(v_room,v_uid,'member') on conflict do nothing; end if;
  end loop;
  return v_room;
end; $$;

create or replace function public.get_my_chat_rooms()
returns table(room_id uuid,room_type text,title text,avatar_url text,last_message text,last_message_at timestamptz,unread_count bigint,pinned boolean,muted boolean)
language sql security definer set search_path=public as $$
  select r.id, r.room_type,
    case when r.room_type='direct' then coalesce(op.nickname,'채팅') else coalesce(r.title,'그룹채팅') end,
    case when r.room_type='direct' then op.avatar_url else r.avatar_url end,
    case when lm.deleted_at is not null then '삭제된 메시지' when lm.message_type='image' then '사진' when lm.message_type='file' then coalesce(lm.file_name,'파일') when lm.message_type='location' then '위치' else coalesce(lm.body,'') end,
    coalesce(lm.created_at,r.created_at),
    (select count(*) from chat_messages cm where cm.room_id=r.id and cm.sender_id is distinct from auth.uid() and cm.created_at > coalesce(my.last_read_at,'1970-01-01'::timestamptz)),
    my.pinned,my.muted
  from chat_room_members my join chat_rooms r on r.id=my.room_id
  left join lateral (select * from chat_messages m where m.room_id=r.id order by m.created_at desc limit 1) lm on true
  left join lateral (select p.* from chat_room_members om join profiles p on p.id=om.user_id where om.room_id=r.id and om.user_id<>auth.uid() limit 1) op on true
  where my.user_id=auth.uid()
  order by my.pinned desc, coalesce(lm.created_at,r.created_at) desc;
$$;

create or replace function public.get_room_members(p_room_id uuid)
returns table(user_id uuid,email text,nickname text,avatar_url text,status_message text,role text,muted boolean,pinned boolean,last_read_at timestamptz,joined_at timestamptz)
language sql security definer set search_path=public as $$
  select p.id,p.email,p.nickname,p.avatar_url,p.status_message,m.role,m.muted,m.pinned,m.last_read_at,m.joined_at
  from chat_room_members m join profiles p on p.id=m.user_id
  where m.room_id=p_room_id and public.is_room_member(p_room_id)
  order by case m.role when 'owner' then 0 else 1 end, p.nickname;
$$;

create or replace function public.mark_room_read(p_room_id uuid)
returns void language sql security definer set search_path=public as $$
  update chat_room_members set last_read_at=now() where room_id=p_room_id and user_id=auth.uid();
$$;

create or replace function public.get_calendar_events(p_from timestamptz, p_to timestamptz)
returns table(id uuid,owner_id uuid,owner_nickname text,owner_avatar_url text,title text,memo text,start_at timestamptz,end_at timestamptz,all_day boolean,color text,share_mode text,group_room_id uuid,created_at timestamptz)
language sql security definer set search_path=public as $$
  select e.id,e.owner_id,p.nickname,p.avatar_url,e.title,e.memo,e.start_at,e.end_at,e.all_day,e.color,e.share_mode,e.group_room_id,e.created_at
  from calendar_events e join profiles p on p.id=e.owner_id
  where e.start_at < p_to and coalesce(e.end_at,e.start_at) >= p_from
    and (e.owner_id=auth.uid() or e.share_mode in ('friends','public') or (e.share_mode='group' and exists(select 1 from chat_room_members m where m.room_id=e.group_room_id and m.user_id=auth.uid())))
  order by e.start_at;
$$;

create or replace function public.save_calendar_event(p_id uuid,p_title text,p_start_at timestamptz,p_end_at timestamptz,p_all_day boolean,p_memo text,p_color text,p_share_mode text,p_group_room_id uuid,p_specific_user_ids uuid[])
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_me uuid:=auth.uid();
begin
  if p_id is null then insert into calendar_events(owner_id,title,start_at,end_at,all_day,memo,color,share_mode,group_room_id) values(v_me,p_title,p_start_at,p_end_at,coalesce(p_all_day,false),p_memo,coalesce(p_color,'#fee500'),coalesce(p_share_mode,'private'),p_group_room_id) returning id into v_id;
  else update calendar_events set title=p_title,start_at=p_start_at,end_at=p_end_at,all_day=coalesce(p_all_day,false),memo=p_memo,color=coalesce(p_color,'#fee500'),share_mode=coalesce(p_share_mode,'private'),group_room_id=p_group_room_id,updated_at=now() where id=p_id and owner_id=v_me returning id into v_id; end if;
  return v_id;
end; $$;
create or replace function public.delete_calendar_event(p_id uuid) returns void language sql security definer set search_path=public as $$ delete from calendar_events where id=p_id and owner_id=auth.uid(); $$;

create or replace function public.request_location_share(p_receiver_id uuid,p_duration_minutes int)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; begin insert into location_share_requests(requester_id,receiver_id,duration_minutes) values(auth.uid(),p_receiver_id,greatest(15,least(coalesce(p_duration_minutes,60),480))) returning id into v_id; return v_id; end; $$;
create or replace function public.respond_location_share(p_request_id uuid,p_accept boolean)
returns uuid language plpgsql security definer set search_path=public as $$
declare r location_share_requests%rowtype; sid uuid;
begin
  select * into r from location_share_requests where id=p_request_id and receiver_id=auth.uid() and status='pending';
  if r.id is null then raise exception 'request not found'; end if;
  if p_accept then update location_share_requests set status='accepted',responded_at=now() where id=p_request_id; insert into location_share_sessions(request_id,user_a,user_b,expires_at) values(p_request_id,r.requester_id,r.receiver_id,now()+make_interval(mins=>r.duration_minutes)) returning id into sid; return sid;
  else update location_share_requests set status='rejected',responded_at=now() where id=p_request_id; return null; end if;
end; $$;
create or replace function public.upsert_live_location(p_latitude double precision,p_longitude double precision,p_accuracy double precision,p_heading double precision,p_speed double precision)
returns void language sql security definer set search_path=public as $$
  insert into live_locations(user_id,latitude,longitude,accuracy,heading,speed,updated_at) values(auth.uid(),p_latitude,p_longitude,p_accuracy,p_heading,p_speed,now()) on conflict(user_id) do update set latitude=excluded.latitude,longitude=excluded.longitude,accuracy=excluded.accuracy,heading=excluded.heading,speed=excluded.speed,updated_at=now();
$$;
create or replace function public.get_visible_locations()
returns table(session_id uuid,user_id uuid,nickname text,avatar_url text,latitude double precision,longitude double precision,accuracy double precision,heading double precision,speed double precision,updated_at timestamptz,expires_at timestamptz,stopped_at timestamptz)
language sql security definer set search_path=public as $$
  select s.id,p.id,p.nickname,p.avatar_url,l.latitude,l.longitude,l.accuracy,l.heading,l.speed,l.updated_at,s.expires_at,s.stopped_at
  from location_share_sessions s join profiles p on p.id=case when s.user_a=auth.uid() then s.user_b else s.user_a end left join live_locations l on l.user_id=p.id
  where (s.user_a=auth.uid() or s.user_b=auth.uid()) and s.stopped_at is null and s.expires_at>now();
$$;
create or replace function public.get_location_requests()
returns table(id uuid,requester_id uuid,requester_nickname text,requester_avatar_url text,receiver_id uuid,receiver_nickname text,status text,duration_minutes int,created_at timestamptz)
language sql security definer set search_path=public as $$
  select r.id,r.requester_id,rp.nickname,rp.avatar_url,r.receiver_id,ap.nickname,r.status,r.duration_minutes,r.created_at
  from location_share_requests r join profiles rp on rp.id=r.requester_id join profiles ap on ap.id=r.receiver_id
  where r.requester_id=auth.uid() or r.receiver_id=auth.uid() order by r.created_at desc limit 100;
$$;

-- RLS reset for core tables
alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.chat_rooms enable row level security;
alter table public.chat_room_members enable row level security;
alter table public.chat_messages enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.calendar_events enable row level security;
alter table public.location_share_requests enable row level security;
alter table public.location_share_sessions enable row level security;
alter table public.live_locations enable row level security;

do $$ declare p record; begin for p in select schemaname,tablename,policyname from pg_policies where schemaname='public' and tablename in ('profiles','friendships','chat_rooms','chat_room_members','chat_messages','push_subscriptions','calendar_events','location_share_requests','location_share_sessions','live_locations') loop execute format('drop policy if exists %I on %I.%I',p.policyname,p.schemaname,p.tablename); end loop; end $$;

create policy profiles_all on public.profiles for select using(auth.uid() is not null);
create policy profiles_insert_own on public.profiles for insert with check(id=auth.uid());
create policy profiles_update_own on public.profiles for update using(id=auth.uid());
create policy friendships_related on public.friendships for all using(requester_id=auth.uid() or addressee_id=auth.uid()) with check(requester_id=auth.uid() or addressee_id=auth.uid());
create policy rooms_select on public.chat_rooms for select using(public.is_room_member(id));
create policy rooms_insert on public.chat_rooms for insert with check(auth.uid() is not null);
create policy members_select on public.chat_room_members for select using(user_id=auth.uid() or public.is_room_member(room_id));
create policy members_insert on public.chat_room_members for insert with check(auth.uid() is not null);
create policy members_update on public.chat_room_members for update using(user_id=auth.uid());
create policy messages_select on public.chat_messages for select using(public.is_room_member(room_id));
create policy messages_insert on public.chat_messages for insert with check(sender_id=auth.uid() and public.is_room_member(room_id));
create policy messages_update on public.chat_messages for update using(sender_id=auth.uid());
create policy push_own on public.push_subscriptions for all using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy calendar_auth_select on public.calendar_events for select using(auth.uid() is not null);
create policy calendar_own_write on public.calendar_events for all using(owner_id=auth.uid()) with check(owner_id=auth.uid());
create policy location_requests_related on public.location_share_requests for all using(requester_id=auth.uid() or receiver_id=auth.uid()) with check(requester_id=auth.uid() or receiver_id=auth.uid());
create policy location_sessions_related on public.location_share_sessions for all using(user_a=auth.uid() or user_b=auth.uid()) with check(user_a=auth.uid() or user_b=auth.uid());
create policy live_locations_select on public.live_locations for select using(user_id=auth.uid() or exists(select 1 from location_share_sessions s where s.stopped_at is null and s.expires_at>now() and ((s.user_a=auth.uid() and s.user_b=live_locations.user_id) or (s.user_b=auth.uid() and s.user_a=live_locations.user_id))));
create policy live_locations_own on public.live_locations for all using(user_id=auth.uid()) with check(user_id=auth.uid());

do $$ begin
  if exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='chat_uploads_select') then drop policy chat_uploads_select on storage.objects; end if;
  if exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='chat_uploads_insert') then drop policy chat_uploads_insert on storage.objects; end if;
end $$;
create policy chat_uploads_select on storage.objects for select using(bucket_id='chat_uploads');
create policy chat_uploads_insert on storage.objects for insert with check(bucket_id='chat_uploads' and auth.uid() is not null);

-- v13.1 login/profile safety: create profile automatically on auth signup
create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles(id, email, nickname)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'nickname', split_part(new.email, '@', 1), '익명')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row execute function public.handle_new_user_profile();

insert into public.profiles(id, email, nickname)
select u.id, u.email, coalesce(u.raw_user_meta_data->>'nickname', split_part(u.email, '@', 1), '익명')
from auth.users u
on conflict (id) do nothing;

-- === v13.2 duplicate friend hotfix ===
-- 기존 중복 친구관계 정리 + 앞으로 같은 2명 친구관계 1개만 허용
with ranked_friendships as (
  select
    id,
    row_number() over (
      partition by least(requester_id, addressee_id), greatest(requester_id, addressee_id)
      order by
        case status when 'accepted' then 0 when 'pending' then 1 else 2 end,
        updated_at desc nulls last,
        created_at desc nulls last
    ) as rn
  from public.friendships
)
delete from public.friendships f
using ranked_friendships r
where f.id = r.id and r.rn > 1;

drop index if exists public.friendships_pair_idx;
create unique index if not exists friendships_pair_idx
on public.friendships(least(requester_id, addressee_id), greatest(requester_id, addressee_id));

drop function if exists public.get_my_friends();
create or replace function public.get_my_friends()
returns table(user_id uuid,email text,nickname text,avatar_url text,status_message text,birthday date,favorite boolean,created_at timestamptz)
language sql security definer set search_path=public as $$
  with raw_rows as (
    select
      case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end as user_id,
      p.email,
      p.nickname,
      p.avatar_url,
      p.status_message,
      p.birthday,
      case when f.requester_id = auth.uid() then coalesce(f.favorite_by_requester,false) else coalesce(f.favorite_by_addressee,false) end as favorite,
      f.created_at
    from public.friendships f
    join public.profiles p on p.id = case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
    where f.status='accepted'
      and (f.requester_id=auth.uid() or f.addressee_id=auth.uid())
  ), deduped as (
    select distinct on (user_id) *
    from raw_rows
    order by user_id, favorite desc, created_at desc
  )
  select user_id,email,nickname,avatar_url,status_message,birthday,favorite,created_at
  from deduped
  order by favorite desc, nickname asc nulls last, email asc nulls last;
$$;

drop function if exists public.get_friend_requests();
create or replace function public.get_friend_requests()
returns table(friendship_id uuid,user_id uuid,email text,nickname text,avatar_url text,status_message text,created_at timestamptz)
language sql security definer set search_path=public as $$
  with raw_rows as (
    select f.id as friendship_id,p.id as user_id,p.email,p.nickname,p.avatar_url,p.status_message,f.created_at
    from public.friendships f
    join public.profiles p on p.id=f.requester_id
    where f.addressee_id=auth.uid() and f.status='pending'
  ), deduped as (
    select distinct on (user_id) *
    from raw_rows
    order by user_id, created_at desc
  )
  select friendship_id,user_id,email,nickname,avatar_url,status_message,created_at
  from deduped
  order by created_at desc;
$$;

drop function if exists public.send_friend_request(uuid);
create or replace function public.send_friend_request(p_addressee_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare
  v_me uuid := auth.uid();
  v_id uuid;
  v_status text;
begin
  if v_me is null then raise exception 'login required'; end if;
  if v_me = p_addressee_id then raise exception 'self request'; end if;

  select id, status into v_id, v_status
  from public.friendships
  where least(requester_id,addressee_id)=least(v_me,p_addressee_id)
    and greatest(requester_id,addressee_id)=greatest(v_me,p_addressee_id)
  order by case status when 'accepted' then 0 when 'pending' then 1 else 2 end, updated_at desc nulls last
  limit 1;

  if v_id is not null then
    if v_status = 'accepted' then
      return v_id;
    end if;
    update public.friendships
      set requester_id=v_me,
          addressee_id=p_addressee_id,
          status='pending',
          updated_at=now()
    where id=v_id;
    return v_id;
  end if;

  insert into public.friendships(requester_id, addressee_id, status)
  values(v_me,p_addressee_id,'pending')
  returning id into v_id;

  return v_id;
end;
$$;

notify pgrst, 'reload schema';
