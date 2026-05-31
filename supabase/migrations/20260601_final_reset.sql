-- FINAL RESET SCHEMA FOR CHAT/CALENDAR/LOCATION APP
-- 주의: 아래 DROP TABLE은 기존 앱 데이터를 삭제합니다. 개발 중 꼬인 스키마를 깨끗하게 맞추는 용도입니다.
create extension if not exists pgcrypto;

drop table if exists public.poll_votes cascade;
drop table if exists public.poll_options cascade;
drop table if exists public.polls cascade;
drop table if exists public.live_locations cascade;
drop table if exists public.location_share_sessions cascade;
drop table if exists public.location_share_requests cascade;
drop table if exists public.work_shift_settings cascade;
drop table if exists public.calendar_event_rsvps cascade;
drop table if exists public.calendar_event_comments cascade;
drop table if exists public.calendar_event_viewers cascade;
drop table if exists public.calendar_events cascade;
drop table if exists public.push_subscriptions cascade;
drop table if exists public.app_notifications cascade;
drop table if exists public.message_reactions cascade;
drop table if exists public.chat_messages cascade;
drop table if exists public.chat_room_members cascade;
drop table if exists public.chat_rooms cascade;
drop table if exists public.friendships cascade;
drop table if exists public.profiles cascade;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  nickname text not null default '익명',
  avatar_url text,
  status_message text default '',
  birthday date,
  is_admin boolean not null default false,
  dark_mode boolean not null default false,
  font_size text not null default 'normal',
  global_push_enabled boolean not null default true,
  show_friend_calendar boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null check (status in ('pending','accepted','rejected','blocked')),
  favorite_by_requester boolean not null default false,
  favorite_by_addressee boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint no_self_friend check (requester_id <> addressee_id)
);
create unique index friendships_pair_unique on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

create table public.chat_rooms (
  id uuid primary key default gen_random_uuid(),
  room_type text not null check (room_type in ('direct','group')),
  title text,
  avatar_url text,
  direct_key text unique,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.chat_room_members (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','member')),
  muted boolean not null default false,
  pinned boolean not null default false,
  last_read_at timestamptz,
  joined_at timestamptz not null default now(),
  unique(room_id, user_id)
);

create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  sender_id uuid references public.profiles(id) on delete set null,
  body text,
  message_type text not null default 'text' check (message_type in ('text','image','file','voice','system','location','calendar','poll')),
  image_url text,
  file_url text,
  file_name text,
  file_size bigint,
  audio_url text,
  reply_to_message_id uuid references public.chat_messages(id) on delete set null,
  shared_latitude double precision,
  shared_longitude double precision,
  edited_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);
create index chat_messages_room_created_idx on public.chat_messages(room_id, created_at desc);

create table public.message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.chat_messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  unique(message_id, user_id, emoji)
);

create table public.app_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null default 'general',
  title text not null,
  body text,
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique,
  subscription jsonb not null,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  memo text,
  start_at timestamptz not null,
  end_at timestamptz,
  all_day boolean not null default false,
  color text not null default '#FEE500',
  share_mode text not null default 'private' check (share_mode in ('private','friends','specific','group','public')),
  group_room_id uuid references public.chat_rooms(id) on delete cascade,
  repeat_rule text,
  reminder_minutes int[],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.calendar_event_viewers (id uuid primary key default gen_random_uuid(), event_id uuid not null references public.calendar_events(id) on delete cascade, viewer_id uuid not null references public.profiles(id) on delete cascade, unique(event_id, viewer_id));
create table public.calendar_event_comments (id uuid primary key default gen_random_uuid(), event_id uuid not null references public.calendar_events(id) on delete cascade, user_id uuid not null references public.profiles(id) on delete cascade, body text not null, created_at timestamptz not null default now());
create table public.calendar_event_rsvps (id uuid primary key default gen_random_uuid(), event_id uuid not null references public.calendar_events(id) on delete cascade, user_id uuid not null references public.profiles(id) on delete cascade, status text not null check (status in ('yes','no','maybe')), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(event_id,user_id));

create table public.work_shift_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  mode text not null default 'normal' check (mode in ('normal','shift4x3')),
  shift_team int default 1 check (shift_team between 1 and 4),
  anchor_date date not null default date '2026-01-01',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.location_share_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected','expired','stopped')),
  duration_minutes int not null default 60,
  created_at timestamptz not null default now(),
  responded_at timestamptz
);
create table public.location_share_sessions (
  id uuid primary key default gen_random_uuid(),
  request_id uuid references public.location_share_requests(id) on delete set null,
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  stopped_at timestamptz,
  created_at timestamptz not null default now()
);
create table public.live_locations (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  latitude double precision not null,
  longitude double precision not null,
  accuracy double precision,
  heading double precision,
  speed double precision,
  updated_at timestamptz not null default now()
);

create table public.polls (id uuid primary key default gen_random_uuid(), room_id uuid not null references public.chat_rooms(id) on delete cascade, created_by uuid not null references public.profiles(id) on delete cascade, question text not null, multiple boolean not null default false, closes_at timestamptz, created_at timestamptz not null default now());
create table public.poll_options (id uuid primary key default gen_random_uuid(), poll_id uuid not null references public.polls(id) on delete cascade, label text not null, created_at timestamptz not null default now());
create table public.poll_votes (id uuid primary key default gen_random_uuid(), poll_id uuid not null references public.polls(id) on delete cascade, option_id uuid not null references public.poll_options(id) on delete cascade, user_id uuid not null references public.profiles(id) on delete cascade, created_at timestamptz not null default now(), unique(option_id, user_id));

create or replace function public.send_friend_request(p_addressee_id uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare v_me uuid:=auth.uid(); v_id uuid; v_status text;
begin
 if v_me is null then raise exception 'login required'; end if; if v_me=p_addressee_id then raise exception 'self request not allowed'; end if;
 select id,status into v_id,v_status from friendships where least(requester_id,addressee_id)=least(v_me,p_addressee_id) and greatest(requester_id,addressee_id)=greatest(v_me,p_addressee_id) limit 1;
 if v_id is not null then if v_status in ('pending','accepted') then return v_id; end if; update friendships set requester_id=v_me,addressee_id=p_addressee_id,status='pending',updated_at=now() where id=v_id; return v_id; end if;
 insert into friendships(requester_id,addressee_id,status) values(v_me,p_addressee_id,'pending') returning id into v_id;
 insert into app_notifications(user_id,type,title,body,data) values(p_addressee_id,'friend_request','친구 요청',(select nickname from profiles where id=v_me)||'님이 친구 요청을 보냈습니다.',jsonb_build_object('friendship_id',v_id));
 return v_id;
end $$;
create or replace function public.accept_friend_request(p_friendship_id uuid) returns void language sql security definer set search_path=public as $$ update friendships set status='accepted',updated_at=now() where id=p_friendship_id and addressee_id=auth.uid() and status='pending'; $$;
create or replace function public.reject_friend_request(p_friendship_id uuid) returns void language sql security definer set search_path=public as $$ update friendships set status='rejected',updated_at=now() where id=p_friendship_id and addressee_id=auth.uid() and status='pending'; $$;
create or replace function public.delete_friend(p_user_id uuid) returns void language sql security definer set search_path=public as $$ delete from friendships where status='accepted' and ((requester_id=auth.uid() and addressee_id=p_user_id) or (requester_id=p_user_id and addressee_id=auth.uid())); $$;
create or replace function public.block_user(p_user_id uuid) returns void language plpgsql security definer set search_path=public as $$ begin delete from friendships where least(requester_id,addressee_id)=least(auth.uid(),p_user_id) and greatest(requester_id,addressee_id)=greatest(auth.uid(),p_user_id); insert into friendships(requester_id,addressee_id,status) values(auth.uid(),p_user_id,'blocked') on conflict do nothing; end $$;
create or replace function public.unblock_user(p_user_id uuid) returns void language sql security definer set search_path=public as $$ delete from friendships where requester_id=auth.uid() and addressee_id=p_user_id and status='blocked'; $$;
create or replace function public.get_my_friends() returns table(user_id uuid,email text,nickname text,avatar_url text,status_message text,birthday date,favorite boolean,created_at timestamptz) language sql security definer set search_path=public as $$ select case when f.requester_id=auth.uid() then f.addressee_id else f.requester_id end,p.email,p.nickname,p.avatar_url,p.status_message,p.birthday,case when f.requester_id=auth.uid() then f.favorite_by_requester else f.favorite_by_addressee end,f.created_at from friendships f join profiles p on p.id=case when f.requester_id=auth.uid() then f.addressee_id else f.requester_id end where f.status='accepted' and (f.requester_id=auth.uid() or f.addressee_id=auth.uid()) order by favorite desc,p.nickname; $$;
create or replace function public.get_friend_requests() returns table(friendship_id uuid,user_id uuid,email text,nickname text,avatar_url text,status_message text,created_at timestamptz) language sql security definer set search_path=public as $$ select f.id,p.id,p.email,p.nickname,p.avatar_url,p.status_message,f.created_at from friendships f join profiles p on p.id=f.requester_id where f.addressee_id=auth.uid() and f.status='pending' order by f.created_at desc; $$;
create or replace function public.get_blocked_users() returns table(user_id uuid,email text,nickname text,avatar_url text,status_message text,created_at timestamptz) language sql security definer set search_path=public as $$ select p.id,p.email,p.nickname,p.avatar_url,p.status_message,f.created_at from friendships f join profiles p on p.id=f.addressee_id where f.requester_id=auth.uid() and f.status='blocked'; $$;

create or replace function public.get_or_create_direct_room(p_other_user_id uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare v_me uuid:=auth.uid(); v_key text; v_room uuid;
begin
 v_key:=least(v_me::text,p_other_user_id::text)||':'||greatest(v_me::text,p_other_user_id::text);
 select id into v_room from chat_rooms where direct_key=v_key;
 if v_room is null then insert into chat_rooms(room_type,direct_key,created_by) values('direct',v_key,v_me) returning id into v_room; end if;
 insert into chat_room_members(room_id,user_id,role) values(v_room,v_me,'member'),(v_room,p_other_user_id,'member') on conflict do nothing;
 return v_room;
end $$;
create or replace function public.create_group_room(p_title text,p_member_ids uuid[]) returns uuid language plpgsql security definer set search_path=public as $$
declare v_me uuid:=auth.uid(); v_room uuid; v_uid uuid;
begin insert into chat_rooms(room_type,title,created_by) values('group',coalesce(nullif(trim(p_title),''),'그룹채팅'),v_me) returning id into v_room; insert into chat_room_members(room_id,user_id,role) values(v_room,v_me,'owner'); foreach v_uid in array coalesce(p_member_ids,array[]::uuid[]) loop if v_uid<>v_me then insert into chat_room_members(room_id,user_id,role) values(v_room,v_uid,'member') on conflict do nothing; end if; end loop; insert into chat_messages(room_id,sender_id,body,message_type) values(v_room,v_me,'그룹채팅방이 생성되었습니다.','system'); return v_room; end $$;
create or replace function public.invite_group_members(p_room_id uuid,p_member_ids uuid[]) returns void language plpgsql security definer set search_path=public as $$ declare v_uid uuid; begin foreach v_uid in array coalesce(p_member_ids,array[]::uuid[]) loop insert into chat_room_members(room_id,user_id,role) values(p_room_id,v_uid,'member') on conflict do nothing; end loop; end $$;
create or replace function public.get_my_chat_rooms() returns table(room_id uuid,room_type text,title text,avatar_url text,last_message text,last_message_at timestamptz,unread_count bigint,pinned boolean,muted boolean) language sql security definer set search_path=public as $$ select r.id,r.room_type,case when r.room_type='direct' then coalesce(op.nickname,'채팅') else coalesce(r.title,'그룹채팅') end,case when r.room_type='direct' then op.avatar_url else r.avatar_url end,case when lm.deleted_at is not null then '삭제된 메시지' when lm.message_type='image' then '사진' when lm.message_type='file' then coalesce(lm.file_name,'파일') when lm.message_type='voice' then '음성 메시지' when lm.message_type='location' then '위치' else coalesce(lm.body,'') end,coalesce(lm.created_at,r.created_at),(select count(*) from chat_messages cm where cm.room_id=r.id and cm.sender_id is distinct from auth.uid() and cm.created_at>coalesce(my.last_read_at,'1970-01-01'::timestamptz)),my.pinned,my.muted from chat_room_members my join chat_rooms r on r.id=my.room_id left join lateral(select * from chat_messages m where m.room_id=r.id order by m.created_at desc limit 1) lm on true left join lateral(select p.* from chat_room_members om join profiles p on p.id=om.user_id where om.room_id=r.id and om.user_id<>auth.uid() limit 1) op on true where my.user_id=auth.uid() order by my.pinned desc,coalesce(lm.created_at,r.created_at) desc; $$;
create or replace function public.get_room_members(p_room_id uuid) returns table(user_id uuid,email text,nickname text,avatar_url text,status_message text,role text,muted boolean,pinned boolean,last_read_at timestamptz,joined_at timestamptz) language sql security definer set search_path=public as $$ select p.id,p.email,p.nickname,p.avatar_url,p.status_message,m.role,m.muted,m.pinned,m.last_read_at,m.joined_at from chat_room_members m join profiles p on p.id=m.user_id where m.room_id=p_room_id and exists(select 1 from chat_room_members me where me.room_id=p_room_id and me.user_id=auth.uid()) order by case m.role when 'owner' then 0 when 'admin' then 1 else 2 end,p.nickname; $$;
create or replace function public.mark_room_read(p_room_id uuid) returns void language sql security definer set search_path=public as $$ update chat_room_members set last_read_at=now() where room_id=p_room_id and user_id=auth.uid(); $$;
create or replace function public.leave_room(p_room_id uuid) returns void language sql security definer set search_path=public as $$ delete from chat_room_members where room_id=p_room_id and user_id=auth.uid(); $$;
create or replace function public.set_room_muted(p_room_id uuid,p_muted boolean) returns void language sql security definer set search_path=public as $$ update chat_room_members set muted=p_muted where room_id=p_room_id and user_id=auth.uid(); $$;
create or replace function public.set_room_pinned(p_room_id uuid,p_pinned boolean) returns void language sql security definer set search_path=public as $$ update chat_room_members set pinned=p_pinned where room_id=p_room_id and user_id=auth.uid(); $$;
create or replace function public.edit_message(p_message_id uuid,p_body text) returns void language sql security definer set search_path=public as $$ update chat_messages set body=p_body,edited_at=now() where id=p_message_id and sender_id=auth.uid() and deleted_at is null and message_type='text'; $$;
create or replace function public.delete_message(p_message_id uuid) returns void language sql security definer set search_path=public as $$ update chat_messages set body=null,deleted_at=now() where id=p_message_id and sender_id=auth.uid() and deleted_at is null; $$;

create or replace function public.get_my_notifications() returns table(id uuid,type text,title text,body text,data jsonb,read_at timestamptz,created_at timestamptz) language sql security definer set search_path=public as $$ select id,type,title,body,data,read_at,created_at from app_notifications where user_id=auth.uid() order by created_at desc limit 100; $$;
create or replace function public.mark_notification_read(p_id uuid) returns void language sql security definer set search_path=public as $$ update app_notifications set read_at=coalesce(read_at,now()) where id=p_id and user_id=auth.uid(); $$;

create or replace function public.get_calendar_events(p_from timestamptz,p_to timestamptz) returns table(id uuid,owner_id uuid,owner_nickname text,owner_avatar_url text,title text,memo text,start_at timestamptz,end_at timestamptz,all_day boolean,color text,share_mode text,group_room_id uuid,repeat_rule text,reminder_minutes int[],created_at timestamptz) language sql security definer set search_path=public as $$ select e.id,e.owner_id,p.nickname,p.avatar_url,e.title,e.memo,e.start_at,e.end_at,e.all_day,e.color,e.share_mode,e.group_room_id,e.repeat_rule,e.reminder_minutes,e.created_at from calendar_events e join profiles p on p.id=e.owner_id where e.start_at<p_to and coalesce(e.end_at,e.start_at)>=p_from and (e.owner_id=auth.uid() or e.share_mode='public' or (e.share_mode='friends' and exists(select 1 from friendships f where f.status='accepted' and ((f.requester_id=auth.uid() and f.addressee_id=e.owner_id) or (f.addressee_id=auth.uid() and f.requester_id=e.owner_id)))) or (e.share_mode='specific' and exists(select 1 from calendar_event_viewers v where v.event_id=e.id and v.viewer_id=auth.uid())) or (e.share_mode='group' and exists(select 1 from chat_room_members m where m.room_id=e.group_room_id and m.user_id=auth.uid()))) order by e.start_at; $$;
create or replace function public.save_calendar_event(p_id uuid,p_title text,p_start_at timestamptz,p_end_at timestamptz,p_all_day boolean,p_memo text,p_color text,p_share_mode text,p_group_room_id uuid,p_specific_user_ids uuid[]) returns uuid language plpgsql security definer set search_path=public as $$ declare v_id uuid; v_uid uuid; begin if p_id is null then insert into calendar_events(owner_id,title,start_at,end_at,all_day,memo,color,share_mode,group_room_id) values(auth.uid(),p_title,p_start_at,p_end_at,coalesce(p_all_day,false),p_memo,coalesce(p_color,'#FEE500'),coalesce(p_share_mode,'private'),p_group_room_id) returning id into v_id; else update calendar_events set title=p_title,start_at=p_start_at,end_at=p_end_at,all_day=coalesce(p_all_day,false),memo=p_memo,color=coalesce(p_color,'#FEE500'),share_mode=coalesce(p_share_mode,'private'),group_room_id=p_group_room_id,updated_at=now() where id=p_id and owner_id=auth.uid() returning id into v_id; delete from calendar_event_viewers where event_id=v_id; end if; if coalesce(p_share_mode,'private')='specific' then foreach v_uid in array coalesce(p_specific_user_ids,array[]::uuid[]) loop insert into calendar_event_viewers(event_id,viewer_id) values(v_id,v_uid) on conflict do nothing; end loop; end if; return v_id; end $$;
create or replace function public.delete_calendar_event(p_id uuid) returns void language sql security definer set search_path=public as $$ delete from calendar_events where id=p_id and owner_id=auth.uid(); $$;
create or replace function public.save_work_shift_settings(p_mode text,p_shift_team int,p_anchor_date date) returns void language sql security definer set search_path=public as $$ insert into work_shift_settings(user_id,mode,shift_team,anchor_date) values(auth.uid(),coalesce(p_mode,'normal'),p_shift_team,coalesce(p_anchor_date,date '2026-01-01')) on conflict(user_id) do update set mode=excluded.mode,shift_team=excluded.shift_team,anchor_date=excluded.anchor_date,updated_at=now(); $$;

create or replace function public.request_location_share(p_receiver_id uuid,p_duration_minutes int) returns uuid language plpgsql security definer set search_path=public as $$ declare v_id uuid; begin insert into location_share_requests(requester_id,receiver_id,duration_minutes) values(auth.uid(),p_receiver_id,greatest(15,least(coalesce(p_duration_minutes,60),480))) returning id into v_id; insert into app_notifications(user_id,type,title,body,data) values(p_receiver_id,'location_request','위치 공유 요청',(select nickname from profiles where id=auth.uid())||'님이 위치 공유를 요청했습니다.',jsonb_build_object('request_id',v_id)); return v_id; end $$;
create or replace function public.respond_location_share(p_request_id uuid,p_accept boolean) returns uuid language plpgsql security definer set search_path=public as $$ declare r location_share_requests%rowtype; sid uuid; begin select * into r from location_share_requests where id=p_request_id and receiver_id=auth.uid() and status='pending'; if r.id is null then raise exception 'request not found'; end if; if p_accept then update location_share_requests set status='accepted',responded_at=now() where id=p_request_id; insert into location_share_sessions(request_id,user_a,user_b,expires_at) values(p_request_id,r.requester_id,r.receiver_id,now()+make_interval(mins=>r.duration_minutes)) returning id into sid; return sid; else update location_share_requests set status='rejected',responded_at=now() where id=p_request_id; return null; end if; end $$;
create or replace function public.stop_location_share(p_session_id uuid) returns void language sql security definer set search_path=public as $$ update location_share_sessions set stopped_at=now() where id=p_session_id and (user_a=auth.uid() or user_b=auth.uid()); $$;
create or replace function public.upsert_live_location(p_latitude double precision,p_longitude double precision,p_accuracy double precision,p_heading double precision,p_speed double precision) returns void language sql security definer set search_path=public as $$ insert into live_locations(user_id,latitude,longitude,accuracy,heading,speed,updated_at) values(auth.uid(),p_latitude,p_longitude,p_accuracy,p_heading,p_speed,now()) on conflict(user_id) do update set latitude=excluded.latitude,longitude=excluded.longitude,accuracy=excluded.accuracy,heading=excluded.heading,speed=excluded.speed,updated_at=now(); $$;
create or replace function public.get_visible_locations() returns table(session_id uuid,user_id uuid,nickname text,avatar_url text,latitude double precision,longitude double precision,accuracy double precision,heading double precision,speed double precision,updated_at timestamptz,expires_at timestamptz,stopped_at timestamptz) language sql security definer set search_path=public as $$ select s.id,p.id,p.nickname,p.avatar_url,l.latitude,l.longitude,l.accuracy,l.heading,l.speed,l.updated_at,s.expires_at,s.stopped_at from location_share_sessions s join profiles p on p.id=case when s.user_a=auth.uid() then s.user_b else s.user_a end left join live_locations l on l.user_id=p.id where (s.user_a=auth.uid() or s.user_b=auth.uid()) and s.stopped_at is null and s.expires_at>now(); $$;
create or replace function public.get_location_requests() returns table(id uuid,requester_id uuid,requester_nickname text,requester_avatar_url text,receiver_id uuid,receiver_nickname text,status text,duration_minutes int,created_at timestamptz) language sql security definer set search_path=public as $$ select r.id,r.requester_id,rp.nickname,rp.avatar_url,r.receiver_id,ap.nickname,r.status,r.duration_minutes,r.created_at from location_share_requests r join profiles rp on rp.id=r.requester_id join profiles ap on ap.id=r.receiver_id where r.requester_id=auth.uid() or r.receiver_id=auth.uid() order by r.created_at desc limit 100; $$;

create or replace function public.create_poll(p_room_id uuid,p_question text,p_options text[],p_multiple boolean,p_closes_at timestamptz) returns uuid language plpgsql security definer set search_path=public as $$ declare pid uuid; opt text; begin insert into polls(room_id,created_by,question,multiple,closes_at) values(p_room_id,auth.uid(),p_question,coalesce(p_multiple,false),p_closes_at) returning id into pid; foreach opt in array p_options loop if nullif(trim(opt),'') is not null then insert into poll_options(poll_id,label) values(pid,trim(opt)); end if; end loop; insert into chat_messages(room_id,sender_id,body,message_type) values(p_room_id,auth.uid(),p_question,'poll'); return pid; end $$;

alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.chat_rooms enable row level security;
alter table public.chat_room_members enable row level security;
alter table public.chat_messages enable row level security;
alter table public.message_reactions enable row level security;
alter table public.app_notifications enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.calendar_events enable row level security;
alter table public.calendar_event_viewers enable row level security;
alter table public.calendar_event_comments enable row level security;
alter table public.calendar_event_rsvps enable row level security;
alter table public.work_shift_settings enable row level security;
alter table public.location_share_requests enable row level security;
alter table public.location_share_sessions enable row level security;
alter table public.live_locations enable row level security;
alter table public.polls enable row level security;
alter table public.poll_options enable row level security;
alter table public.poll_votes enable row level security;

create policy profiles_all on public.profiles for all using (auth.uid() is not null) with check (id=auth.uid());
create policy friendships_related on public.friendships for all using (requester_id=auth.uid() or addressee_id=auth.uid()) with check (requester_id=auth.uid() or addressee_id=auth.uid());
create policy rooms_member on public.chat_rooms for all using (exists(select 1 from chat_room_members m where m.room_id=id and m.user_id=auth.uid()) or created_by=auth.uid()) with check (auth.uid() is not null);
create policy members_related on public.chat_room_members for all using (user_id=auth.uid() or exists(select 1 from chat_room_members m where m.room_id=chat_room_members.room_id and m.user_id=auth.uid())) with check (auth.uid() is not null);
create policy messages_member on public.chat_messages for all using (exists(select 1 from chat_room_members m where m.room_id=chat_messages.room_id and m.user_id=auth.uid())) with check (sender_id=auth.uid());
create policy reactions_room on public.message_reactions for all using (user_id=auth.uid() or exists(select 1 from chat_messages cm join chat_room_members m on m.room_id=cm.room_id where cm.id=message_reactions.message_id and m.user_id=auth.uid())) with check (user_id=auth.uid());
create policy notifications_own on public.app_notifications for all using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy push_own on public.push_subscriptions for all using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy calendar_auth on public.calendar_events for all using (auth.uid() is not null) with check (owner_id=auth.uid());
create policy calendar_viewers_auth on public.calendar_event_viewers for all using (auth.uid() is not null) with check (auth.uid() is not null);
create policy calendar_comments_auth on public.calendar_event_comments for all using (auth.uid() is not null) with check (user_id=auth.uid());
create policy calendar_rsvp_own on public.calendar_event_rsvps for all using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy shift_own on public.work_shift_settings for all using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy loc_req_related on public.location_share_requests for all using (requester_id=auth.uid() or receiver_id=auth.uid()) with check (requester_id=auth.uid() or receiver_id=auth.uid());
create policy loc_session_related on public.location_share_sessions for all using (user_a=auth.uid() or user_b=auth.uid()) with check (user_a=auth.uid() or user_b=auth.uid());
create policy live_location_visible on public.live_locations for select using (user_id=auth.uid() or exists(select 1 from location_share_sessions s where s.stopped_at is null and s.expires_at>now() and ((s.user_a=auth.uid() and s.user_b=live_locations.user_id) or (s.user_b=auth.uid() and s.user_a=live_locations.user_id))));
create policy live_location_own_insert on public.live_locations for insert with check (user_id=auth.uid());
create policy live_location_own_update on public.live_locations for update using (user_id=auth.uid());
create policy polls_member on public.polls for all using (exists(select 1 from chat_room_members m where m.room_id=polls.room_id and m.user_id=auth.uid())) with check (created_by=auth.uid());
create policy poll_options_member on public.poll_options for all using (exists(select 1 from polls p join chat_room_members m on m.room_id=p.room_id where p.id=poll_options.poll_id and m.user_id=auth.uid())) with check (true);
create policy poll_votes_own on public.poll_votes for all using (user_id=auth.uid()) with check (user_id=auth.uid());

insert into storage.buckets (id,name,public) values ('chat_uploads','chat_uploads',true) on conflict(id) do update set public=true;
drop policy if exists chat_uploads_select on storage.objects;
create policy chat_uploads_select on storage.objects for select using (bucket_id='chat_uploads');
drop policy if exists chat_uploads_insert on storage.objects;
create policy chat_uploads_insert on storage.objects for insert with check (bucket_id='chat_uploads' and auth.uid() is not null);
drop policy if exists chat_uploads_update on storage.objects;
create policy chat_uploads_update on storage.objects for update using (bucket_id='chat_uploads' and auth.uid() is not null);
drop policy if exists chat_uploads_delete on storage.objects;
create policy chat_uploads_delete on storage.objects for delete using (bucket_id='chat_uploads' and auth.uid() is not null);
