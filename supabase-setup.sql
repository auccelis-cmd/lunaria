-- ============================================================
-- 月汐 Lunaria · Supabase 設定（放進「插單」的專案執行）
-- 用法：Supabase → SQL Editor → New query → 整段貼上 → Run
-- 所有東西都以 lunaria_ 開頭，不會動到插單原本的資料表。
-- 可以重複執行，不會重複建立。
-- ============================================================

-- 1. 資料表 ---------------------------------------------------
create table if not exists public.lunaria_profiles (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  period_len   int  not null default 5  check (period_len between 2 and 10),
  cycle_mode   text not null default 'auto' check (cycle_mode in ('auto','manual')),
  cycle_manual int  not null default 28 check (cycle_manual between 20 and 45),
  prefs        jsonb not null default '{}'::jsonb,
  share        jsonb not null default '{"phase":true,"flow":false,"intimacy":false,"details":false}'::jsonb,
  updated_at   timestamptz not null default now()
);

create table if not exists public.lunaria_starts (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  day     date not null,
  primary key (user_id, day)
);

create table if not exists public.lunaria_logs (
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  day        date not null,
  flow       text,
  other      text,
  discharge  text,
  intimacy   text,
  note       text,
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

-- 一個人只能分享給一位伴侶（owner = 分享週期的人）
create table if not exists public.lunaria_links (
  owner      uuid primary key references auth.users(id) on delete cascade,
  partner    uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (owner <> partner)
);

create table if not exists public.lunaria_invites (
  code       text primary key,
  owner      uuid not null unique references auth.users(id) on delete cascade,
  expires_at timestamptz not null
);

-- 2. 權限（RLS）：自己的資料只有自己能讀寫 -----------------------
alter table public.lunaria_profiles enable row level security;
alter table public.lunaria_starts   enable row level security;
alter table public.lunaria_logs     enable row level security;
alter table public.lunaria_links    enable row level security;
alter table public.lunaria_invites  enable row level security;

drop policy if exists "lunaria own profile" on public.lunaria_profiles;
create policy "lunaria own profile" on public.lunaria_profiles
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "lunaria own starts" on public.lunaria_starts;
create policy "lunaria own starts" on public.lunaria_starts
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "lunaria own logs" on public.lunaria_logs;
create policy "lunaria own logs" on public.lunaria_logs
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "lunaria see own link" on public.lunaria_links;
create policy "lunaria see own link" on public.lunaria_links
  for select to authenticated using (owner = auth.uid() or partner = auth.uid());
-- lunaria_invites 不開任何政策：只能透過下面的函式操作。
-- 伴侶「不能」直接讀你的表，只能透過 lunaria_partner_view()，
-- 而那個函式只回傳你在 App 裡勾選分享的欄位。

-- 3. 函式 -----------------------------------------------------
create or replace function public.lunaria_create_invite()
returns text language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  c := upper(substr(md5(gen_random_uuid()::text), 1, 6));
  insert into lunaria_invites(code, owner, expires_at)
    values (c, auth.uid(), now() + interval '24 hours')
    on conflict (owner) do update set code = excluded.code, expires_at = excluded.expires_at;
  return c;
end $$;

create or replace function public.lunaria_accept_invite(p_code text)
returns text language plpgsql security definer set search_path = public as $$
declare o uuid; n text;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select owner into o from lunaria_invites
    where code = upper(trim(p_code)) and expires_at > now();
  if o is null then raise exception '邀請碼無效或已過期'; end if;
  if o = auth.uid() then raise exception '不能和自己連動'; end if;
  insert into lunaria_links(owner, partner) values (o, auth.uid())
    on conflict (owner) do update set partner = excluded.partner, created_at = now();
  delete from lunaria_invites where owner = o;
  select nullif(display_name, '') into n from lunaria_profiles where user_id = o;
  return coalesce(n, '對方');
end $$;

create or replace function public.lunaria_unlink()
returns void language sql security definer set search_path = public as $$
  delete from lunaria_links where owner = auth.uid() or partner = auth.uid();
$$;

create or replace function public.lunaria_link_info()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'as_owner', (select json_build_object('partner_name', coalesce(nullif(p.display_name, ''), '伴侶'))
                   from lunaria_links l left join lunaria_profiles p on p.user_id = l.partner
                  where l.owner = auth.uid()),
    'as_partner', (select json_build_object('owner_name', coalesce(nullif(p.display_name, ''), '伴侶'))
                     from lunaria_links l left join lunaria_profiles p on p.user_id = l.owner
                    where l.partner = auth.uid())
  );
$$;

create or replace function public.lunaria_partner_view()
returns json language plpgsql stable security definer set search_path = public as $$
declare o uuid; pr lunaria_profiles; sh jsonb;
  ph boolean; fl boolean; it boolean; dt boolean;
begin
  select owner into o from lunaria_links where partner = auth.uid();
  if o is null then return null; end if;
  select * into pr from lunaria_profiles where user_id = o;
  sh := coalesce(pr.share, '{}'::jsonb);
  ph := coalesce((sh->>'phase')::boolean, false);
  fl := coalesce((sh->>'flow')::boolean, false);
  it := coalesce((sh->>'intimacy')::boolean, false);
  dt := coalesce((sh->>'details')::boolean, false);
  return json_build_object(
    'name', coalesce(nullif(pr.display_name, ''), '伴侶'),
    'share', json_build_object('phase', ph, 'flow', fl, 'intimacy', it, 'details', dt),
    'period_len',   case when ph then pr.period_len end,
    'cycle_mode',   case when ph then pr.cycle_mode end,
    'cycle_manual', case when ph then pr.cycle_manual end,
    'starts', case when ph then
                (select coalesce(json_agg(day order by day), '[]'::json)
                   from lunaria_starts where user_id = o and day > current_date - 400)
              else '[]'::json end,
    'logs', (select coalesce(json_object_agg(day, json_strip_nulls(json_build_object(
                'flow',      case when fl then flow end,
                'intimacy',  case when it then intimacy end,
                'other',     case when dt then other end,
                'discharge', case when dt then discharge end,
                'note',      case when dt then note end))), '{}'::json)
               from lunaria_logs where user_id = o and day > current_date - 120)
  );
end $$;

-- 伴侶記錄親密關係（只有你開放「親密關係」時才允許）
create or replace function public.lunaria_partner_set_intimacy(p_day date, p_value text)
returns void language plpgsql security definer set search_path = public as $$
declare o uuid; sh jsonb;
begin
  select owner into o from lunaria_links where partner = auth.uid();
  if o is null then raise exception '尚未連動'; end if;
  select share into sh from lunaria_profiles where user_id = o;
  if not coalesce((sh->>'intimacy')::boolean, false) then raise exception '對方沒有開放親密關係紀錄'; end if;
  if p_value is not null and p_value not in ('有防護', '無防護') then raise exception '選項不正確'; end if;
  insert into lunaria_logs(user_id, day, intimacy, updated_at) values (o, p_day, p_value, now())
    on conflict (user_id, day) do update set intimacy = excluded.intimacy, updated_at = now();
end $$;

revoke all on function public.lunaria_create_invite()                     from public, anon;
revoke all on function public.lunaria_accept_invite(text)                  from public, anon;
revoke all on function public.lunaria_unlink()                             from public, anon;
revoke all on function public.lunaria_link_info()                          from public, anon;
revoke all on function public.lunaria_partner_view()                       from public, anon;
revoke all on function public.lunaria_partner_set_intimacy(date, text)     from public, anon;
grant execute on function public.lunaria_create_invite()                   to authenticated;
grant execute on function public.lunaria_accept_invite(text)               to authenticated;
grant execute on function public.lunaria_unlink()                          to authenticated;
grant execute on function public.lunaria_link_info()                       to authenticated;
grant execute on function public.lunaria_partner_view()                    to authenticated;
grant execute on function public.lunaria_partner_set_intimacy(date, text)  to authenticated;
