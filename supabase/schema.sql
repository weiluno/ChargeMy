
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text not null default '',
  avatar_url text,
  password_set boolean not null default false,
  role text not null default 'user' check (role in ('user', 'admin')),
  active_vehicle_id text,
  home_lat double precision,
  home_lng double precision,
  home_address text,
  work_lat double precision,
  work_lng double precision,
  work_address text,
  notification_preferences jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles add column if not exists home_address text;
alter table public.profiles add column if not exists work_address text;
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists password_set boolean not null default false;

create table if not exists public.vehicles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  id text not null,
  make text not null,
  model text not null,
  battery_kwh numeric(12,2) not null check (battery_kwh > 0),
  efficiency_wh_per_km numeric(12,2) not null check (efficiency_wh_per_km > 0),
  connector_types text[] not null default '{}',
  target_soc integer not null default 80 check (target_soc between 1 and 100),
  reserve_soc integer not null default 15 check (reserve_soc between 0 and 95),
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create table if not exists public.stations (
  id text primary key,
  name text not null,
  address text not null default '',
  latitude double precision not null check (latitude between 0.8 and 8.5),
  longitude double precision not null check (longitude between 98.0 and 120.0),
  state text not null default 'Malaysia',
  local_authority text not null default 'Unknown',
  indoor_outdoor text not null default 'Unknown',
  brand text not null default 'Unknown',
  is_published boolean not null default true,
  source_name text not null default 'ChargeMY demo data',
  source_url text,
  source_record_id text,
  synthetic_pile_data boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.piles (
  id text primary key,
  station_id text not null references public.stations(id) on delete cascade,
  label text not null,
  connector_type text not null,
  power_kw numeric(12,2) not null check (power_kw >= 0),
  price_per_kwh numeric(12,2) not null check (price_per_kwh >= 0),
  operational_state text not null default 'available'
    check (operational_state in ('available', 'reserved', 'occupied', 'offline', 'maintenance')),
  reservation_session_id uuid,
  is_active boolean not null default true,
  telemetry_updated_at timestamptz not null default now(),
  maintenance_alert_acknowledged_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.favorites (
  user_id uuid not null references public.profiles(id) on delete cascade,
  station_id text not null references public.stations(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, station_id)
);

create table if not exists public.charging_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  station_id text not null references public.stations(id),
  pile_id text not null references public.piles(id),
  type text not null default 'hold' check (type in ('hold', 'charge', 'trip')),
  state text not null default 'reserved'
    check (state in ('reserved', 'occupied', 'completed', 'cancelled', 'expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  arrived_at timestamptz,
  started_at timestamptz,
  ended_at timestamptz,
  target_soc integer,
  start_soc integer,
  end_soc integer,
  energy_kwh numeric(12,2),
  charge_power_kw numeric(12,2),
  battery_kwh numeric(12,2),
  route_summary jsonb
);

alter table public.charging_sessions add column if not exists charge_power_kw numeric(12,2);
alter table public.charging_sessions add column if not exists battery_kwh numeric(12,2);

alter table public.piles
  drop constraint if exists piles_reservation_session_id_fkey;
alter table public.piles
  add constraint piles_reservation_session_id_fkey
  foreign key (reservation_session_id) references public.charging_sessions(id) on delete set null;

create table if not exists public.hazard_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  station_id text not null references public.stations(id) on delete cascade,
  pile_id text references public.piles(id) on delete set null,
  category text not null,
  note text not null,
  image_path text,
  status text not null default 'submitted',
  created_at timestamptz not null default now()
);

create table if not exists public.tickets (
  id uuid primary key default gen_random_uuid(),
  station_id text not null references public.stations(id) on delete cascade,
  pile_id text references public.piles(id) on delete set null,
  type text not null default 'hazard',
  severity text not null default 'medium' check (severity in ('low', 'medium', 'high')),
  status text not null default 'open' check (status in ('open', 'in_progress', 'resolved')),
  report_ids uuid[] not null default '{}',
  distinct_reporter_ids uuid[] not null default '{}',
  opened_at timestamptz not null default now(),
  assigned_admin_id uuid references public.profiles(id),
  resolved_at timestamptz,
  audit_trail jsonb not null default '[]'::jsonb
);

create table if not exists public.pile_status_events (
  id uuid primary key default gen_random_uuid(),
  pile_id text not null references public.piles(id) on delete cascade,
  old_state text,
  new_state text not null,
  changed_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create index if not exists piles_station_id_idx on public.piles (station_id);
create index if not exists piles_state_idx on public.piles (operational_state);
create index if not exists stations_location_idx on public.stations (latitude, longitude);
create index if not exists sessions_active_user_idx on public.charging_sessions (user_id, state, expires_at);
create index if not exists reports_station_created_idx on public.hazard_reports (station_id, created_at desc);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, display_name, password_set)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'display_name', ''),
    new.encrypted_password is not null
  )
  on conflict (id) do update set
    email = excluded.email,
    display_name = case
      when public.profiles.display_name = '' then excluded.display_name
      else public.profiles.display_name
    end,
    password_set = public.profiles.password_set or excluded.password_set,
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'admin' from public.profiles where id = auth.uid()), false);
$$;

create or replace function public.protect_profile_role()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.id <> old.id then raise exception 'Profile identity cannot change.'; end if;
  if auth.uid() is not null and new.role is distinct from old.role and not public.is_admin() then
    raise exception 'Only an administrator can change roles.';
  end if;
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists protect_profile_role on public.profiles;
create trigger protect_profile_role before update on public.profiles
  for each row execute procedure public.protect_profile_role();

create or replace function public.refresh_station_summary(p_station_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.stations set updated_at = now() where id = p_station_id;
end;
$$;

create or replace function public.create_hold(p_station_id text, p_pile_id text)
returns public.charging_sessions language plpgsql security definer set search_path = public as $$
declare v_session public.charging_sessions;
begin
  if auth.uid() is null then raise exception 'Sign in is required.'; end if;
  update public.charging_sessions set state = 'expired'
    where pile_id = p_pile_id and state = 'reserved' and expires_at <= now();
  update public.piles set operational_state = 'available', reservation_session_id = null
    where id = p_pile_id and operational_state = 'reserved'
      and not exists (select 1 from public.charging_sessions where id = public.piles.reservation_session_id and state = 'reserved' and expires_at > now());
  if not exists (select 1 from public.piles where id = p_pile_id and station_id = p_station_id and operational_state = 'available' and is_active) then
    raise exception 'This pile is no longer available.';
  end if;
  if exists (select 1 from public.charging_sessions where user_id = auth.uid() and state in ('reserved', 'occupied') and (expires_at is null or expires_at > now())) then
    raise exception 'You already have an active reservation or charging session.';
  end if;
  insert into public.charging_sessions (user_id, station_id, pile_id, expires_at)
  values (auth.uid(), p_station_id, p_pile_id, now() + interval '15 minutes') returning * into v_session;
  update public.piles set operational_state = 'reserved', reservation_session_id = v_session.id, telemetry_updated_at = now() where id = p_pile_id;
  insert into public.pile_status_events (pile_id, old_state, new_state, changed_by)
  values (p_pile_id, 'available', 'reserved', auth.uid());
  return v_session;
end;
$$;

create or replace function public.start_charge_at_station(
  p_station_id text,
  p_pile_id text,
  p_latitude double precision,
  p_longitude double precision,
  p_start_soc integer,
  p_target_soc integer)
returns public.charging_sessions language plpgsql security definer set search_path = public as $$
declare
  v_station public.stations;
  v_pile public.piles;
  v_session public.charging_sessions;
  v_distance double precision;
  v_battery numeric;
begin
  if auth.uid() is null then raise exception 'Sign in to start charging.'; end if;
  if p_start_soc < 0 or p_start_soc > 99 then raise exception 'Current battery must be between 0 and 99%%.'; end if;
  if p_target_soc <= p_start_soc or p_target_soc > 100 then raise exception 'Target battery must be higher than current and at most 100%%.'; end if;
  select * into v_station from public.stations where id = p_station_id and is_published;
  if v_station.id is null then raise exception 'Station not found.'; end if;
  v_distance := 6371 * acos(greatest(-1.0, least(1.0,
    cos(radians(p_latitude)) * cos(radians(v_station.latitude)) * cos(radians(v_station.longitude) - radians(p_longitude))
    + sin(radians(p_latitude)) * sin(radians(v_station.latitude)))));
  if v_distance > 0.35 then raise exception 'Move within 350 metres of the station before starting.'; end if;
  select * into v_pile from public.piles where id = p_pile_id and station_id = p_station_id and is_active for update;
  if v_pile.id is null or v_pile.operational_state <> 'available' then raise exception 'That pile is no longer available. Choose another pile.'; end if;
  if exists (select 1 from public.charging_sessions where user_id = auth.uid() and state = 'occupied') then
    raise exception 'You already have an active charging session.';
  end if;
  select v.battery_kwh into v_battery
  from public.vehicles v
  join public.profiles p on p.active_vehicle_id = v.id and p.id = auth.uid()
  where v.user_id = auth.uid()
  order by v.updated_at desc
  limit 1;
  insert into public.charging_sessions
    (user_id, station_id, pile_id, type, state, started_at,
     start_soc, target_soc, charge_power_kw, battery_kwh)
    values
      (auth.uid(), p_station_id, p_pile_id, 'charge', 'occupied', now(),
       p_start_soc, p_target_soc, v_pile.power_kw, coalesce(v_battery, 60))
    returning * into v_session;
  insert into public.pile_status_events (pile_id, old_state, new_state, changed_by)
    values (p_pile_id, 'available', 'occupied', auth.uid());
  update public.piles set operational_state = 'occupied', reservation_session_id = v_session.id, telemetry_updated_at = now()
    where id = p_pile_id;
  return v_session;
end;
$$;

create or replace function public.check_in(p_session_id uuid)
returns public.charging_sessions language plpgsql security definer set search_path = public as $$
declare v_session public.charging_sessions;
begin
  update public.charging_sessions set state = 'expired'
    where id = p_session_id and state = 'reserved' and expires_at <= now();
  update public.charging_sessions set state = 'occupied', type = 'charge', arrived_at = now(), started_at = now()
    where id = p_session_id and user_id = auth.uid() and state = 'reserved' and expires_at > now()
    returning * into v_session;
  if not found then raise exception 'A valid active reservation is required.'; end if;
  update public.piles set operational_state = 'occupied', telemetry_updated_at = now() where id = v_session.pile_id;
  insert into public.pile_status_events (pile_id, old_state, new_state, changed_by)
  values (v_session.pile_id, 'reserved', 'occupied', auth.uid());
  return v_session;
end;
$$;

create or replace function public.check_in_at_station(
  p_session_id uuid, p_latitude double precision, p_longitude double precision)
returns public.charging_sessions language plpgsql security definer set search_path = public as $$
declare v_session public.charging_sessions; v_station public.stations; v_distance double precision;
begin
  select * into v_session from public.charging_sessions
    where id = p_session_id and user_id = auth.uid() and state = 'reserved' and expires_at > now() for update;
  if v_session.id is null then raise exception 'This reservation has expired or is not yours.'; end if;
  select * into v_station from public.stations where id = v_session.station_id;
  v_distance := 6371 * acos(least(1.0,
    cos(radians(p_latitude)) * cos(radians(v_station.latitude)) * cos(radians(v_station.longitude) - radians(p_longitude))
    + sin(radians(p_latitude)) * sin(radians(v_station.latitude))));
  if v_distance > 0.35 then raise exception 'Move within 350 metres of the station before checking in.'; end if;
  return public.check_in(p_session_id);
end;
$$;

create or replace function public.switch_reserved_pile(
  p_session_id uuid, p_new_pile_id text)
returns public.charging_sessions language plpgsql security definer set search_path = public as $$
declare v_session public.charging_sessions; v_new public.piles;
begin
  select * into v_session from public.charging_sessions
    where id = p_session_id and user_id = auth.uid() and state = 'reserved' and expires_at > now() for update;
  if v_session.id is null then raise exception 'This reservation has expired or is already charging.'; end if;
  if p_new_pile_id = v_session.pile_id then return v_session; end if;
  select * into v_new from public.piles where id = p_new_pile_id and is_active for update;
  if v_new.id is null or v_new.operational_state <> 'available' then raise exception 'That pile is no longer available.'; end if;
  update public.piles set operational_state = 'available', reservation_session_id = null, telemetry_updated_at = now()
    where id = v_session.pile_id and reservation_session_id = v_session.id;
  update public.piles set operational_state = 'reserved', reservation_session_id = v_session.id, telemetry_updated_at = now()
    where id = p_new_pile_id;
  update public.charging_sessions set pile_id = p_new_pile_id where id = v_session.id returning * into v_session;
  return v_session;
end;
$$;

create or replace function public.cancel_hold(p_session_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_pile_id text;
begin
  update public.charging_sessions set state = 'cancelled', ended_at = now()
    where id = p_session_id and user_id = auth.uid() and state = 'reserved'
    returning pile_id into v_pile_id;
  if not found then raise exception 'No active hold was found.'; end if;
  update public.piles set operational_state = 'available', reservation_session_id = null, telemetry_updated_at = now()
    where id = v_pile_id and reservation_session_id = p_session_id;
  insert into public.pile_status_events (pile_id, old_state, new_state, changed_by)
  values (v_pile_id, 'reserved', 'available', auth.uid());
end;
$$;

create or replace function public.complete_charge(p_session_id uuid, p_energy_kwh numeric default null, p_end_soc integer default null)
returns public.charging_sessions language plpgsql security definer set search_path = public as $$
declare v_session public.charging_sessions;
begin
  update public.charging_sessions set state = 'completed', ended_at = now(), energy_kwh = p_energy_kwh, end_soc = p_end_soc
    where id = p_session_id and user_id = auth.uid() and state = 'occupied' returning * into v_session;
  if not found then raise exception 'No active charge session was found.'; end if;
  update public.piles set operational_state = 'available', reservation_session_id = null, telemetry_updated_at = now() where id = v_session.pile_id;
  insert into public.pile_status_events (pile_id, old_state, new_state, changed_by)
  values (v_session.pile_id, 'occupied', 'available', auth.uid());
  return v_session;
end;
$$;

create or replace function public.admin_update_pile_status(p_pile_id text, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare v_old text;
begin
  if not public.is_admin() then raise exception 'Administrator access is required.'; end if;
  if p_status not in ('available', 'reserved', 'occupied', 'offline', 'maintenance') then raise exception 'Invalid pile status.'; end if;
  select operational_state into v_old from public.piles where id = p_pile_id for update;
  if not found then raise exception 'Pile not found.'; end if;
  update public.piles set operational_state = p_status, reservation_session_id = case when p_status = 'available' then null else reservation_session_id end, telemetry_updated_at = now() where id = p_pile_id;
  insert into public.pile_status_events (pile_id, old_state, new_state, changed_by) values (p_pile_id, v_old, p_status, auth.uid());
end;
$$;

create or replace function public.admin_update_pile(
  p_pile_id text, p_label text, p_connector_type text,
  p_power_kw numeric, p_price_per_kwh numeric
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Administrator access is required.'; end if;
  if length(trim(p_label)) = 0
     or p_connector_type not in ('CCS2', 'Type 2', 'CHAdeMO')
     or p_power_kw < 0
     or p_price_per_kwh < 0 then
    raise exception 'Invalid pile details.';
  end if;
  update public.piles
  set label = trim(p_label), connector_type = p_connector_type,
      power_kw = p_power_kw, price_per_kwh = p_price_per_kwh,
      telemetry_updated_at = now()
  where id = p_pile_id and is_active;
  if not found then raise exception 'Charging pile not found.'; end if;
end;
$$;

create or replace function public.admin_delete_pile(p_pile_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Administrator access is required.'; end if;
  update public.piles
  set is_active = false, reservation_session_id = null, telemetry_updated_at = now()
  where id = p_pile_id and is_active;
  if not found then raise exception 'Charging pile was already removed.'; end if;
end;
$$;

create or replace function public.admin_create_station(
  p_station_id text, p_name text, p_address text, p_latitude double precision, p_longitude double precision,
  p_brand text, p_indoor_outdoor text, p_local_authority text, p_connector_type text, p_power_kw numeric, p_price_per_kwh numeric
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Administrator access is required.'; end if;
  if p_latitude not between 0.8 and 8.5 or p_longitude not between 98 and 120 or p_power_kw < 0 or p_price_per_kwh < 0 then raise exception 'Invalid Malaysian station details.'; end if;
  insert into public.stations (id, name, address, latitude, longitude, brand, indoor_outdoor, local_authority, source_name)
  values (p_station_id, trim(p_name), trim(p_address), p_latitude, p_longitude, trim(p_brand), p_indoor_outdoor, trim(p_local_authority), 'ChargeMY admin entry');
  insert into public.piles (id, station_id, label, connector_type, power_kw, price_per_kwh)
  values (p_station_id || '-pile-001', p_station_id, 'Bay 01', p_connector_type, p_power_kw, p_price_per_kwh);
end;
$$;

create or replace function public.admin_create_pile(p_station_id text, p_pile_id text, p_label text, p_connector_type text, p_power_kw numeric, p_price_per_kwh numeric, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Administrator access is required.'; end if;
  insert into public.piles (id, station_id, label, connector_type, power_kw, price_per_kwh, operational_state)
  values (p_pile_id, p_station_id, trim(p_label), p_connector_type, p_power_kw, p_price_per_kwh, p_status);
end;
$$;

create or replace function public.create_hazard_report(p_station_id text, p_pile_id text, p_category text, p_note text, p_image_path text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in is required.'; end if;
  if length(trim(p_note)) = 0 then raise exception 'Please describe the hazard.'; end if;
  insert into public.hazard_reports (user_id, station_id, pile_id, category, note, image_path)
  values (auth.uid(), p_station_id, nullif(p_pile_id, ''), p_category, trim(p_note), p_image_path) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.open_ticket_for_repeated_hazard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_report_ids uuid[];
  v_reporters uuid[];
  v_report_count integer;
  v_ticket uuid;
begin
  select count(*), array_agg(id order by created_at), array_agg(distinct user_id)
  into v_report_count, v_report_ids, v_reporters
  from public.hazard_reports
  where station_id = new.station_id
    and pile_id is not distinct from new.pile_id
    and status <> 'cancelled'
    and created_at >= now() - interval '24 hours';

  if v_report_count >= 3 then
    select id into v_ticket from public.tickets
    where station_id = new.station_id
      and pile_id is not distinct from new.pile_id
      and status in ('open', 'in_progress')
    limit 1;
    if v_ticket is null then
      insert into public.tickets (station_id, pile_id, severity, report_ids, distinct_reporter_ids)
      values (new.station_id, new.pile_id, 'high', v_report_ids, v_reporters);
    else
      update public.tickets
      set report_ids = v_report_ids, distinct_reporter_ids = v_reporters
      where id = v_ticket;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists on_hazard_report_created on public.hazard_reports;
create trigger on_hazard_report_created after insert on public.hazard_reports for each row execute procedure public.open_ticket_for_repeated_hazard();

alter table public.profiles enable row level security;
alter table public.vehicles enable row level security;
alter table public.stations enable row level security;
alter table public.piles enable row level security;
alter table public.favorites enable row level security;
alter table public.charging_sessions enable row level security;
alter table public.hazard_reports enable row level security;
alter table public.tickets enable row level security;
alter table public.pile_status_events enable row level security;

drop policy if exists "profiles own read" on public.profiles;
drop policy if exists "profiles own update" on public.profiles;
drop policy if exists "vehicles own" on public.vehicles;
drop policy if exists "published stations public read" on public.stations;
drop policy if exists "stations admin write" on public.stations;
drop policy if exists "published piles public read" on public.piles;
drop policy if exists "piles admin write" on public.piles;
drop policy if exists "favorites own" on public.favorites;
drop policy if exists "sessions own or admin read" on public.charging_sessions;
drop policy if exists "reports own or admin read" on public.hazard_reports;
drop policy if exists "tickets admin read" on public.tickets;
drop policy if exists "ticket admin write" on public.tickets;
drop policy if exists "status events admin read" on public.pile_status_events;
create policy "profiles own read" on public.profiles for select using (auth.uid() = id or public.is_admin());
create policy "profiles own update" on public.profiles for update using (auth.uid() = id or public.is_admin()) with check (auth.uid() = id or public.is_admin());
create policy "vehicles own" on public.vehicles for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "published stations public read" on public.stations for select using (is_published or public.is_admin());
create policy "stations admin write" on public.stations for all using (public.is_admin()) with check (public.is_admin());
create policy "published piles public read" on public.piles for select using (public.is_admin() or exists (select 1 from public.stations s where s.id = station_id and s.is_published));
create policy "piles admin write" on public.piles for all using (public.is_admin()) with check (public.is_admin());
create policy "favorites own" on public.favorites for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "sessions own or admin read" on public.charging_sessions for select using (auth.uid() = user_id or public.is_admin());
create policy "reports own or admin read" on public.hazard_reports for select using (auth.uid() = user_id or public.is_admin());
create policy "tickets admin read" on public.tickets for select using (public.is_admin());
create policy "ticket admin write" on public.tickets for all using (public.is_admin()) with check (public.is_admin());
create policy "status events admin read" on public.pile_status_events for select using (public.is_admin());

insert into storage.buckets (id, name, public) values ('reports', 'reports', false) on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true)
  on conflict (id) do update set public = true;
drop policy if exists "avatar upload by owner" on storage.objects;
create policy "avatar upload by owner" on storage.objects
  for all to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "report image upload by owner" on storage.objects;
drop policy if exists "report image read by owner or admin" on storage.objects;
create policy "report image upload by owner" on storage.objects for insert to authenticated
  with check (bucket_id = 'reports' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "report image read by owner or admin" on storage.objects for select to authenticated
  using (bucket_id = 'reports' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'stations') then
    alter publication supabase_realtime add table public.stations;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'piles') then
    alter publication supabase_realtime add table public.piles;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'favorites') then
    alter publication supabase_realtime add table public.favorites;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'hazard_reports') then
    alter publication supabase_realtime add table public.hazard_reports;
  end if;
end;
$$;

create or replace view public.station_daily_analytics with (security_invoker = true) as
select
  s.id as station_id,
  date_trunc('day', coalesce(cs.ended_at, cs.created_at))::date as day,
  avg(extract(epoch from (cs.ended_at - cs.started_at)) / 60.0) filter (where cs.state = 'completed') as average_stay_minutes,
  count(*) filter (where cs.state = 'completed') as completed_sessions
from public.stations s left join public.charging_sessions cs on cs.station_id = s.id
group by s.id, date_trunc('day', coalesce(cs.ended_at, cs.created_at))::date;


create table if not exists public.notification_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  push_token text not null unique,
  provider text not null check (provider in ('fcm', 'onesignal')),
  platform text not null default 'unknown',
  updated_at timestamptz not null default now()
);

create table if not exists public.reservation_heartbeats (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.charging_sessions(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  recorded_at timestamptz not null default now()
);

create table if not exists public.import_batches (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references public.profiles(id),
  source_file_name text not null,
  source_format text not null check (source_format in ('csv', 'json')),
  total_rows integer not null default 0,
  imported_rows integer not null default 0,
  errors jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_created_idx
  on public.notification_events (user_id, created_at desc);
create index if not exists heartbeats_session_created_idx
  on public.reservation_heartbeats (session_id, recorded_at desc);

alter table public.notification_events enable row level security;
alter table public.user_devices enable row level security;
alter table public.reservation_heartbeats enable row level security;
alter table public.import_batches enable row level security;

drop policy if exists "notifications own read" on public.notification_events;
create policy "notifications own read" on public.notification_events for select
  using (auth.uid() = user_id);
drop policy if exists "notifications own update" on public.notification_events;
create policy "notifications own update" on public.notification_events for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "devices own manage" on public.user_devices;
create policy "devices own manage" on public.user_devices for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "heartbeats own read" on public.reservation_heartbeats;
create policy "heartbeats own read" on public.reservation_heartbeats for select
  using (exists (select 1 from public.charging_sessions s where s.id = session_id and s.user_id = auth.uid()));
drop policy if exists "imports admin read" on public.import_batches;
create policy "imports admin read" on public.import_batches for select using (public.is_admin());

create or replace function public.notify_favourite_station_available()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.operational_state = 'available'
     and (tg_op = 'INSERT' or old.operational_state is distinct from 'available') then
    insert into public.notification_events (user_id, type, title, body, data)
    select f.user_id, 'favourite_available', 'Favourite station available',
      coalesce(s.name, 'Your favourite station') || ' has an available charging pile.',
      jsonb_build_object('station_id', new.station_id, 'pile_id', new.id)
    from public.favorites f join public.stations s on s.id = f.station_id
    where f.station_id = new.station_id;
  end if;
  return new;
end;
$$;
drop trigger if exists pile_available_notification on public.piles;
create trigger pile_available_notification after insert or update of operational_state on public.piles
  for each row execute procedure public.notify_favourite_station_available();

create or replace function public.notify_nearby_new_station()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.is_published and (tg_op = 'INSERT' or old.is_published is distinct from true) then
    insert into public.notification_events (user_id, type, title, body, data)
    select p.id, 'nearby_new_station', 'New charging station nearby',
      new.name || ' is within 10 km of your saved home or work location.',
      jsonb_build_object('station_id', new.id)
    from public.profiles p
    where (p.home_lat is not null and p.home_lng is not null and
      6371 * acos(least(1.0, cos(radians(p.home_lat)) * cos(radians(new.latitude)) * cos(radians(new.longitude) - radians(p.home_lng)) + sin(radians(p.home_lat)) * sin(radians(new.latitude)))) <= 10)
      or (p.work_lat is not null and p.work_lng is not null and
      6371 * acos(least(1.0, cos(radians(p.work_lat)) * cos(radians(new.latitude)) * cos(radians(new.longitude) - radians(p.work_lng)) + sin(radians(p.work_lat)) * sin(radians(new.latitude)))) <= 10);
  end if;
  return new;
end;
$$;
drop trigger if exists nearby_station_notification on public.stations;
create trigger nearby_station_notification after insert or update of is_published on public.stations
  for each row execute procedure public.notify_nearby_new_station();

create or replace function public.record_reservation_heartbeat(
  p_session_id uuid, p_latitude double precision, p_longitude double precision)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.charging_sessions where id = p_session_id and user_id = auth.uid() and state = 'reserved' and expires_at > now()) then
    raise exception 'No active reservation exists.';
  end if;
  insert into public.reservation_heartbeats (session_id, latitude, longitude)
  values (p_session_id, p_latitude, p_longitude);
end;
$$;

create or replace function public.monitor_abandoned_holds()
returns integer language plpgsql security definer set search_path = public as $$
declare v_count integer := 0;
begin
  with candidates as (
    select s.id, s.user_id, st.name,
      (select h.recorded_at from public.reservation_heartbeats h where h.session_id = s.id order by h.recorded_at desc limit 1) as last_heartbeat
    from public.charging_sessions s join public.stations st on st.id = s.station_id
    where s.state = 'reserved' and s.expires_at > now()
      and s.created_at < now() - interval '5 minutes'
      and not coalesce((s.route_summary ->> 'abandonment_warned')::boolean, false)
  ), inserted as (
    insert into public.notification_events (user_id, type, title, body, data)
    select user_id, 'reservation_abandonment', 'Are you still heading to your charger?',
      'Your hold at ' || name || ' will expire normally if you do not continue your journey.', jsonb_build_object('session_id', id)
    from candidates
    where last_heartbeat is null or last_heartbeat < now() - interval '4 minutes'
    returning data ->> 'session_id' as session_id
  )
  update public.charging_sessions s set route_summary = coalesce(route_summary, '{}'::jsonb) || jsonb_build_object('abandonment_warned', true)
  from inserted i where s.id::text = i.session_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.record_charge_progress(
  p_session_id uuid, p_soc integer, p_energy_kwh numeric default null)
returns public.charging_sessions language plpgsql security definer set search_path = public as $$
declare v_session public.charging_sessions; v_target integer;
begin
  if p_soc < 0 or p_soc > 100 then raise exception 'State of charge must be 0-100.'; end if;
  update public.charging_sessions set end_soc = p_soc, energy_kwh = coalesce(p_energy_kwh, energy_kwh)
  where id = p_session_id and user_id = auth.uid() and state = 'occupied' returning * into v_session;
  if v_session.id is null then raise exception 'No active charging session exists.'; end if;
  v_target := v_session.target_soc;
  if v_target is null then
    select v.target_soc into v_target from public.vehicles v join public.profiles p on p.active_vehicle_id = v.id
      where p.id = auth.uid() and v.user_id = auth.uid();
  end if;
  if v_target is not null and p_soc >= v_target and not exists (
    select 1 from public.notification_events where user_id = auth.uid() and type = 'idle_fee_warning' and data ->> 'session_id' = p_session_id::text
  ) then
    insert into public.notification_events (user_id, type, title, body, data)
    values (auth.uid(), 'idle_fee_warning', 'Target charge reached', 'Vehicle reached ' || p_soc || '%. Unplug within 10 minutes to avoid idle fees.', jsonb_build_object('session_id', p_session_id));
  end if;
  return v_session;
end;
$$;

create or replace function public.admin_bulk_import(
  p_file_name text, p_format text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_row jsonb; v_index integer := 0; v_ok integer := 0; v_errors jsonb := '[]'::jsonb;
  v_station_id text; v_pile_id text; v_lat double precision; v_lng double precision; v_kw numeric; v_price numeric;
begin
  if not public.is_admin() then raise exception 'Administrator access required.'; end if;
  if p_format not in ('csv', 'json') then raise exception 'Only CSV and JSON imports are supported.'; end if;
  if jsonb_array_length(p_rows) > 500 then raise exception 'Import is limited to 500 rows.'; end if;
  for v_row in select * from jsonb_array_elements(p_rows) loop
    v_index := v_index + 1;
    begin
      v_station_id := coalesce(nullif(v_row ->> 'station_id', ''), 'admin-import-' || extract(epoch from clock_timestamp())::bigint || '-' || v_index);
      v_pile_id := coalesce(nullif(v_row ->> 'pile_id', ''), v_station_id || '-pile-1');
      v_lat := (v_row ->> 'latitude')::double precision; v_lng := (v_row ->> 'longitude')::double precision;
      v_kw := coalesce((v_row ->> 'power_kw')::numeric, 0); v_price := coalesce((v_row ->> 'price_per_kwh')::numeric, 0);
      if coalesce(trim(v_row ->> 'name'), '') = '' or v_lat not between 0.8 and 8.5 or v_lng not between 98 and 120 or v_kw < 0 or v_price < 0 then
        raise exception 'Missing name, invalid Malaysian location, power or price.';
      end if;
      insert into public.stations (id, name, address, latitude, longitude, brand, indoor_outdoor, local_authority, source_name)
      values (v_station_id, trim(v_row ->> 'name'), coalesce(v_row ->> 'address', ''), v_lat, v_lng,
        coalesce(nullif(v_row ->> 'brand', ''), 'Imported'), coalesce(nullif(v_row ->> 'indoor_outdoor', ''), 'Unknown'),
        coalesce(nullif(v_row ->> 'local_authority', ''), 'Unknown'), 'Admin ' || upper(p_format) || ' import')
      on conflict (id) do update set name = excluded.name, address = excluded.address, latitude = excluded.latitude, longitude = excluded.longitude, brand = excluded.brand, updated_at = now();
      insert into public.piles (id, station_id, label, connector_type, power_kw, price_per_kwh, operational_state)
      values (v_pile_id, v_station_id, coalesce(nullif(v_row ->> 'pile_label', ''), 'Bay 01'),
        coalesce(nullif(v_row ->> 'connector_type', ''), 'CCS2'), v_kw, v_price,
        coalesce(nullif(v_row ->> 'operational_state', ''), 'available'))
      on conflict (id) do update set power_kw = excluded.power_kw, price_per_kwh = excluded.price_per_kwh, operational_state = excluded.operational_state, telemetry_updated_at = now();
      v_ok := v_ok + 1;
    exception when others then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('row', v_index, 'error', sqlerrm));
    end;
  end loop;
  insert into public.import_batches (created_by, source_file_name, source_format, total_rows, imported_rows, errors)
  values (auth.uid(), p_file_name, p_format, v_index, v_ok, v_errors);
  return jsonb_build_object('total_rows', v_index, 'imported_rows', v_ok, 'errors', v_errors);
end;
$$;


alter table public.hazard_reports
  add column if not exists image_paths text[] not null default '{}';
alter table public.hazard_reports
  alter column status set default 'ongoing';
update public.hazard_reports set status = 'ongoing'
where status = 'submitted' or status is null;
update public.hazard_reports set image_paths = array[image_path]
where image_path is not null and cardinality(image_paths) = 0;

drop function if exists public.create_hazard_report(text, text, text, text, text);
drop function if exists public.create_hazard_report(text, text, text, text, text[]);
create or replace function public.create_hazard_report(
  p_station_id text, p_pile_id text, p_category text, p_note text,
  p_image_paths text[] default '{}'
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_paths text[] := coalesce(p_image_paths, '{}');
begin
  if auth.uid() is null then raise exception 'Sign in is required.'; end if;
  if length(trim(p_note)) = 0 then raise exception 'Please describe the hazard.'; end if;
  if cardinality(v_paths) > 5 then raise exception 'You can attach up to five photos to one report.'; end if;
  if exists (select 1 from unnest(v_paths) as path where trim(path) = '') then
    raise exception 'One of the selected photos is invalid.';
  end if;
  insert into public.hazard_reports
    (user_id, station_id, pile_id, category, note, image_path, image_paths, status)
  values
    (auth.uid(), p_station_id, nullif(p_pile_id, ''), p_category, trim(p_note),
     nullif(v_paths[1], ''), v_paths, 'ongoing')
  returning id into v_id;
  return v_id;
end;
$$;
grant execute on function public.create_hazard_report(text, text, text, text, text[]) to authenticated;

create table if not exists public.charging_payments (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null unique references public.charging_sessions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  station_id text not null references public.stations(id),
  energy_kwh numeric(12,2) not null default 0 check (energy_kwh >= 0),
  amount_myr numeric(12,2) not null check (amount_myr >= 0),
  currency text not null default 'myr',
  provider text not null default 'stripe_test',
  status text not null default 'paid' check (status in ('paid', 'refunded', 'failed')),
  receipt_email text,
  paid_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists charging_payments_user_paid_idx on public.charging_payments (user_id, paid_at desc);
create index if not exists charging_payments_station_paid_idx on public.charging_payments (station_id, paid_at desc);
alter table public.charging_payments enable row level security;
drop policy if exists "payments own read" on public.charging_payments;
drop policy if exists "payments admin read" on public.charging_payments;
create policy "payments own read" on public.charging_payments
  for select using (auth.uid() = user_id or public.is_admin());
create policy "payments admin read" on public.charging_payments
  for select using (public.is_admin());
drop policy if exists "reports admin update" on public.hazard_reports;
create policy "reports admin update" on public.hazard_reports
  for update using (public.is_admin()) with check (public.is_admin());

create or replace function public.record_charging_payment(
  p_session_id uuid, p_amount_myr numeric, p_energy_kwh numeric,
  p_receipt_email text default null
) returns public.charging_payments language plpgsql security definer set search_path = public as $$
declare
  v_session public.charging_sessions;
  v_payment public.charging_payments;
begin
  if auth.uid() is null then raise exception 'Sign in is required.'; end if;
  p_amount_myr := round(p_amount_myr, 2);
  p_energy_kwh := round(p_energy_kwh, 2);
  if p_amount_myr < 0 or p_energy_kwh < 0 then raise exception 'Payment values cannot be negative.'; end if;
  if abs(p_amount_myr - greatest(2.00, p_energy_kwh * 1.20)) > 0.01 then
    raise exception 'Payment amount does not match the charging energy.';
  end if;
  select * into v_session from public.charging_sessions
  where id = p_session_id and user_id = auth.uid() and state = 'completed';
  if v_session.id is null then raise exception 'Completed charging session not found.'; end if;
  insert into public.charging_payments
    (session_id, user_id, station_id, energy_kwh, amount_myr, receipt_email)
  values
    (v_session.id, auth.uid(), v_session.station_id, p_energy_kwh, p_amount_myr,
     nullif(trim(p_receipt_email), ''))
  on conflict (session_id) do update set
    energy_kwh = excluded.energy_kwh, amount_myr = excluded.amount_myr,
    receipt_email = excluded.receipt_email, status = 'paid', paid_at = now()
  returning * into v_payment;
  return v_payment;
end;
$$;

create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'Sign in is required.'; end if;
  if exists (select 1 from public.charging_sessions where user_id = auth.uid() and state = 'occupied') then
    raise exception 'Complete or stop your active charging session before deleting the account.';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

create or replace function public.admin_set_user_role(p_user_id uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Administrator access is required.'; end if;
  if p_role not in ('user', 'admin') then raise exception 'Invalid role.'; end if;
  if p_user_id = auth.uid() and p_role <> 'admin' then
    raise exception 'You cannot remove your own administrator access.';
  end if;
  update public.profiles set role = p_role, updated_at = now() where id = p_user_id;
  if not found then raise exception 'User profile not found.'; end if;
end;
$$;

create or replace function public.admin_update_station(
  p_station_id text, p_name text, p_address text, p_latitude double precision,
  p_longitude double precision, p_brand text, p_indoor_outdoor text,
  p_local_authority text
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Administrator access is required.'; end if;
  if p_latitude not between 0.8 and 8.5 or p_longitude not between 98 and 120 then
    raise exception 'Invalid Malaysian station coordinates.';
  end if;
  if length(trim(p_name)) = 0 or length(trim(p_address)) = 0 then
    raise exception 'Station name and address are required.';
  end if;
  update public.stations set
    name = trim(p_name), address = trim(p_address), latitude = p_latitude,
    longitude = p_longitude, brand = trim(p_brand), indoor_outdoor = trim(p_indoor_outdoor),
    local_authority = trim(p_local_authority), updated_at = now()
  where id = p_station_id;
  if not found then raise exception 'Station not found.'; end if;
end;
$$;

create or replace function public.admin_delete_station(p_station_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Administrator access is required.'; end if;
  update public.stations set is_published = false, updated_at = now() where id = p_station_id;
  if not found then raise exception 'Station not found.'; end if;
end;
$$;

create or replace view public.station_revenue_analytics
with (security_invoker = true) as
select
  cp.station_id, s.name as station_name, date_trunc('day', cp.paid_at)::date as day,
  count(*)::integer as paid_sessions,
  round(coalesce(sum(cp.energy_kwh), 0), 2) as energy_kwh,
  round(coalesce(sum(cp.amount_myr), 0), 2) as revenue_myr
from public.charging_payments cp
join public.stations s on s.id = cp.station_id
where cp.status = 'paid'
group by cp.station_id, s.name, date_trunc('day', cp.paid_at)::date;
grant select on public.station_revenue_analytics to authenticated;
grant execute on function public.record_charging_payment(uuid, numeric, numeric, text) to authenticated;
grant execute on function public.delete_my_account() to authenticated;
grant execute on function public.admin_set_user_role(uuid, text) to authenticated;
grant execute on function public.admin_update_station(text, text, text, double precision, double precision, text, text, text) to authenticated;
grant execute on function public.admin_delete_station(text) to authenticated;

create table if not exists public.admin_activity_log (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  action text not null,
  entity_type text not null,
  entity_id text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists admin_activity_log_created_idx
  on public.admin_activity_log (created_at desc);

create table if not exists public.station_ratings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  station_id text not null references public.stations(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text not null default '' check (char_length(comment) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, station_id)
);
create index if not exists station_ratings_station_idx
  on public.station_ratings (station_id, updated_at desc);

alter table public.admin_activity_log enable row level security;
alter table public.station_ratings enable row level security;
drop policy if exists "activity log admin read" on public.admin_activity_log;
drop policy if exists "station ratings public read" on public.station_ratings;
drop policy if exists "station ratings owner write" on public.station_ratings;
create policy "activity log admin read" on public.admin_activity_log
  for select using (public.is_admin());
create policy "station ratings public read" on public.station_ratings
  for select using (true);
create policy "station ratings owner write" on public.station_ratings
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function public.record_admin_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_action text;
  v_entity_id text;
  v_details jsonb;
begin
  if not public.is_admin() then return new; end if;
  if TG_TABLE_NAME = 'piles' then
    v_entity_id := coalesce(new.id, old.id);
    if old.is_active and not new.is_active then v_action := 'Removed charging pile';
    elsif old.operational_state is distinct from new.operational_state then v_action := 'Changed pile status';
    else v_action := 'Updated charging pile'; end if;
    v_details := jsonb_build_object(
      'station_id', new.station_id, 'pile_label', new.label,
      'old_status', old.operational_state, 'new_status', new.operational_state);
  elsif TG_TABLE_NAME = 'stations' then
    v_entity_id := coalesce(new.id, old.id);
    v_action := case when old.is_published and not new.is_published
      then 'Removed station' else 'Updated station' end;
    v_details := jsonb_build_object('station_name', new.name);
  elsif TG_TABLE_NAME = 'hazard_reports' then
    v_entity_id := coalesce(new.id, old.id)::text;
    v_action := 'Updated hazard report';
    v_details := jsonb_build_object(
      'station_id', new.station_id, 'pile_id', new.pile_id,
      'old_status', old.status, 'new_status', new.status);
  elsif TG_TABLE_NAME = 'tickets' then
    v_entity_id := coalesce(new.id, old.id)::text;
    v_action := 'Updated maintenance ticket';
    v_details := jsonb_build_object(
      'station_id', new.station_id, 'pile_id', new.pile_id,
      'old_status', old.status, 'new_status', new.status);
  else
    return new;
  end if;
  insert into public.admin_activity_log (admin_id, action, entity_type, entity_id, details)
  values (auth.uid(), v_action, TG_TABLE_NAME, v_entity_id, v_details);
  return new;
end;
$$;

drop trigger if exists log_admin_pile_activity on public.piles;
create trigger log_admin_pile_activity after update on public.piles
  for each row execute procedure public.record_admin_activity();
drop trigger if exists log_admin_station_activity on public.stations;
create trigger log_admin_station_activity after update on public.stations
  for each row execute procedure public.record_admin_activity();
drop trigger if exists log_admin_hazard_activity on public.hazard_reports;
create trigger log_admin_hazard_activity after update on public.hazard_reports
  for each row execute procedure public.record_admin_activity();
drop trigger if exists log_admin_ticket_activity on public.tickets;
create trigger log_admin_ticket_activity after update on public.tickets
  for each row execute procedure public.record_admin_activity();

create or replace function public.submit_station_rating(
  p_station_id text, p_rating integer, p_comment text default ''
) returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in is required.'; end if;
  if p_rating not between 1 and 5 then
    raise exception 'Choose a rating from 1 to 5 stars.';
  end if;
  if not exists (
    select 1 from public.stations where id = p_station_id and is_published
  ) then
    raise exception 'Charging station not found.';
  end if;
  insert into public.station_ratings (user_id, station_id, rating, comment)
  values (auth.uid(), p_station_id, p_rating, trim(coalesce(p_comment, '')))
  on conflict (user_id, station_id) do update set
    rating = excluded.rating,
    comment = excluded.comment,
    updated_at = now();
end;
$$;

create or replace view public.station_rating_summary
with (security_invoker = true) as
select
  station_id,
  round(avg(rating)::numeric, 2) as average_rating,
  count(*)::integer as rating_count
from public.station_ratings
group by station_id;

grant select on public.station_rating_summary to authenticated;
grant execute on function public.submit_station_rating(text, integer, text) to authenticated;

create table if not exists public.vouchers (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  title text not null,
  description text not null default '',
  discount_type text not null check (discount_type in ('fixed', 'percent')),
  discount_value numeric(12,2) not null check (discount_value > 0),
  minimum_spend_myr numeric(12,2) not null default 0 check (minimum_spend_myr >= 0),
  max_redemptions integer check (max_redemptions is null or max_redemptions > 0),
  is_new_user_voucher boolean not null default false,
  is_reward_voucher boolean not null default false,
  is_active boolean not null default true,
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (discount_type <> 'percent' or discount_value <= 100)
);

alter table public.vouchers
  add column if not exists is_reward_voucher boolean not null default false;

create table if not exists public.voucher_claims (
  id uuid primary key default gen_random_uuid(),
  voucher_id uuid not null references public.vouchers(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  claimed_at timestamptz not null default now(),
  used_at timestamptz,
  unique (voucher_id, user_id)
);

create index if not exists voucher_claims_user_idx
  on public.voucher_claims (user_id, claimed_at desc);
create index if not exists voucher_claims_voucher_idx
  on public.voucher_claims (voucher_id, used_at);

alter table public.charging_payments
  add column if not exists original_amount_myr numeric(12,2),
  add column if not exists discount_myr numeric(12,2) not null default 0,
  add column if not exists voucher_code text,
  add column if not exists voucher_claim_id uuid references public.voucher_claims(id) on delete set null;

update public.charging_payments
set original_amount_myr = amount_myr
where original_amount_myr is null;

alter table public.charging_payments
  alter column original_amount_myr set not null;

insert into public.vouchers (
  code, title, description, discount_type, discount_value, minimum_spend_myr,
  is_new_user_voucher, is_active
) values (
  'WELCOME5', 'Welcome to ChargeMY', 'RM 5.00 off your first eligible charging payment.',
  'fixed', 5.00, 10.00, true, true
) on conflict (code) do update set
  title = excluded.title,
  description = excluded.description,
  discount_type = excluded.discount_type,
  discount_value = excluded.discount_value,
  minimum_spend_myr = excluded.minimum_spend_myr,
  is_new_user_voucher = true,
  updated_at = now();

insert into public.voucher_claims (voucher_id, user_id)
select v.id, p.id
from public.vouchers v
cross join public.profiles p
where v.is_new_user_voucher
on conflict (voucher_id, user_id) do nothing;

alter table public.vouchers enable row level security;
alter table public.voucher_claims enable row level security;
drop policy if exists "vouchers admin manage" on public.vouchers;
drop policy if exists "active vouchers can be claimed" on public.vouchers;
drop policy if exists "voucher claims own read" on public.voucher_claims;
drop policy if exists "voucher claims own insert" on public.voucher_claims;
create policy "vouchers admin manage" on public.vouchers
  for all using (public.is_admin()) with check (public.is_admin());
create policy "active vouchers can be claimed" on public.vouchers
  for select using (
    (is_active and starts_at <= now() and (expires_at is null or expires_at > now()))
    or public.is_admin()
    or exists (
      select 1 from public.voucher_claims c
      where c.voucher_id = public.vouchers.id and c.user_id = auth.uid()
    )
  );
create policy "voucher claims own read" on public.voucher_claims
  for select using (auth.uid() = user_id or public.is_admin());
create policy "voucher claims own insert" on public.voucher_claims
  for insert with check (auth.uid() = user_id);

create or replace function public.validate_voucher_claim()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_voucher public.vouchers;
  v_claim_count integer;
begin
  select * into v_voucher from public.vouchers where id = new.voucher_id;
  if v_voucher.id is null or not v_voucher.is_active
     or v_voucher.starts_at > now()
     or (v_voucher.expires_at is not null and v_voucher.expires_at <= now()) then
    raise exception 'This voucher code is not available.';
  end if;
  select count(*) into v_claim_count from public.voucher_claims
  where voucher_id = new.voucher_id;
  if v_voucher.max_redemptions is not null
     and v_claim_count >= v_voucher.max_redemptions then
    raise exception 'This voucher has reached its claim limit.';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_voucher_claim on public.voucher_claims;
create trigger validate_voucher_claim
before insert on public.voucher_claims
for each row execute procedure public.validate_voucher_claim();

drop function if exists public.my_vouchers();
create function public.my_vouchers()
returns table (
  claim_id uuid,
  code text,
  title text,
  description text,
  discount_type text,
  discount_value numeric,
  minimum_spend_myr numeric,
  claimed_at timestamptz,
  expires_at timestamptz,
  used_at timestamptz,
  is_active boolean,
  is_reward_voucher boolean
) language sql security definer set search_path = public as $$
  select c.id, v.code, v.title, v.description, v.discount_type,
    v.discount_value, v.minimum_spend_myr, c.claimed_at, v.expires_at,
    c.used_at, v.is_active, v.is_reward_voucher
  from public.voucher_claims c
  join public.vouchers v on v.id = c.voucher_id
  where c.user_id = auth.uid()
  order by c.used_at nulls first, v.expires_at nulls last, c.claimed_at desc;
$$;

create or replace function public.claim_voucher(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_voucher public.vouchers;
  v_claim_id uuid;
  v_claim_count integer;
begin
  if auth.uid() is null then raise exception 'Sign in is required.'; end if;
  select * into v_voucher from public.vouchers
  where upper(code) = upper(trim(p_code)) and is_active
    and starts_at <= now() and (expires_at is null or expires_at > now());
  if v_voucher.id is null then raise exception 'This voucher code is not available.'; end if;
  select count(*) into v_claim_count from public.voucher_claims
  where voucher_id = v_voucher.id;
  if v_voucher.max_redemptions is not null and v_claim_count >= v_voucher.max_redemptions then
    raise exception 'This voucher has reached its claim limit.';
  end if;
  insert into public.voucher_claims (voucher_id, user_id)
  values (v_voucher.id, auth.uid())
  on conflict (voucher_id, user_id) do update set voucher_id = excluded.voucher_id
  returning id into v_claim_id;
  return v_claim_id;
end;
$$;

create or replace function public.preview_voucher_payment(
  p_session_id uuid,
  p_subtotal_myr numeric,
  p_voucher_claim_id uuid default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_claim public.voucher_claims;
  v_voucher public.vouchers;
  v_discount numeric(12,2) := 0;
  v_final numeric(12,2);
begin
  if auth.uid() is null then raise exception 'Sign in is required.'; end if;
  if p_subtotal_myr < 0 then raise exception 'The payment amount is invalid.'; end if;
  if not exists (
    select 1 from public.charging_sessions
    where id = p_session_id and user_id = auth.uid()
      and state in ('occupied', 'completed')
  ) then
    raise exception 'The charging session is no longer available for payment.';
  end if;
  if p_voucher_claim_id is not null then
    select * into v_claim from public.voucher_claims
    where id = p_voucher_claim_id and user_id = auth.uid() and used_at is null;
    if v_claim.id is null then raise exception 'This voucher is no longer available.'; end if;
    select * into v_voucher from public.vouchers where id = v_claim.voucher_id;
    if v_voucher.id is null or not v_voucher.is_active
       or v_voucher.starts_at > now()
       or (v_voucher.expires_at is not null and v_voucher.expires_at <= now()) then
      raise exception 'This voucher is no longer available.';
    end if;
    if p_subtotal_myr < v_voucher.minimum_spend_myr then
      raise exception 'This voucher requires a minimum spend of RM %.',
        to_char(v_voucher.minimum_spend_myr, 'FM999999990.00');
    end if;
    v_discount := case
      when v_voucher.discount_type = 'percent'
        then round(p_subtotal_myr * v_voucher.discount_value / 100, 2)
      else v_voucher.discount_value
    end;
  end if;
  v_discount := least(round(v_discount, 2), round(p_subtotal_myr, 2));
  v_final := round(p_subtotal_myr - v_discount, 2);
  return jsonb_build_object(
    'original_amount_myr', round(p_subtotal_myr, 2),
    'discount_myr', v_discount,
    'final_amount_myr', v_final,
    'voucher_code', v_voucher.code
  );
end;
$$;

drop function if exists public.record_charging_payment(uuid, numeric, numeric, text);
drop function if exists public.record_charging_payment(uuid, numeric, numeric, text, uuid, numeric);
create or replace function public.record_charging_payment(
  p_session_id uuid,
  p_amount_myr numeric,
  p_energy_kwh numeric,
  p_receipt_email text default null,
  p_voucher_claim_id uuid default null,
  p_original_amount_myr numeric default null
) returns public.charging_payments
language plpgsql security definer set search_path = public as $$
declare
  v_session public.charging_sessions;
  v_payment public.charging_payments;
  v_quote jsonb;
  v_original numeric(12,2);
  v_discount numeric(12,2);
  v_code text;
begin
  if auth.uid() is null then raise exception 'Sign in is required.'; end if;
  p_amount_myr := round(p_amount_myr, 2);
  p_energy_kwh := round(p_energy_kwh, 2);
  v_original := round(coalesce(p_original_amount_myr, p_amount_myr), 2);
  if p_amount_myr < 0 or p_energy_kwh < 0 or v_original < p_amount_myr then
    raise exception 'Payment values are invalid.';
  end if;
  v_quote := public.preview_voucher_payment(
    p_session_id, v_original, p_voucher_claim_id
  );
  v_discount := coalesce((v_quote ->> 'discount_myr')::numeric, 0);
  v_code := nullif(v_quote ->> 'voucher_code', '');
  if abs(p_amount_myr - (v_quote ->> 'final_amount_myr')::numeric) > 0.01 then
    raise exception 'The payment amount does not match the selected voucher.';
  end if;
  select * into v_session from public.charging_sessions
  where id = p_session_id and user_id = auth.uid() and state = 'completed';
  if v_session.id is null then raise exception 'Completed charging session not found.'; end if;
  insert into public.charging_payments
    (session_id, user_id, station_id, energy_kwh, amount_myr, original_amount_myr,
     discount_myr, voucher_code, voucher_claim_id, receipt_email)
  values
    (v_session.id, auth.uid(), v_session.station_id, p_energy_kwh, p_amount_myr,
     v_original, v_discount, v_code, p_voucher_claim_id,
     nullif(trim(p_receipt_email), ''))
  on conflict (session_id) do update set
    energy_kwh = excluded.energy_kwh,
    amount_myr = excluded.amount_myr,
    original_amount_myr = excluded.original_amount_myr,
    discount_myr = excluded.discount_myr,
    voucher_code = excluded.voucher_code,
    voucher_claim_id = excluded.voucher_claim_id,
    receipt_email = excluded.receipt_email,
    status = 'paid',
    paid_at = now()
  returning * into v_payment;
  if p_voucher_claim_id is not null then
    update public.voucher_claims set used_at = now()
    where id = p_voucher_claim_id and user_id = auth.uid() and used_at is null;
    if not found then raise exception 'This voucher has already been used.'; end if;
  end if;
  return v_payment;
end;
$$;

create or replace function public.admin_create_voucher(
  p_code text,
  p_title text,
  p_description text,
  p_discount_type text,
  p_discount_value numeric,
  p_minimum_spend_myr numeric,
  p_max_redemptions integer default null,
  p_expires_at timestamptz default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'Administrator access is required.'; end if;
  if upper(trim(p_code)) !~ '^[A-Z0-9-]{3,32}$' then
    raise exception 'Use 3 to 32 letters, numbers, or hyphens for the voucher code.';
  end if;
  if length(trim(p_title)) = 0 or p_discount_type not in ('fixed', 'percent')
     or p_discount_value <= 0 or p_minimum_spend_myr < 0
     or (p_discount_type = 'percent' and p_discount_value > 100) then
    raise exception 'The voucher details are invalid.';
  end if;
  if p_expires_at is not null and p_expires_at <= now() then
    raise exception 'Choose a future expiry date.';
  end if;
  insert into public.vouchers (
    code, title, description, discount_type, discount_value, minimum_spend_myr,
    max_redemptions, expires_at, created_by
  ) values (
    upper(trim(p_code)), trim(p_title), trim(coalesce(p_description, '')),
    p_discount_type, round(p_discount_value, 2), round(p_minimum_spend_myr, 2),
    p_max_redemptions, p_expires_at, auth.uid()
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.admin_set_voucher_active(
  p_voucher_id uuid,
  p_is_active boolean
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Administrator access is required.'; end if;
  update public.vouchers set is_active = p_is_active, updated_at = now()
  where id = p_voucher_id and not is_new_user_voucher;
  if not found then raise exception 'This voucher could not be updated.'; end if;
end;
$$;

create or replace function public.admin_voucher_overview()
returns table (
  id uuid,
  code text,
  title text,
  description text,
  discount_type text,
  discount_value numeric,
  minimum_spend_myr numeric,
  max_redemptions integer,
  is_new_user_voucher boolean,
  is_active boolean,
  expires_at timestamptz,
  claim_count bigint,
  redeemed_count bigint
) language sql security definer set search_path = public as $$
  select v.id, v.code, v.title, v.description, v.discount_type,
    v.discount_value, v.minimum_spend_myr, v.max_redemptions,
    v.is_new_user_voucher, v.is_active, v.expires_at,
    count(c.id), count(c.used_at)
  from public.vouchers v
  left join public.voucher_claims c on c.voucher_id = v.id
  where public.is_admin() and not v.is_reward_voucher
  group by v.id
  order by v.is_new_user_voucher desc, v.created_at desc;
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, display_name, password_set)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'display_name', ''),
    new.encrypted_password is not null
  ) on conflict (id) do update set
    email = excluded.email,
    display_name = case
      when public.profiles.display_name = '' then excluded.display_name
      else public.profiles.display_name
    end,
    password_set = public.profiles.password_set or excluded.password_set,
    updated_at = now();
  insert into public.voucher_claims (voucher_id, user_id)
  select id, new.id from public.vouchers
  where is_new_user_voucher and is_active
  on conflict (voucher_id, user_id) do nothing;
  return new;
end;
$$;

grant execute on function public.my_vouchers() to authenticated;
grant execute on function public.claim_voucher(text) to authenticated;
grant execute on function public.preview_voucher_payment(uuid, numeric, uuid) to authenticated;
grant execute on function public.record_charging_payment(uuid, numeric, numeric, text, uuid, numeric) to authenticated;
grant execute on function public.admin_create_voucher(text, text, text, text, numeric, numeric, integer, timestamptz) to authenticated;
grant execute on function public.admin_set_voucher_active(uuid, boolean) to authenticated;
grant execute on function public.admin_voucher_overview() to authenticated;

create table if not exists public.reward_catalog (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  points_required integer not null check (points_required > 0),
  discount_myr numeric(12,2) not null check (discount_myr > 0),
  minimum_spend_myr numeric(12,2) not null check (minimum_spend_myr >= discount_myr + 2),
  is_active boolean not null default true,
  is_deleted boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.reward_catalog
  add column if not exists is_deleted boolean not null default false;

alter table public.vouchers
  add column if not exists reward_id uuid references public.reward_catalog(id) on delete set null;

update public.vouchers
set is_reward_voucher = true
where reward_id is not null or upper(code) like 'RW-%';

alter table public.charging_payments
  add column if not exists points_earned integer not null default 0;

create table if not exists public.reward_accounts (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  points_balance integer not null default 0 check (points_balance >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.reward_redemptions (
  id uuid primary key default gen_random_uuid(),
  reward_id uuid references public.reward_catalog(id) on delete set null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  points_spent integer not null check (points_spent > 0),
  reward_title text not null,
  discount_myr numeric(12,2) not null check (discount_myr > 0),
  voucher_code text not null,
  voucher_claim_id uuid not null unique references public.voucher_claims(id) on delete restrict,
  redeemed_at timestamptz not null default now()
);

create table if not exists public.reward_point_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  points integer not null check (points <> 0),
  transaction_type text not null check (transaction_type in ('payment', 'redemption')),
  payment_id uuid unique references public.charging_payments(id) on delete set null,
  reward_redemption_id uuid unique references public.reward_redemptions(id) on delete set null,
  description text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists reward_redemptions_user_idx
  on public.reward_redemptions (user_id, redeemed_at desc);
create index if not exists reward_point_transactions_user_idx
  on public.reward_point_transactions (user_id, created_at desc);

insert into public.reward_accounts (user_id)
select id from public.profiles
on conflict (user_id) do nothing;

insert into public.reward_catalog
  (id, title, description, points_required, discount_myr, minimum_spend_myr)
values
  ('00000000-0000-0000-0000-000000000050', 'RM2 charging reward', 'Redeem 50 points for RM2 off a charging payment.', 50, 2, 4),
  ('00000000-0000-0000-0000-000000000100', 'RM5 charging reward', 'Redeem 100 points for RM5 off a charging payment.', 100, 5, 7),
  ('00000000-0000-0000-0000-000000000200', 'RM12 charging reward', 'Redeem 200 points for RM12 off a charging payment.', 200, 12, 14),
  ('00000000-0000-0000-0000-000000000300', 'RM20 charging reward', 'Redeem 300 points for RM20 off a charging payment.', 300, 20, 22)
on conflict (id) do nothing;

alter table public.reward_catalog enable row level security;
alter table public.reward_accounts enable row level security;
alter table public.reward_redemptions enable row level security;
alter table public.reward_point_transactions enable row level security;

drop policy if exists "reward catalog read" on public.reward_catalog;
drop policy if exists "reward catalog admin manage" on public.reward_catalog;
drop policy if exists "reward accounts own read" on public.reward_accounts;
drop policy if exists "reward redemptions own read" on public.reward_redemptions;
drop policy if exists "reward transactions own read" on public.reward_point_transactions;

create policy "reward catalog read" on public.reward_catalog
  for select using ((is_active and not is_deleted) or public.is_admin());
create policy "reward catalog admin manage" on public.reward_catalog
  for all using (public.is_admin()) with check (public.is_admin());
create policy "reward accounts own read" on public.reward_accounts
  for select using (auth.uid() = user_id or public.is_admin());
create policy "reward redemptions own read" on public.reward_redemptions
  for select using (auth.uid() = user_id or public.is_admin());
create policy "reward transactions own read" on public.reward_point_transactions
  for select using (auth.uid() = user_id or public.is_admin());

drop policy if exists "active vouchers can be claimed" on public.vouchers;
create policy "active vouchers can be claimed" on public.vouchers
  for select using (
    (not is_reward_voucher and is_active and starts_at <= now()
      and (expires_at is null or expires_at > now()))
    or public.is_admin()
    or exists (
      select 1 from public.voucher_claims c
      where c.voucher_id = public.vouchers.id and c.user_id = auth.uid()
    )
  );

create or replace function public.claim_voucher(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_voucher public.vouchers;
  v_claim_id uuid;
  v_claim_count integer;
begin
  if auth.uid() is null then raise exception 'Sign in is required.'; end if;
  select * into v_voucher from public.vouchers
  where upper(code) = upper(trim(p_code)) and not is_reward_voucher and is_active
    and starts_at <= now() and (expires_at is null or expires_at > now());
  if v_voucher.id is null then raise exception 'This voucher code is not available.'; end if;
  select count(*) into v_claim_count from public.voucher_claims
  where voucher_id = v_voucher.id;
  if v_voucher.max_redemptions is not null and v_claim_count >= v_voucher.max_redemptions then
    raise exception 'This voucher has reached its claim limit.';
  end if;
  insert into public.voucher_claims (voucher_id, user_id)
  values (v_voucher.id, auth.uid())
  on conflict (voucher_id, user_id) do update set voucher_id = excluded.voucher_id
  returning id into v_claim_id;
  return v_claim_id;
end;
$$;

create or replace function public.my_reward_points()
returns integer language sql security definer set search_path = public as $$
  select coalesce((
    select points_balance from public.reward_accounts where user_id = auth.uid()
  ), 0);
$$;

create or replace function public.my_reward_redemptions()
returns table (
  id uuid,
  reward_title text,
  points_spent integer,
  discount_myr numeric,
  voucher_code text,
  redeemed_at timestamptz
) language sql security definer set search_path = public as $$
  select r.id, r.reward_title, r.points_spent, r.discount_myr,
    r.voucher_code, r.redeemed_at
  from public.reward_redemptions r
  where r.user_id = auth.uid()
  order by r.redeemed_at desc;
$$;

create or replace function public.redeem_reward(p_reward_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_reward public.reward_catalog;
  v_balance integer;
  v_code text;
  v_voucher_id uuid;
  v_claim_id uuid;
  v_redemption_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in is required.'; end if;
  select * into v_reward from public.reward_catalog
  where id = p_reward_id and is_active and not is_deleted for update;
  if v_reward.id is null then raise exception 'This reward is no longer available.'; end if;
  insert into public.reward_accounts (user_id) values (auth.uid())
  on conflict (user_id) do nothing;
  select points_balance into v_balance from public.reward_accounts
  where user_id = auth.uid() for update;
  if v_balance < v_reward.points_required then
    raise exception 'You do not have enough points for this reward.';
  end if;
  v_code := 'RW-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
  insert into public.vouchers (
    code, title, description, discount_type, discount_value,
    minimum_spend_myr, max_redemptions, is_active, created_by, reward_id,
    is_reward_voucher
  ) values (
    v_code, v_reward.title, v_reward.description, 'fixed', v_reward.discount_myr,
    greatest(v_reward.minimum_spend_myr, v_reward.discount_myr + 2),
    1, true, v_reward.created_by, v_reward.id, true
  ) returning id into v_voucher_id;
  insert into public.voucher_claims (voucher_id, user_id)
  values (v_voucher_id, auth.uid()) returning id into v_claim_id;
  insert into public.reward_redemptions (
    reward_id, user_id, points_spent, reward_title, discount_myr,
    voucher_code, voucher_claim_id
  ) values (
    v_reward.id, auth.uid(), v_reward.points_required, v_reward.title,
    v_reward.discount_myr, v_code, v_claim_id
  ) returning id into v_redemption_id;
  update public.reward_accounts
  set points_balance = points_balance - v_reward.points_required, updated_at = now()
  where user_id = auth.uid();
  insert into public.reward_point_transactions (
    user_id, points, transaction_type, reward_redemption_id, description
  ) values (
    auth.uid(), -v_reward.points_required, 'redemption', v_redemption_id,
    'Redeemed ' || v_reward.title
  );
  return jsonb_build_object(
    'points_balance', v_balance - v_reward.points_required,
    'voucher_claim_id', v_claim_id,
    'voucher_code', v_code
  );
end;
$$;

create or replace function public.preview_voucher_payment(
  p_session_id uuid,
  p_subtotal_myr numeric,
  p_voucher_claim_id uuid default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_claim public.voucher_claims;
  v_voucher public.vouchers;
  v_discount numeric(12,2) := 0;
  v_final numeric(12,2);
  v_minimum numeric(12,2);
begin
  if auth.uid() is null then raise exception 'Sign in is required.'; end if;
  if p_subtotal_myr < 0 then raise exception 'The payment amount is invalid.'; end if;
  if not exists (
    select 1 from public.charging_sessions
    where id = p_session_id and user_id = auth.uid()
      and state in ('occupied', 'completed')
  ) then
    raise exception 'The charging session is no longer available for payment.';
  end if;
  if p_voucher_claim_id is not null then
    select * into v_claim from public.voucher_claims
    where id = p_voucher_claim_id and user_id = auth.uid() and used_at is null;
    if v_claim.id is null then raise exception 'This voucher is no longer available.'; end if;
    select * into v_voucher from public.vouchers where id = v_claim.voucher_id;
    if v_voucher.id is null or not v_voucher.is_active
       or v_voucher.starts_at > now()
       or (v_voucher.expires_at is not null and v_voucher.expires_at <= now()) then
      raise exception 'This voucher is no longer available.';
    end if;
    v_minimum := case
      when v_voucher.discount_type = 'fixed'
        then greatest(v_voucher.minimum_spend_myr, v_voucher.discount_value + 2)
      else v_voucher.minimum_spend_myr
    end;
    if p_subtotal_myr < v_minimum then
      raise exception 'This voucher requires a minimum spend of RM %.',
        to_char(v_minimum, 'FM999999990.00');
    end if;
    v_discount := case
      when v_voucher.discount_type = 'percent'
        then round(p_subtotal_myr * v_voucher.discount_value / 100, 2)
      else v_voucher.discount_value
    end;
  end if;
  v_discount := least(round(v_discount, 2), round(p_subtotal_myr, 2));
  v_final := round(p_subtotal_myr - v_discount, 2);
  if p_voucher_claim_id is not null and v_final < 2 then
    raise exception 'The final payment must be at least RM 2.00.';
  end if;
  return jsonb_build_object(
    'original_amount_myr', round(p_subtotal_myr, 2),
    'discount_myr', v_discount,
    'final_amount_myr', v_final,
    'voucher_code', v_voucher.code
  );
end;
$$;

create or replace function public.record_charging_payment(
  p_session_id uuid,
  p_amount_myr numeric,
  p_energy_kwh numeric,
  p_receipt_email text default null,
  p_voucher_claim_id uuid default null,
  p_original_amount_myr numeric default null
) returns public.charging_payments
language plpgsql security definer set search_path = public as $$
declare
  v_session public.charging_sessions;
  v_payment public.charging_payments;
  v_quote jsonb;
  v_original numeric(12,2);
  v_discount numeric(12,2);
  v_code text;
  v_points integer;
  v_awarded integer;
begin
  if auth.uid() is null then raise exception 'Sign in is required.'; end if;
  p_amount_myr := round(p_amount_myr, 2);
  p_energy_kwh := round(p_energy_kwh, 2);
  v_original := round(coalesce(p_original_amount_myr, p_amount_myr), 2);
  if p_amount_myr < 0 or p_energy_kwh < 0 or v_original < p_amount_myr then
    raise exception 'Payment values are invalid.';
  end if;
  v_quote := public.preview_voucher_payment(
    p_session_id, v_original, p_voucher_claim_id
  );
  v_discount := coalesce((v_quote ->> 'discount_myr')::numeric, 0);
  v_code := nullif(v_quote ->> 'voucher_code', '');
  if abs(p_amount_myr - (v_quote ->> 'final_amount_myr')::numeric) > 0.01 then
    raise exception 'The payment amount does not match the selected voucher.';
  end if;
  select * into v_session from public.charging_sessions
  where id = p_session_id and user_id = auth.uid() and state = 'completed';
  if v_session.id is null then raise exception 'Completed charging session not found.'; end if;
  insert into public.charging_payments
    (session_id, user_id, station_id, energy_kwh, amount_myr, original_amount_myr,
     discount_myr, voucher_code, voucher_claim_id, receipt_email)
  values
    (v_session.id, auth.uid(), v_session.station_id, p_energy_kwh, p_amount_myr,
     v_original, v_discount, v_code, p_voucher_claim_id,
     nullif(trim(p_receipt_email), ''))
  on conflict (session_id) do update set
    energy_kwh = excluded.energy_kwh,
    amount_myr = excluded.amount_myr,
    original_amount_myr = excluded.original_amount_myr,
    discount_myr = excluded.discount_myr,
    voucher_code = excluded.voucher_code,
    voucher_claim_id = excluded.voucher_claim_id,
    receipt_email = excluded.receipt_email,
    status = 'paid',
    paid_at = now()
  returning * into v_payment;
  if p_voucher_claim_id is not null then
    update public.voucher_claims set used_at = now()
    where id = p_voucher_claim_id and user_id = auth.uid() and used_at is null;
    if not found then raise exception 'This voucher has already been used.'; end if;
  end if;
  v_points := floor(p_amount_myr)::integer;
  v_awarded := 0;
  if v_points > 0 then
    insert into public.reward_accounts (user_id) values (auth.uid())
    on conflict (user_id) do nothing;
    insert into public.reward_point_transactions (
      user_id, points, transaction_type, payment_id, description
    ) values (
      auth.uid(), v_points, 'payment', v_payment.id,
      'Charging payment points'
    ) on conflict (payment_id) do nothing
    returning points into v_awarded;
    if v_awarded is not null and v_awarded > 0 then
      update public.reward_accounts
      set points_balance = points_balance + v_awarded, updated_at = now()
      where user_id = auth.uid();
      update public.charging_payments set points_earned = v_awarded
      where id = v_payment.id returning * into v_payment;
    end if;
  end if;
  return v_payment;
end;
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, display_name, password_set)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'display_name', ''),
    new.encrypted_password is not null
  ) on conflict (id) do update set
    email = excluded.email,
    display_name = case
      when public.profiles.display_name = '' then excluded.display_name
      else public.profiles.display_name
    end,
    password_set = public.profiles.password_set or excluded.password_set,
    updated_at = now();
  insert into public.voucher_claims (voucher_id, user_id)
  select id, new.id from public.vouchers
  where is_new_user_voucher and is_active
  on conflict (voucher_id, user_id) do nothing;
  insert into public.reward_accounts (user_id) values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

grant select on public.reward_catalog to authenticated;
grant insert, update, delete on public.reward_catalog to authenticated;
grant select on public.reward_accounts to authenticated;
grant select on public.reward_redemptions to authenticated;
grant select on public.reward_point_transactions to authenticated;
grant execute on function public.my_reward_points() to authenticated;
grant execute on function public.my_reward_redemptions() to authenticated;
grant execute on function public.redeem_reward(uuid) to authenticated;

drop function if exists public.my_vouchers();
create function public.my_vouchers()
returns table (
  claim_id uuid,
  code text,
  title text,
  description text,
  discount_type text,
  discount_value numeric,
  minimum_spend_myr numeric,
  claimed_at timestamptz,
  expires_at timestamptz,
  used_at timestamptz,
  is_active boolean,
  is_reward_voucher boolean
) language sql security definer set search_path = public as $$
  select c.id, v.code, v.title, v.description, v.discount_type,
    v.discount_value, v.minimum_spend_myr, c.claimed_at, v.expires_at,
    c.used_at, v.is_active, v.is_reward_voucher
  from public.voucher_claims c
  join public.vouchers v on v.id = c.voucher_id
  where c.user_id = auth.uid()
  order by c.used_at nulls first, v.expires_at nulls last, c.claimed_at desc;
$$;

grant execute on function public.my_vouchers() to authenticated;
