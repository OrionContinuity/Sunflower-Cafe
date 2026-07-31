-- ═══ Sunflower Café — site backend. Run ONCE in the WebApps project's SQL editor ═══
--
-- Project: WebApps (unfjnmrjmidrfmmtyhpe) — shared with gbc_* and ar_*.
-- Everything here is prefixed sf_ so the three sites never collide.
--
-- Security model (inherited from GBC → Ariana → the NEXUS hardening):
--   • public tables are READ-ONLY to anon — zero write policies, ever
--   • every write goes through a SECURITY DEFINER RPC gated on a bcrypt passphrase
--   • search_path is pinned on every function
--   • Supabase default-privs auto-grant EXECUTE — we revoke PUBLIC/authenticated
--     explicitly, then re-grant only anon + service_role
--   • tables holding customer data (orders, events, auth attempts) get NO select
--     policy, so they are invisible to the anon key even though the site writes them
--   • prices are NEVER trusted from the browser — sf_submit_order re-prices every
--     line against sf_menu and computes the total itself
--
create extension if not exists pgcrypto with schema extensions;

-- ═══════════════════════════════════════════════════════════════════════
--  1. CONTENT — editable page copy + hours, keyed by section
-- ═══════════════════════════════════════════════════════════════════════
create table if not exists public.sf_content (
  section    text primary key,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.sf_content enable row level security;
create policy sf_content_read on public.sf_content for select using (true);

-- ═══════════════════════════════════════════════════════════════════════
--  2. CATEGORIES — the menu's sections, and their order on the page
-- ═══════════════════════════════════════════════════════════════════════
create table if not exists public.sf_categories (
  key        text primary key,                  -- 'breakfast', 'lunch', 'bar', …
  label      text not null,
  blurb      text,
  sort       int  not null default 100,
  active     boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.sf_categories enable row level security;
create policy sf_categories_read on public.sf_categories for select using (true);

-- ═══════════════════════════════════════════════════════════════════════
--  3. MENU — the items themselves
--     price_cents = 0 means "not priced yet": the item still shows on the
--     menu, but it cannot be added to a pre-order (see sf_submit_order).
-- ═══════════════════════════════════════════════════════════════════════
create table if not exists public.sf_menu (
  id          bigint generated always as identity primary key,
  slug        text unique not null,
  name        text not null,
  category    text not null default 'breakfast' references public.sf_categories(key)
                on update cascade on delete restrict,
  blurb       text,                             -- one line, shows on the card
  detail      text,                             -- longer copy, shows when expanded
  price_cents int  not null default 0,
  unit        text,                             -- 'half order', 'cup', 'bowl', … null = plain
  image       text,                             -- https URL or data-URL; null = SVG illustration
  glyph       text default 'plate',             -- fallback illustration key
  badge       text,                             -- 'Friday only', 'House favorite', …
  dietary     jsonb not null default '[]'::jsonb,  -- ['vegetarian','gluten-free',…]
  sort        int  not null default 100,
  featured    boolean not null default false,
  active      boolean not null default true,
  updated_at  timestamptz not null default now()
);
alter table public.sf_menu enable row level security;
create policy sf_menu_read on public.sf_menu for select using (true);
create index if not exists sf_menu_sort_idx on public.sf_menu (active, category, sort);

-- ═══════════════════════════════════════════════════════════════════════
--  4. PHOTOS — hero album + slot images
-- ═══════════════════════════════════════════════════════════════════════
create table if not exists public.sf_photos (
  id         bigint generated always as identity primary key,
  slot       text not null default 'album',     -- 'album' | 'room' | 'item-<slug>'
  url        text not null,
  alt        text not null default '',
  sort       int  not null default 100,
  active     boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.sf_photos enable row level security;
create policy sf_photos_read on public.sf_photos for select using (true);

-- ═══════════════════════════════════════════════════════════════════════
--  5. ORDERS — customer data. NO select policy: invisible to the anon key.
--     Writes happen only through sf_submit_order (honeypot + rate limited).
-- ═══════════════════════════════════════════════════════════════════════
create table if not exists public.sf_orders (
  id           bigint generated always as identity primary key,
  name         text not null,
  phone        text,
  email        text,
  pickup_date  text,
  pickup_time  text,
  items        jsonb not null default '[]'::jsonb,   -- server-priced, see below
  total_cents  int not null default 0,               -- computed server-side
  notes        text,
  status       text not null default 'new',          -- new | confirmed | ready | done | cancelled
  ip           text,
  ua           text,
  created_at   timestamptz not null default now()
);
alter table public.sf_orders enable row level security;
-- deliberately no policies

-- ═══════════════════════════════════════════════════════════════════════
--  6. EVENTS — first-party analytics. Also invisible to anon.
-- ═══════════════════════════════════════════════════════════════════════
create table if not exists public.sf_events (
  id         bigint generated always as identity primary key,
  type       text not null,
  path       text, ref text, sid text,
  meta       jsonb not null default '{}'::jsonb,
  ip         text, ua text,
  created_at timestamptz not null default now()
);
alter table public.sf_events enable row level security;
create index if not exists sf_events_created_idx on public.sf_events (created_at);
create index if not exists sf_events_type_idx    on public.sf_events (type);

-- ═══════════════════════════════════════════════════════════════════════
--  7. ADMIN passphrase (bcrypt at rest). Invisible to anon: no policies.
--     SET IT: replace CHANGE-ME-NOW below. Re-run this insert to rotate.
-- ═══════════════════════════════════════════════════════════════════════
create table if not exists public.sf_admin (
  id int primary key default 1,
  pass_hash text not null
);
alter table public.sf_admin enable row level security;
insert into public.sf_admin (id, pass_hash)
values (1, extensions.crypt('CHANGE-ME-NOW', extensions.gen_salt('bf', 10)))
on conflict (id) do update set pass_hash = excluded.pass_hash;

create or replace function public.sf_check_admin(p_pass text)
returns boolean language sql stable security definer
set search_path to 'public','extensions','pg_temp' as $$
  select exists (
    select 1 from public.sf_admin
    where id = 1 and pass_hash = extensions.crypt(coalesce(p_pass,''), pass_hash)
  );
$$;

-- ═══════════════════════════════════════════════════════════════════════
--  8. LOGIN — rate limited, so the passphrase cannot be brute-forced.
--     sf_check_admin itself is internal-only (see grants) so it can never be
--     used as an unthrottled passphrase oracle.
-- ═══════════════════════════════════════════════════════════════════════
create table if not exists public.sf_auth_attempts (
  id         bigint generated always as identity primary key,
  ip         text,
  ok         boolean not null,
  created_at timestamptz not null default now()
);
alter table public.sf_auth_attempts enable row level security;
-- no policies: invisible to anon
create index if not exists sf_auth_attempts_ip_idx
  on public.sf_auth_attempts (ip, created_at desc);

create or replace function public.sf_admin_login(p_pass text)
returns jsonb language plpgsql security definer
set search_path to 'public','extensions','pg_temp' as $$
declare v_ip text; v_fails int; v_ok boolean;
begin
  begin
    v_ip := coalesce(
      current_setting('request.headers', true)::json->>'cf-connecting-ip',
      current_setting('request.headers', true)::json->>'x-real-ip');
  exception when others then v_ip := null;
  end;

  select count(*) into v_fails
    from public.sf_auth_attempts
   where ok = false
     and ip is not distinct from v_ip
     and created_at > now() - interval '15 minutes';

  if v_fails >= 8 then
    return jsonb_build_object('ok', false, 'locked', true);
  end if;

  v_ok := public.sf_check_admin(p_pass);
  insert into public.sf_auth_attempts (ip, ok) values (v_ip, v_ok);

  if v_ok and v_ip is not null then
    delete from public.sf_auth_attempts
     where ip = v_ip and ok = false and created_at > now() - interval '15 minutes';
  end if;

  return jsonb_build_object('ok', v_ok, 'locked', false);
end $$;

-- ═══════════════════════════════════════════════════════════════════════
--  9. PUBLIC WRITE PATH — the pickup pre-order funnel
--     Prices are NEVER trusted from the client. Unpriced items (price_cents
--     = 0) are silently dropped, so a "call for price" item can never be
--     ordered for free.
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.sf_submit_order(p jsonb)
returns bigint language plpgsql security definer
set search_path to 'public','extensions','pg_temp' as $$
declare
  v_ip text; v_ua text; v_id bigint;
  v_name  text := left(btrim(coalesce(p->>'name','')),  120);
  v_phone text := left(btrim(coalesce(p->>'phone','')),  40);
  v_email text := left(btrim(coalesce(p->>'email','')), 160);
  v_date  text := left(btrim(coalesce(p->>'pickup_date','')), 40);
  v_items jsonb := coalesce(p->'items', '[]'::jsonb);
  v_clean jsonb := '[]'::jsonb;
  v_total int := 0;
  v_line  jsonb;
  v_qty   int;
  v_item  record;
begin
  -- honeypot: a hidden "website" field. Bots fill it. Pretend success.
  if coalesce(p->>'website','') <> '' then return 0; end if;

  if length(v_name) < 2 then raise exception 'invalid_name'; end if;
  if v_phone = '' and v_email = '' then raise exception 'contact_required'; end if;
  if jsonb_array_length(v_items) = 0 then raise exception 'empty_order'; end if;
  if jsonb_array_length(v_items) > 40 then raise exception 'too_many_items'; end if;

  -- pickup date must be a real date, today or within the next 30 days.
  -- (Which days the café is actually open is content, not schema — the page
  -- enforces that from sf_content so changing hours never needs a migration.)
  if v_date <> '' then
    begin
      if v_date::date < (now() at time zone 'America/Chicago')::date
         or v_date::date > (now() at time zone 'America/Chicago')::date + 30 then
        raise exception 'bad_pickup_date';
      end if;
    exception when invalid_datetime_format or datetime_field_overflow then
      raise exception 'bad_pickup_date';
    end;
  end if;

  begin
    v_ip := coalesce(
      current_setting('request.headers', true)::json->>'cf-connecting-ip',
      current_setting('request.headers', true)::json->>'x-real-ip',
      split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1));
    v_ua := left(current_setting('request.headers', true)::json->>'user-agent', 300);
  exception when others then v_ip := null; v_ua := null;
  end;

  -- rate limits: per-IP hourly, and a global daily ceiling
  if v_ip is not null and (
       select count(*) from public.sf_orders
       where ip = v_ip and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'rate_limited';
  end if;
  if (select count(*) from public.sf_orders
      where created_at > now() - interval '1 day') >= 200 then
    raise exception 'rate_limited';
  end if;

  -- re-price every line from the menu; drop unknown, inactive and unpriced items
  for v_line in select * from jsonb_array_elements(v_items) loop
    v_qty := greatest(1, least(coalesce((v_line->>'qty')::int, 1), 99));
    select slug, name, price_cents, unit into v_item
      from public.sf_menu
      where slug = (v_line->>'slug') and active and price_cents > 0 limit 1;
    if found then
      v_total := v_total + (v_item.price_cents * v_qty);
      v_clean := v_clean || jsonb_build_object(
        'slug', v_item.slug, 'name', v_item.name, 'unit', v_item.unit,
        'qty', v_qty, 'price_cents', v_item.price_cents,
        'line_cents', v_item.price_cents * v_qty);
    end if;
  end loop;

  if jsonb_array_length(v_clean) = 0 then raise exception 'empty_order'; end if;

  insert into public.sf_orders
    (name, phone, email, pickup_date, pickup_time, items, total_cents, notes, ip, ua)
  values (
    v_name, nullif(v_phone,''), nullif(v_email,''),
    nullif(v_date,''),
    nullif(left(btrim(coalesce(p->>'pickup_time','')), 40),''),
    v_clean, v_total,
    nullif(left(btrim(coalesce(p->>'notes','')), 4000),''),
    v_ip, v_ua)
  returning id into v_id;
  return v_id;
end $$;

-- lightweight analytics write (anon)
create or replace function public.sf_log_event(p jsonb)
returns void language plpgsql security definer
set search_path to 'public','extensions','pg_temp' as $$
declare v_ip text; v_ua text;
begin
  if coalesce(p->>'type','') not in
     ('page_view','menu_open','order_start','order_submit','call_click',
      'directions_click','hours_check') then
    return;
  end if;
  begin
    v_ip := coalesce(current_setting('request.headers', true)::json->>'cf-connecting-ip',
                     current_setting('request.headers', true)::json->>'x-real-ip');
    v_ua := left(current_setting('request.headers', true)::json->>'user-agent', 300);
  exception when others then v_ip := null; v_ua := null;
  end;
  -- cheap flood guard
  if (select count(*) from public.sf_events
      where created_at > now() - interval '1 minute') >= 400 then return; end if;
  insert into public.sf_events (type, path, ref, sid, meta, ip, ua)
  values (p->>'type', left(coalesce(p->>'path',''),200), left(coalesce(p->>'ref',''),200),
          left(coalesce(p->>'sid',''),40), coalesce(p->'meta','{}'::jsonb), v_ip, v_ua);
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- 10. ADMIN WRITE PATH — every one of these checks the passphrase first
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.sf_save_content(p_pass text, p_section text, p_data jsonb)
returns boolean language plpgsql security definer
set search_path to 'public','extensions','pg_temp' as $$
begin
  if not public.sf_check_admin(p_pass) then raise exception 'not_authorized'; end if;
  insert into public.sf_content (section, data, updated_at)
  values (p_section, p_data, now())
  on conflict (section) do update set data = excluded.data, updated_at = now();
  return true;
end $$;

create or replace function public.sf_save_category(p_pass text, p_key text, p_data jsonb)
returns text language plpgsql security definer
set search_path to 'public','extensions','pg_temp' as $$
declare v_key text;
begin
  if not public.sf_check_admin(p_pass) then raise exception 'not_authorized'; end if;
  v_key := lower(regexp_replace(btrim(coalesce(nullif(p_key,''), p_data->>'key','')),
                                '[^a-z0-9]+', '-', 'gi'));
  if v_key = '' then raise exception 'key_required'; end if;
  insert into public.sf_categories (key, label, blurb, sort, active, updated_at)
  values (
    v_key,
    left(btrim(coalesce(p_data->>'label', v_key)), 80),
    nullif(left(btrim(coalesce(p_data->>'blurb','')), 300), ''),
    coalesce((p_data->>'sort')::int, 100),
    coalesce((p_data->>'active')::boolean, true),
    now())
  on conflict (key) do update set
    label = excluded.label, blurb = excluded.blurb, sort = excluded.sort,
    active = excluded.active, updated_at = now();
  return v_key;
end $$;

create or replace function public.sf_delete_category(p_pass text, p_key text)
returns boolean language plpgsql security definer
set search_path to 'public','extensions','pg_temp' as $$
begin
  if not public.sf_check_admin(p_pass) then raise exception 'not_authorized'; end if;
  if exists (select 1 from public.sf_menu where category = p_key) then
    raise exception 'category_in_use';
  end if;
  delete from public.sf_categories where key = p_key;
  return true;
end $$;

create or replace function public.sf_save_item(p_pass text, p_id bigint, p_data jsonb)
returns bigint language plpgsql security definer
set search_path to 'public','extensions','pg_temp' as $$
declare v_id bigint; v_slug text;
begin
  if not public.sf_check_admin(p_pass) then raise exception 'not_authorized'; end if;
  v_slug := lower(regexp_replace(btrim(coalesce(p_data->>'slug', p_data->>'name','')),
                                 '[^a-z0-9]+', '-', 'gi'));
  v_slug := btrim(v_slug, '-');
  if v_slug = '' then raise exception 'slug_required'; end if;

  if p_id is null then
    insert into public.sf_menu
      (slug, name, category, blurb, detail, price_cents, unit, image, glyph,
       badge, dietary, sort, featured, active, updated_at)
    values (
      v_slug,
      left(btrim(coalesce(p_data->>'name','')), 120),
      coalesce(nullif(p_data->>'category',''), 'breakfast'),
      nullif(left(btrim(coalesce(p_data->>'blurb','')), 300), ''),
      nullif(left(btrim(coalesce(p_data->>'detail','')), 2000), ''),
      greatest(0, coalesce((p_data->>'price_cents')::int, 0)),
      nullif(left(btrim(coalesce(p_data->>'unit','')), 40), ''),
      nullif(p_data->>'image', ''),
      coalesce(nullif(p_data->>'glyph',''), 'plate'),
      nullif(left(btrim(coalesce(p_data->>'badge','')), 40), ''),
      coalesce(p_data->'dietary', '[]'::jsonb),
      coalesce((p_data->>'sort')::int, 100),
      coalesce((p_data->>'featured')::boolean, false),
      coalesce((p_data->>'active')::boolean, true),
      now())
    returning id into v_id;
  else
    update public.sf_menu set
      slug        = v_slug,
      name        = left(btrim(coalesce(p_data->>'name', name)), 120),
      category    = coalesce(nullif(p_data->>'category',''), category),
      blurb       = nullif(left(btrim(coalesce(p_data->>'blurb','')), 300), ''),
      detail      = nullif(left(btrim(coalesce(p_data->>'detail','')), 2000), ''),
      price_cents = greatest(0, coalesce((p_data->>'price_cents')::int, price_cents)),
      unit        = nullif(left(btrim(coalesce(p_data->>'unit','')), 40), ''),
      image       = nullif(coalesce(p_data->>'image', image), ''),
      glyph       = coalesce(nullif(p_data->>'glyph',''), glyph),
      badge       = nullif(left(btrim(coalesce(p_data->>'badge','')), 40), ''),
      dietary     = coalesce(p_data->'dietary', dietary),
      sort        = coalesce((p_data->>'sort')::int, sort),
      featured    = coalesce((p_data->>'featured')::boolean, featured),
      active      = coalesce((p_data->>'active')::boolean, active),
      updated_at  = now()
    where id = p_id
    returning id into v_id;
  end if;
  return v_id;
end $$;

create or replace function public.sf_delete_item(p_pass text, p_id bigint)
returns boolean language plpgsql security definer
set search_path to 'public','extensions','pg_temp' as $$
begin
  if not public.sf_check_admin(p_pass) then raise exception 'not_authorized'; end if;
  delete from public.sf_menu where id = p_id;
  return true;
end $$;

create or replace function public.sf_save_photo(p_pass text, p_id bigint, p_data jsonb)
returns bigint language plpgsql security definer
set search_path to 'public','extensions','pg_temp' as $$
declare v_id bigint;
begin
  if not public.sf_check_admin(p_pass) then raise exception 'not_authorized'; end if;
  if p_id is null then
    insert into public.sf_photos (slot, url, alt, sort, active, updated_at)
    values (
      coalesce(nullif(p_data->>'slot',''), 'album'),
      coalesce(p_data->>'url',''),
      left(btrim(coalesce(p_data->>'alt','')), 200),
      coalesce((p_data->>'sort')::int, 100),
      coalesce((p_data->>'active')::boolean, true),
      now())
    returning id into v_id;
  else
    update public.sf_photos set
      slot   = coalesce(nullif(p_data->>'slot',''), slot),
      url    = coalesce(nullif(p_data->>'url',''), url),
      alt    = left(btrim(coalesce(p_data->>'alt', alt)), 200),
      sort   = coalesce((p_data->>'sort')::int, sort),
      active = coalesce((p_data->>'active')::boolean, active),
      updated_at = now()
    where id = p_id
    returning id into v_id;
  end if;
  return v_id;
end $$;

create or replace function public.sf_delete_photo(p_pass text, p_id bigint)
returns boolean language plpgsql security definer
set search_path to 'public','extensions','pg_temp' as $$
begin
  if not public.sf_check_admin(p_pass) then raise exception 'not_authorized'; end if;
  delete from public.sf_photos where id = p_id;
  return true;
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- 11. ADMIN READ PATH — orders are invisible to anon, so they come back
--     only through these passphrase-gated functions.
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.sf_list_orders(p_pass text)
returns setof public.sf_orders language plpgsql security definer
set search_path to 'public','extensions','pg_temp' as $$
begin
  if not public.sf_check_admin(p_pass) then raise exception 'not_authorized'; end if;
  return query select * from public.sf_orders order by created_at desc limit 300;
end $$;

create or replace function public.sf_set_order_status(p_pass text, p_id bigint, p_status text)
returns boolean language plpgsql security definer
set search_path to 'public','extensions','pg_temp' as $$
begin
  if not public.sf_check_admin(p_pass) then raise exception 'not_authorized'; end if;
  if p_status not in ('new','confirmed','ready','done','cancelled') then
    raise exception 'bad_status';
  end if;
  update public.sf_orders set status = p_status where id = p_id;
  return true;
end $$;

create or replace function public.sf_analytics(p_pass text)
returns jsonb language plpgsql security definer
set search_path to 'public','extensions','pg_temp' as $$
declare v jsonb;
begin
  if not public.sf_check_admin(p_pass) then raise exception 'not_authorized'; end if;
  select jsonb_build_object(
    'views_7d',   (select count(*) from public.sf_events
                    where type = 'page_view' and created_at > now() - interval '7 days'),
    'views_30d',  (select count(*) from public.sf_events
                    where type = 'page_view' and created_at > now() - interval '30 days'),
    'calls_30d',  (select count(*) from public.sf_events
                    where type = 'call_click' and created_at > now() - interval '30 days'),
    'orders_7d',  (select count(*) from public.sf_orders
                    where created_at > now() - interval '7 days'),
    'orders_30d', (select count(*) from public.sf_orders
                    where created_at > now() - interval '30 days'),
    'revenue_30d',(select coalesce(sum(total_cents),0) from public.sf_orders
                    where created_at > now() - interval '30 days'
                      and status <> 'cancelled'),
    'top_items',  (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
                     select i->>'name' as name, sum((i->>'qty')::int) as qty
                       from public.sf_orders o,
                            lateral jsonb_array_elements(o.items) i
                      where o.created_at > now() - interval '30 days'
                        and o.status <> 'cancelled'
                      group by 1 order by 2 desc limit 8) t),
    'by_day',     (select coalesce(jsonb_agg(t order by t.day), '[]'::jsonb) from (
                     select to_char(created_at at time zone 'America/Chicago', 'YYYY-MM-DD') as day,
                            count(*) as n
                       from public.sf_events
                      where type = 'page_view' and created_at > now() - interval '14 days'
                      group by 1) t)
  ) into v;
  return v;
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- 12. GRANTS — strip Supabase's auto-grants, then hand back only what's needed
-- ═══════════════════════════════════════════════════════════════════════
do $$
declare f text;
begin
  foreach f in array array[
    'sf_admin_login(text)',
    'sf_submit_order(jsonb)',
    'sf_log_event(jsonb)',
    'sf_save_content(text,text,jsonb)',
    'sf_save_category(text,text,jsonb)',
    'sf_delete_category(text,text)',
    'sf_save_item(text,bigint,jsonb)',
    'sf_delete_item(text,bigint)',
    'sf_save_photo(text,bigint,jsonb)',
    'sf_delete_photo(text,bigint)',
    'sf_list_orders(text)',
    'sf_set_order_status(text,bigint,text)',
    'sf_analytics(text)'
  ]
  loop
    execute 'revoke execute on function public.' || f || ' from public, authenticated';
    execute 'grant  execute on function public.' || f || ' to anon, service_role';
  end loop;
end $$;

-- sf_check_admin is NOT granted to anon: it is called internally by every
-- SECURITY DEFINER RPC above (as the owner), so those keep working, while the
-- browser can only reach the rate-limited sf_admin_login.
revoke execute on function public.sf_check_admin(text) from anon, public, authenticated;
grant  execute on function public.sf_check_admin(text) to service_role;

-- ═══════════════════════════════════════════════════════════════════════
-- 13. SEED — the menu's sections, in the café's own order.
--
--     The ITEMS are deliberately NOT seeded here. The menu is content, not
--     schema: 190 items were imported from the café's own live Toast
--     ordering menu on 2026-07-31 and from then on they are maintained in
--     the back office, never in this file. Re-running this script therefore
--     never clobbers a price the owner has since corrected.
--
--     An item with price_cents = 0 shows on the menu but cannot be
--     pre-ordered — the honest default for anything priced at the counter.
-- ═══════════════════════════════════════════════════════════════════════
insert into public.sf_categories (key, label, sort) values
  ('appetizers',      'Appetizers',        10),
  ('breakfast',       'Breakfast',         20),
  ('lunch',           'Lunch',             30),
  ('kids',            'Kids',              40),
  ('sides',           'Sides',             50),
  ('desserts',        'Homemade Desserts', 60),
  ('togo',            'To Go',             70),
  ('dinner-platters', 'Dinner Platters',   80),
  ('fish-friday',     'Fish Friday',       90),
  ('fish-buckets',    'Fish Buckets',     100),
  ('hot-beverages',   'Hot Beverages',    110),
  ('milk',            'Milk',             120),
  ('juice',           'Juice',            130),
  ('coke-products',   'Coke Products',    140),
  ('iced-drinks',     'Iced Drinks',      150)
on conflict (key) do nothing;
