create extension if not exists pgcrypto;

create table if not exists public.profiles (id uuid primary key references auth.users(id) on delete cascade);
alter table public.profiles
  add column if not exists email text,
  add column if not exists nickname text not null default '익명',
  add column if not exists avatar_url text,
  add column if not exists status_message text default '',
  add column if not exists birthday date,
  add column if not exists dark_mode boolean not null default false,
  add column if not exists font_size text not null default 'normal',
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create table if not exists public.friendships (id uuid primary key default gen_random_uuid());
alter table public.friendships
  add column if not exists requester_id uuid references public.profiles(id) on delete cascade,
  add column if not exists addressee_id uuid references public.profiles(id) on delete cascade,
  add column if not exists status text not null default 'pending',
  add column if not exists favorite_by_requester boolean not null default false,
  add column if not exists favorite_by_addressee boolean not null default false,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();
create unique index if not exists friendships_unique_pair_idx on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

create table if not exists public.chat_rooms (id uuid primary key default gen_random_uuid());
alter table public.chat_rooms
  add column if not exists room_type text not null default 'direct',
  add column if not exists title text,
  add column if not exists avatar_url text,
  add column if not exists direct_key text,
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();
create unique index if not exists chat_rooms_direct_key_unique_idx on public.chat_rooms(direct_key) where direct_key is not null;

create table if not exists public.chat_room_members (id uuid primary key default gen_random_uuid());
alter table public.chat_room_members
  add column if not exists room_id uuid references public.chat_rooms(id) on delete cascade,
  add column if not exists user_id uuid references public.profiles(id) on delete cascade,
  add column if not exists role text not null default 'member',
  add column if not exists muted boolean not null default false,
  add column if not exists pinned boolean not null default false,
  add column if not exists last_read_at timestamptz,
  add column if not exists joined_at timestamptz not null default now();
create unique index if not exists chat_room_members_unique_idx on public.chat_room_members(room_id, user_id);

create table if not exists public.chat_messages (id uuid primary key default gen_random_uuid());
alter table public.chat_messages
  add column if not exists room_id uuid references public.chat_rooms(id) on delete cascade,
  add column if not exists sender_id uuid references public.profiles(id) on delete set null,
  add column if not exists body text,
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
  add column if not exists deleted_at timestamptz,
  add column if not exists created_at timestamptz not null default now();
create index if not exists chat_messages_room_created_idx on public.chat_messages(room_id, created_at desc);

create table if not exists public.message_reactions (id uuid primary key default gen_random_uuid(), message_id uuid references public.chat_messages(id) on delete cascade, user_id uuid references public.profiles(id) on delete cascade, emoji text not null, created_at timestamptz default now());
create unique index if not exists message_reactions_unique_idx on public.message_reactions(message_id,user_id,emoji);

create table if not exists public.app_notifications (id uuid primary key default gen_random_uuid());
alter table public.app_notifications
  add column if not exists user_id uuid references public.profiles(id) on delete cascade,
  add column if not exists type text not null default 'general',
  add column if not exists title text not null default '알림',
  add column if not exists body text,
  add column if not exists data jsonb not null default '{}'::jsonb,
  add column if not exists read_at timestamptz,
  add column if not exists created_at timestamptz not null default now();

create table if not exists public.push_subscriptions (id uuid primary key default gen_random_uuid());
alter table public.push_subscriptions
  add column if not exists user_id uuid references public.profiles(id) on delete cascade,
  add column if not exists endpoint text,
  add column if not exists subscription jsonb,
  add column if not exists user_agent text,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();
create unique index if not exists push_subscriptions_endpoint_idx on public.push_subscriptions(endpoint);

create table if not exists public.calendar_events (id uuid primary key default gen_random_uuid());
alter table public.calendar_events
  add column if not exists owner_id uuid references public.profiles(id) on delete cascade,
  add column if not exists title text not null default '일정',
  add column if not exists memo text,
  add column if not exists start_at timestamptz not null default now(),
  add column if not exists end_at timestamptz,
  add column if not exists all_day boolean not null default false,
  add column if not exists color text not null default '#FEE500',
  add column if not exists share_mode text not null default 'private',
  add column if not exists group_room_id uuid,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create table if not exists public.work_shift_settings (user_id uuid primary key references public.profiles(id) on delete cascade);
alter table public.work_shift_settings
  add column if not exists mode text not null default 'normal',
  add column if not exists shift_team int default 1,
  add column if not exists anchor_date date not null default date '2026-01-01',
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create table if not exists public.location_share_requests (id uuid primary key default gen_random_uuid());
alter table public.location_share_requests
  add column if not exists requester_id uuid references public.profiles(id) on delete cascade,
  add column if not exists receiver_id uuid references public.profiles(id) on delete cascade,
  add column if not exists status text not null default 'pending',
  add column if not exists duration_minutes int not null default 60,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists responded_at timestamptz;
create table if not exists public.location_share_sessions (id uuid primary key default gen_random_uuid());
alter table public.location_share_sessions
  add column if not exists request_id uuid references public.location_share_requests(id) on delete set null,
  add column if not exists user_a uuid references public.profiles(id) on delete cascade,
  add column if not exists user_b uuid references public.profiles(id) on delete cascade,
  add column if not exists started_at timestamptz not null default now(),
  add column if not exists expires_at timestamptz not null default now(),
  add column if not exists stopped_at timestamptz;
create table if not exists public.live_locations (user_id uuid primary key references public.profiles(id) on delete cascade, latitude double precision not null, longitude double precision not null, accuracy double precision, heading double precision, speed double precision, updated_at timestamptz not null default now());

-- drop recursive policies on chat tables
DO $$
DECLARE p record;
BEGIN
  FOR p IN SELECT schemaname, tablename, policyname FROM pg_policies WHERE schemaname='public' AND tablename IN ('chat_room_members','chat_rooms','chat_messages') LOOP
    EXECUTE format('drop policy if exists %I on %I.%I', p.policyname, p.schemaname, p.tablename);
  END LOOP;
END $$;

alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.chat_rooms enable row level security;
alter table public.chat_room_members enable row level security;
alter table public.chat_messages enable row level security;
alter table public.message_reactions enable row level security;
alter table public.app_notifications enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.calendar_events enable row level security;
alter table public.work_shift_settings enable row level security;
alter table public.location_share_requests enable row level security;
alter table public.location_share_sessions enable row level security;
alter table public.live_locations enable row level security;

-- simple safe policies
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles' AND policyname='profiles_auth_all') THEN
    CREATE POLICY profiles_auth_all ON public.profiles FOR ALL USING (auth.uid() is not null) WITH CHECK (id = auth.uid());
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='friendships' AND policyname='friendships_related') THEN
    CREATE POLICY friendships_related ON public.friendships FOR ALL USING (requester_id=auth.uid() OR addressee_id=auth.uid()) WITH CHECK (requester_id=auth.uid() OR addressee_id=auth.uid());
  END IF;
END $$;
CREATE POLICY chat_room_members_select_v5 ON public.chat_room_members FOR SELECT USING (auth.uid() is not null);
CREATE POLICY chat_room_members_insert_v5 ON public.chat_room_members FOR INSERT WITH CHECK (auth.uid() is not null);
CREATE POLICY chat_room_members_update_v5 ON public.chat_room_members FOR UPDATE USING (user_id=auth.uid()) WITH CHECK (user_id=auth.uid());
CREATE POLICY chat_room_members_delete_v5 ON public.chat_room_members FOR DELETE USING (user_id=auth.uid());
CREATE POLICY chat_rooms_select_v5 ON public.chat_rooms FOR SELECT USING (auth.uid() is not null);
CREATE POLICY chat_rooms_insert_v5 ON public.chat_rooms FOR INSERT WITH CHECK (auth.uid() is not null);
CREATE POLICY chat_rooms_update_v5 ON public.chat_rooms FOR UPDATE USING (auth.uid() is not null);
CREATE POLICY chat_messages_select_v5 ON public.chat_messages FOR SELECT USING (auth.uid() is not null);
CREATE POLICY chat_messages_insert_v5 ON public.chat_messages FOR INSERT WITH CHECK (sender_id=auth.uid());
CREATE POLICY chat_messages_update_v5 ON public.chat_messages FOR UPDATE USING (sender_id=auth.uid());
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='app_notifications' AND policyname='notifications_own_v5') THEN
    CREATE POLICY notifications_own_v5 ON public.app_notifications FOR ALL USING (user_id=auth.uid()) WITH CHECK (user_id=auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='push_subscriptions' AND policyname='push_own_v5') THEN
    CREATE POLICY push_own_v5 ON public.push_subscriptions FOR ALL USING (user_id=auth.uid()) WITH CHECK (user_id=auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='calendar_events' AND policyname='calendar_auth_select_v5') THEN
    CREATE POLICY calendar_auth_select_v5 ON public.calendar_events FOR SELECT USING (auth.uid() is not null);
    CREATE POLICY calendar_own_insert_v5 ON public.calendar_events FOR INSERT WITH CHECK (owner_id=auth.uid());
    CREATE POLICY calendar_own_update_v5 ON public.calendar_events FOR UPDATE USING (owner_id=auth.uid());
    CREATE POLICY calendar_own_delete_v5 ON public.calendar_events FOR DELETE USING (owner_id=auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='work_shift_settings' AND policyname='work_own_v5') THEN
    CREATE POLICY work_own_v5 ON public.work_shift_settings FOR ALL USING (user_id=auth.uid()) WITH CHECK (user_id=auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='location_share_requests' AND policyname='loc_req_related_v5') THEN
    CREATE POLICY loc_req_related_v5 ON public.location_share_requests FOR ALL USING (requester_id=auth.uid() OR receiver_id=auth.uid()) WITH CHECK (requester_id=auth.uid() OR receiver_id=auth.uid());
    CREATE POLICY loc_sess_related_v5 ON public.location_share_sessions FOR ALL USING (user_a=auth.uid() OR user_b=auth.uid()) WITH CHECK (user_a=auth.uid() OR user_b=auth.uid());
    CREATE POLICY live_select_v5 ON public.live_locations FOR SELECT USING (auth.uid() is not null);
    CREATE POLICY live_insert_v5 ON public.live_locations FOR INSERT WITH CHECK (user_id=auth.uid());
    CREATE POLICY live_update_v5 ON public.live_locations FOR UPDATE USING (user_id=auth.uid());
  END IF;
END $$;

-- storage bucket
insert into storage.buckets (id, name, public) values ('chat_uploads','chat_uploads',true) on conflict (id) do update set public=true;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='chat_uploads_select_v5') THEN
    CREATE POLICY chat_uploads_select_v5 ON storage.objects FOR SELECT USING (bucket_id='chat_uploads');
    CREATE POLICY chat_uploads_insert_v5 ON storage.objects FOR INSERT WITH CHECK (bucket_id='chat_uploads' AND auth.uid() is not null);
    CREATE POLICY chat_uploads_update_v5 ON storage.objects FOR UPDATE USING (bucket_id='chat_uploads' AND auth.uid() is not null);
    CREATE POLICY chat_uploads_delete_v5 ON storage.objects FOR DELETE USING (bucket_id='chat_uploads' AND auth.uid() is not null);
  END IF;
END $$;

-- RPC functions
CREATE OR REPLACE FUNCTION public.get_my_friends()
returns table(user_id uuid,email text,nickname text,avatar_url text,status_message text,birthday date,favorite boolean,created_at timestamptz)
language sql security definer set search_path=public as $$
  select case when f.requester_id=auth.uid() then f.addressee_id else f.requester_id end,
         p.email,p.nickname,p.avatar_url,p.status_message,p.birthday,
         case when f.requester_id=auth.uid() then coalesce(f.favorite_by_requester,false) else coalesce(f.favorite_by_addressee,false) end,
         f.created_at
  from friendships f join profiles p on p.id=case when f.requester_id=auth.uid() then f.addressee_id else f.requester_id end
  where f.status='accepted' and (f.requester_id=auth.uid() or f.addressee_id=auth.uid())
  order by 7 desc, p.nickname asc;
$$;
CREATE OR REPLACE FUNCTION public.get_friend_requests()
returns table(friendship_id uuid,user_id uuid,email text,nickname text,avatar_url text,status_message text,created_at timestamptz)
language sql security definer set search_path=public as $$
  select f.id,p.id,p.email,p.nickname,p.avatar_url,p.status_message,f.created_at
  from friendships f join profiles p on p.id=f.requester_id
  where f.addressee_id=auth.uid() and f.status='pending' order by f.created_at desc;
$$;
CREATE OR REPLACE FUNCTION public.send_friend_request(p_addressee_id uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare v_me uuid:=auth.uid(); v_id uuid; v_status text;
begin
 if v_me is null then raise exception 'login required'; end if; if v_me=p_addressee_id then raise exception 'self request'; end if;
 select id,status into v_id,v_status from friendships where least(requester_id,addressee_id)=least(v_me,p_addressee_id) and greatest(requester_id,addressee_id)=greatest(v_me,p_addressee_id) limit 1;
 if v_id is not null then if v_status='accepted' or v_status='pending' then return v_id; end if; update friendships set requester_id=v_me,addressee_id=p_addressee_id,status='pending' where id=v_id; return v_id; end if;
 insert into friendships(requester_id,addressee_id,status) values(v_me,p_addressee_id,'pending') returning id into v_id;
 insert into app_notifications(user_id,type,title,body,data) values(p_addressee_id,'friend_request','친구 요청',coalesce((select nickname from profiles where id=v_me),'상대')||'님이 친구 요청을 보냈습니다.',jsonb_build_object('friendship_id',v_id));
 return v_id;
end $$;
CREATE OR REPLACE FUNCTION public.accept_friend_request(p_friendship_id uuid) returns void language sql security definer set search_path=public as $$ update friendships set status='accepted',updated_at=now() where id=p_friendship_id and addressee_id=auth.uid() and status='pending'; $$;
CREATE OR REPLACE FUNCTION public.reject_friend_request(p_friendship_id uuid) returns void language sql security definer set search_path=public as $$ update friendships set status='rejected',updated_at=now() where id=p_friendship_id and addressee_id=auth.uid(); $$;
CREATE OR REPLACE FUNCTION public.delete_friend(p_user_id uuid) returns void language sql security definer set search_path=public as $$ delete from friendships where status='accepted' and ((requester_id=auth.uid() and addressee_id=p_user_id) or (requester_id=p_user_id and addressee_id=auth.uid())); $$;
CREATE OR REPLACE FUNCTION public.block_user(p_user_id uuid) returns void language plpgsql security definer set search_path=public as $$ begin delete from friendships where least(requester_id,addressee_id)=least(auth.uid(),p_user_id) and greatest(requester_id,addressee_id)=greatest(auth.uid(),p_user_id); insert into friendships(requester_id,addressee_id,status) values(auth.uid(),p_user_id,'blocked'); end $$;
CREATE OR REPLACE FUNCTION public.get_or_create_direct_room(p_other_user_id uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare v_me uuid:=auth.uid(); v_key text; v_room uuid;
begin
 v_key:=least(v_me::text,p_other_user_id::text)||':'||greatest(v_me::text,p_other_user_id::text);
 select id into v_room from chat_rooms where direct_key=v_key;
 if v_room is null then insert into chat_rooms(room_type,direct_key,created_by) values('direct',v_key,v_me) returning id into v_room; end if;
 insert into chat_room_members(room_id,user_id,role) values(v_room,v_me,'member') on conflict do nothing;
 insert into chat_room_members(room_id,user_id,role) values(v_room,p_other_user_id,'member') on conflict do nothing;
 return v_room;
end $$;
CREATE OR REPLACE FUNCTION public.create_group_room(p_title text,p_member_ids uuid[]) returns uuid language plpgsql security definer set search_path=public as $$
declare v_me uuid:=auth.uid(); v_room uuid; v_uid uuid;
begin
 insert into chat_rooms(room_type,title,created_by) values('group',coalesce(nullif(trim(p_title),''),'그룹채팅'),v_me) returning id into v_room;
 insert into chat_room_members(room_id,user_id,role) values(v_room,v_me,'owner') on conflict do nothing;
 foreach v_uid in array coalesce(p_member_ids,array[]::uuid[]) loop if v_uid<>v_me then insert into chat_room_members(room_id,user_id,role) values(v_room,v_uid,'member') on conflict do nothing; end if; end loop;
 insert into chat_messages(room_id,sender_id,body,message_type) values(v_room,v_me,'그룹채팅방이 생성되었습니다.','system');
 return v_room;
end $$;
CREATE OR REPLACE FUNCTION public.get_my_chat_rooms()
returns table(room_id uuid,room_type text,title text,avatar_url text,last_message text,last_message_at timestamptz,unread_count bigint,pinned boolean,muted boolean)
language sql security definer set search_path=public as $$
 select r.id,r.room_type,
   case when r.room_type='direct' then coalesce(op.nickname,'채팅') else coalesce(r.title,'그룹채팅') end,
   case when r.room_type='direct' then op.avatar_url else r.avatar_url end,
   case when lm.deleted_at is not null then '삭제된 메시지' when lm.message_type='image' then '사진' when lm.message_type='file' then coalesce(lm.file_name,'파일') when lm.message_type='voice' then '음성 메시지' when lm.message_type='location' then '위치' else coalesce(lm.body,'') end,
   coalesce(lm.created_at,r.created_at),
   (select count(*) from chat_messages cm where cm.room_id=r.id and cm.sender_id is distinct from auth.uid() and cm.created_at>coalesce(my.last_read_at,'1970-01-01'::timestamptz)),
   my.pinned,my.muted
 from chat_room_members my join chat_rooms r on r.id=my.room_id
 left join lateral (select * from chat_messages m where m.room_id=r.id order by m.created_at desc limit 1) lm on true
 left join lateral (select p.* from chat_room_members om join profiles p on p.id=om.user_id where om.room_id=r.id and om.user_id<>auth.uid() limit 1) op on true
 where my.user_id=auth.uid() order by my.pinned desc, coalesce(lm.created_at,r.created_at) desc;
$$;
CREATE OR REPLACE FUNCTION public.get_room_members(p_room_id uuid)
returns table(user_id uuid,email text,nickname text,avatar_url text,status_message text,role text,muted boolean,pinned boolean,last_read_at timestamptz,joined_at timestamptz)
language sql security definer set search_path=public as $$
 select p.id,p.email,p.nickname,p.avatar_url,p.status_message,m.role,m.muted,m.pinned,m.last_read_at,m.joined_at
 from chat_room_members m join profiles p on p.id=m.user_id where m.room_id=p_room_id order by case m.role when 'owner' then 0 when 'admin' then 1 else 2 end,p.nickname;
$$;
CREATE OR REPLACE FUNCTION public.mark_room_read(p_room_id uuid) returns void language sql security definer set search_path=public as $$ update chat_room_members set last_read_at=now() where room_id=p_room_id and user_id=auth.uid(); $$;
CREATE OR REPLACE FUNCTION public.set_room_muted(p_room_id uuid,p_muted boolean) returns void language sql security definer set search_path=public as $$ update chat_room_members set muted=p_muted where room_id=p_room_id and user_id=auth.uid(); $$;
CREATE OR REPLACE FUNCTION public.set_room_pinned(p_room_id uuid,p_pinned boolean) returns void language sql security definer set search_path=public as $$ update chat_room_members set pinned=p_pinned where room_id=p_room_id and user_id=auth.uid(); $$;
CREATE OR REPLACE FUNCTION public.leave_room(p_room_id uuid) returns void language sql security definer set search_path=public as $$ delete from chat_room_members where room_id=p_room_id and user_id=auth.uid(); $$;
CREATE OR REPLACE FUNCTION public.edit_message(p_message_id uuid,p_body text) returns void language sql security definer set search_path=public as $$ update chat_messages set body=p_body,edited_at=now() where id=p_message_id and sender_id=auth.uid() and deleted_at is null; $$;
CREATE OR REPLACE FUNCTION public.delete_message(p_message_id uuid) returns void language sql security definer set search_path=public as $$ update chat_messages set body=null,deleted_at=now() where id=p_message_id and sender_id=auth.uid(); $$;
CREATE OR REPLACE FUNCTION public.get_my_notifications() returns table(id uuid,type text,title text,body text,data jsonb,read_at timestamptz,created_at timestamptz) language sql security definer set search_path=public as $$ select id,type,title,body,data,read_at,created_at from app_notifications where user_id=auth.uid() order by created_at desc limit 100; $$;
CREATE OR REPLACE FUNCTION public.mark_notification_read(p_id uuid) returns void language sql security definer set search_path=public as $$ update app_notifications set read_at=coalesce(read_at,now()) where id=p_id and user_id=auth.uid(); $$;
CREATE OR REPLACE FUNCTION public.get_calendar_events(p_from timestamptz,p_to timestamptz) returns table(id uuid,owner_id uuid,owner_nickname text,owner_avatar_url text,title text,memo text,start_at timestamptz,end_at timestamptz,all_day boolean,color text,share_mode text,group_room_id uuid,repeat_rule text,reminder_minutes int[],created_at timestamptz) language sql security definer set search_path=public as $$ select e.id,e.owner_id,p.nickname,p.avatar_url,e.title,e.memo,e.start_at,e.end_at,e.all_day,e.color,e.share_mode,e.group_room_id,null::text,null::int[],e.created_at from calendar_events e join profiles p on p.id=e.owner_id where e.start_at<p_to and coalesce(e.end_at,e.start_at)>=p_from and (e.owner_id=auth.uid() or e.share_mode in ('friends','public')) order by e.start_at; $$;
CREATE OR REPLACE FUNCTION public.save_calendar_event(p_id uuid,p_title text,p_start_at timestamptz,p_end_at timestamptz,p_all_day boolean,p_memo text,p_color text,p_share_mode text,p_group_room_id uuid,p_specific_user_ids uuid[]) returns uuid language plpgsql security definer set search_path=public as $$ declare v_id uuid; begin if p_id is null then insert into calendar_events(owner_id,title,start_at,end_at,all_day,memo,color,share_mode,group_room_id) values(auth.uid(),p_title,p_start_at,p_end_at,coalesce(p_all_day,false),p_memo,coalesce(p_color,'#FEE500'),coalesce(p_share_mode,'private'),p_group_room_id) returning id into v_id; else update calendar_events set title=p_title,start_at=p_start_at,end_at=p_end_at,all_day=coalesce(p_all_day,false),memo=p_memo,color=coalesce(p_color,'#FEE500'),share_mode=coalesce(p_share_mode,'private'),group_room_id=p_group_room_id,updated_at=now() where id=p_id and owner_id=auth.uid() returning id into v_id; end if; return v_id; end $$;
CREATE OR REPLACE FUNCTION public.delete_calendar_event(p_id uuid) returns void language sql security definer set search_path=public as $$ delete from calendar_events where id=p_id and owner_id=auth.uid(); $$;
CREATE OR REPLACE FUNCTION public.save_work_shift_settings(p_mode text,p_shift_team int,p_anchor_date date) returns void language sql security definer set search_path=public as $$ insert into work_shift_settings(user_id,mode,shift_team,anchor_date) values(auth.uid(),coalesce(p_mode,'normal'),p_shift_team,coalesce(p_anchor_date,date '2026-01-01')) on conflict(user_id) do update set mode=excluded.mode,shift_team=excluded.shift_team,anchor_date=excluded.anchor_date,updated_at=now(); $$;
CREATE OR REPLACE FUNCTION public.request_location_share(p_receiver_id uuid,p_duration_minutes int) returns uuid language plpgsql security definer set search_path=public as $$ declare v_id uuid; begin insert into location_share_requests(requester_id,receiver_id,duration_minutes) values(auth.uid(),p_receiver_id,greatest(15,least(coalesce(p_duration_minutes,60),480))) returning id into v_id; insert into app_notifications(user_id,type,title,body,data) values(p_receiver_id,'location_request','위치 공유 요청',coalesce((select nickname from profiles where id=auth.uid()),'상대')||'님이 위치 공유를 요청했습니다.',jsonb_build_object('request_id',v_id)); return v_id; end $$;
CREATE OR REPLACE FUNCTION public.respond_location_share(p_request_id uuid,p_accept boolean) returns uuid language plpgsql security definer set search_path=public as $$ declare r location_share_requests%rowtype; v_id uuid; begin select * into r from location_share_requests where id=p_request_id and receiver_id=auth.uid() and status='pending'; if p_accept then update location_share_requests set status='accepted',responded_at=now() where id=p_request_id; insert into location_share_sessions(request_id,user_a,user_b,expires_at) values(p_request_id,r.requester_id,r.receiver_id,now()+make_interval(mins=>r.duration_minutes)) returning id into v_id; return v_id; else update location_share_requests set status='rejected',responded_at=now() where id=p_request_id; return null; end if; end $$;
CREATE OR REPLACE FUNCTION public.upsert_live_location(p_latitude double precision,p_longitude double precision,p_accuracy double precision,p_heading double precision,p_speed double precision) returns void language sql security definer set search_path=public as $$ insert into live_locations(user_id,latitude,longitude,accuracy,heading,speed,updated_at) values(auth.uid(),p_latitude,p_longitude,p_accuracy,p_heading,p_speed,now()) on conflict(user_id) do update set latitude=excluded.latitude,longitude=excluded.longitude,accuracy=excluded.accuracy,heading=excluded.heading,speed=excluded.speed,updated_at=now(); $$;
CREATE OR REPLACE FUNCTION public.get_visible_locations() returns table(session_id uuid,user_id uuid,nickname text,avatar_url text,latitude double precision,longitude double precision,accuracy double precision,heading double precision,speed double precision,updated_at timestamptz,expires_at timestamptz,stopped_at timestamptz) language sql security definer set search_path=public as $$ select s.id,p.id,p.nickname,p.avatar_url,l.latitude,l.longitude,l.accuracy,l.heading,l.speed,l.updated_at,s.expires_at,s.stopped_at from location_share_sessions s join profiles p on p.id=case when s.user_a=auth.uid() then s.user_b else s.user_a end left join live_locations l on l.user_id=p.id where (s.user_a=auth.uid() or s.user_b=auth.uid()) and s.stopped_at is null and s.expires_at>now(); $$;
CREATE OR REPLACE FUNCTION public.get_location_requests() returns table(id uuid,requester_id uuid,requester_nickname text,requester_avatar_url text,receiver_id uuid,receiver_nickname text,status text,duration_minutes int,created_at timestamptz) language sql security definer set search_path=public as $$ select r.id,r.requester_id,rp.nickname,rp.avatar_url,r.receiver_id,ap.nickname,r.status,r.duration_minutes,r.created_at from location_share_requests r join profiles rp on rp.id=r.requester_id join profiles ap on ap.id=r.receiver_id where r.requester_id=auth.uid() or r.receiver_id=auth.uid() order by r.created_at desc; $$;
