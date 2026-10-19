create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null check (char_length(username) between 3 and 30),
  display_name text not null default 'Novo usuário',
  bio text not null default '',
  created_at timestamptz not null default now()
);
create table public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
create table public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followed_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followed_id),
  check (follower_id <> followed_id)
);
create table public.likes (
  user_id uuid not null references public.profiles(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);
create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 220),
  created_at timestamptz not null default now()
);
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  post_id uuid references public.posts(id) on delete cascade,
  kind text not null check (kind in ('follow','like','comment')),
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index posts_created_at_idx on public.posts(created_at desc);
create index posts_user_created_idx on public.posts(user_id, created_at desc);
create index comments_post_created_idx on public.comments(post_id, created_at);
create index notifications_recipient_created_idx on public.notifications(recipient_id, created_at desc);

alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.follows enable row level security;
alter table public.likes enable row level security;
alter table public.comments enable row level security;
alter table public.notifications enable row level security;

grant select on public.profiles, public.posts, public.follows, public.likes, public.comments to anon, authenticated;
grant insert, update on public.profiles to authenticated;
grant insert, delete on public.posts to authenticated;
grant insert, delete on public.follows to authenticated;
grant insert, delete on public.likes to authenticated;
grant insert, delete on public.comments to authenticated;
grant select, update, delete on public.notifications to authenticated;

create policy "profiles readable by everyone" on public.profiles for select to anon, authenticated using (true);
create policy "users insert own profile" on public.profiles for insert to authenticated with check ((select auth.uid()) = id);
create policy "users update own profile" on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy "posts readable by everyone" on public.posts for select to anon, authenticated using (true);
create policy "users create own posts" on public.posts for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "users delete own posts" on public.posts for delete to authenticated using ((select auth.uid()) = user_id);
create policy "follows readable by everyone" on public.follows for select to anon, authenticated using (true);
create policy "users follow as themselves" on public.follows for insert to authenticated with check ((select auth.uid()) = follower_id);
create policy "users unfollow as themselves" on public.follows for delete to authenticated using ((select auth.uid()) = follower_id);
create policy "likes readable by everyone" on public.likes for select to anon, authenticated using (true);
create policy "users like as themselves" on public.likes for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "users remove own likes" on public.likes for delete to authenticated using ((select auth.uid()) = user_id);
create policy "comments readable by everyone" on public.comments for select to anon, authenticated using (true);
create policy "users create own comments" on public.comments for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "users delete own comments" on public.comments for delete to authenticated using ((select auth.uid()) = user_id);
create policy "users read own notifications" on public.notifications for select to authenticated using ((select auth.uid()) = recipient_id);
create policy "users update own notifications" on public.notifications for update to authenticated using ((select auth.uid()) = recipient_id) with check ((select auth.uid()) = recipient_id);
create policy "users delete own notifications" on public.notifications for delete to authenticated using ((select auth.uid()) = recipient_id);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare base_username text; candidate text;
begin
  base_username := lower(regexp_replace(coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1), 'user'), '[^a-zA-Z0-9_]', '', 'g'));
  if char_length(base_username) < 3 then base_username := 'user'; end if;
  candidate := left(base_username, 22) || '_' || substr(replace(new.id::text, '-', ''), 1, 7);
  insert into public.profiles (id, username, display_name, bio)
  values (new.id, candidate, coalesce(nullif(new.raw_user_meta_data->>'display_name',''), split_part(coalesce(new.email,''),'@',1), 'Novo usuário'), '')
  on conflict (id) do nothing;
  return new;
end;
$$;
create trigger on_auth_user_created_minimo after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.create_minimo_notification()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare post_owner uuid; actor uuid; recipient uuid; notification_kind text; target_post uuid;
begin
  if tg_table_name = 'follows' then
    actor := new.follower_id; recipient := new.followed_id; notification_kind := 'follow'; target_post := null;
  elsif tg_table_name = 'likes' then
    actor := new.user_id; target_post := new.post_id;
    select user_id into post_owner from public.posts where id = new.post_id;
    recipient := post_owner; notification_kind := 'like';
  elsif tg_table_name = 'comments' then
    actor := new.user_id; target_post := new.post_id;
    select user_id into post_owner from public.posts where id = new.post_id;
    recipient := post_owner; notification_kind := 'comment';
  else return new;
  end if;
  if recipient is not null and actor is distinct from recipient then
    insert into public.notifications (recipient_id, actor_id, post_id, kind)
    values (recipient, actor, target_post, notification_kind);
  end if;
  return new;
end;
$$;
create trigger notify_minimo_follow after insert on public.follows for each row execute function public.create_minimo_notification();
create trigger notify_minimo_like after insert on public.likes for each row execute function public.create_minimo_notification();
create trigger notify_minimo_comment after insert on public.comments for each row execute function public.create_minimo_notification();

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.create_minimo_notification() from public, anon, authenticated;
