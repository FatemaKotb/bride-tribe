-- =====================================================================
-- Bridal Party Coordination App: Database Schema (Supabase / Postgres)
-- Based on the requirements (BR-01 to BR-34), the ERD, and the backend
-- contract. This file creates types, tables, constraints, indexes,
-- integrity triggers, and display labels.
--
-- Business flows (claiming, requests, automatic cancellations) live in
-- the server functions, which come in the next file.
--
-- Before running on Supabase: enable Anonymous Sign-Ins under
-- Authentication > Providers.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. Enums
-- ---------------------------------------------------------------------

create type member_role as enum ('bride', 'maid_of_honor', 'bridesmaid');

create type member_status as enum (
  'at_home', 'at_brides_house', 'transporting_to_hotel',
  'between_hotel_and_venue', 'personal_errand', 'errand_for_bride',
  'doing_makeup', 'dressing_up', 'photo_session', 'at_venue', 'heading_home'
);

create type item_kind         as enum ('item', 'container');
create type item_visibility   as enum ('private', 'shared');
create type item_type         as enum ('personal', 'claimable');
create type trip              as enum ('to_hotel', 'hotel_to_venue', 'return_home');
create type area              as enum ('maadi', 'zahraa_el_maadi', 'october', 'other');
create type stop_purpose      as enum ('myself', 'bride');
create type request_direction as enum ('ask', 'offer');
create type request_kind      as enum ('passenger', 'cargo');
create type request_state     as enum ('pending', 'confirmed', 'declined', 'cancelled');
create type cancel_reason     as enum ('by_sender', 'left_car', 'car_withdrawn', 'auto');
create type pickup_type       as enum ('bride_home', 'vendor_address', 'custom');

-- ---------------------------------------------------------------------
-- 2. Shared trigger: keep updated_at current
-- ---------------------------------------------------------------------

create function set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Members and sessions (BR-01, BR-03, BR-26)
-- ---------------------------------------------------------------------

create table member (
  id                   uuid primary key default gen_random_uuid(),
  name                 text not null unique check (btrim(name) <> ''),
  role                 member_role not null,
  status               member_status not null default 'at_home',
  status_updated_at    timestamptz not null default now(),
  attention_cleared_at timestamptz not null default now(),
  created_at           timestamptz not null default now()
);

-- Links a Supabase anonymous session to the member who picked her name.
create table member_session (
  auth_user_id uuid primary key references auth.users (id) on delete cascade,
  member_id    uuid not null references member (id) on delete cascade,
  created_at   timestamptz not null default now()
);

create index member_session_member_idx on member_session (member_id);

-- The current member, used by every server function.
create function current_member_id() returns uuid
language sql stable security definer set search_path = public as $$
  select member_id from member_session where auth_user_id = auth.uid();
$$;

-- ---------------------------------------------------------------------
-- 4. Items and containers (BR-04 to BR-11a)
-- ---------------------------------------------------------------------

create table item (
  id            uuid primary key default gen_random_uuid(),
  kind          item_kind not null,
  owner_id      uuid not null references member (id),
  parent_id     uuid references item (id) on delete set null,  -- deleting a container moves its contents out
  group_id      uuid,
  name          text not null check (btrim(name) <> ''),
  emoji         text,
  description   text,
  quantity      int check (quantity > 0),
  tags          text[] not null default '{}',
  visibility    item_visibility,
  type          item_type,
  claimed_by_id uuid references member (id),
  is_packed     boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- Items need their item-only fields; containers must leave them empty.
  constraint item_kind_fields check (
    (kind = 'item'
      and visibility is not null and type is not null and group_id is not null)
    or
    (kind = 'container'
      and visibility is null and type is null and group_id is null
      and quantity is null and claimed_by_id is null and parent_id is null)
  ),
  -- BR-06: claimable items are always shared.
  constraint item_claimable_shared check (type is distinct from 'claimable' or visibility = 'shared'),
  -- BR-08: only claimable items can be claimed.
  constraint item_claim_only_claimable check (claimed_by_id is null or type = 'claimable'),
  constraint item_not_own_parent check (parent_id is distinct from id)
);

create index item_owner_idx   on item (owner_id);
create index item_parent_idx  on item (parent_id);
create index item_group_idx   on item (group_id);
create index item_claimer_idx on item (claimed_by_id);
create index item_tags_idx    on item using gin (tags);

create trigger item_updated_at before update on item
  for each row execute function set_updated_at();

-- BR-28: vendor details, one-to-one with a claimable item.
create table vendor_details (
  item_id       uuid primary key references item (id) on delete cascade,
  vendor_name   text not null check (btrim(vendor_name) <> ''),
  service       text,
  phone         text,
  address       text,
  expected_time time,
  amount_egp    numeric(10, 2) check (amount_egp >= 0),
  details       text
);

-- Cross-row rules for items that a CHECK constraint can't express.
create function check_item_integrity() returns trigger
language plpgsql as $$
declare
  parent      item%rowtype;
  bag_owner   uuid;  -- whose bag this item may be in
begin
  -- BR-10: a container must be a container, and it holds only its
  -- owner's cargo (BR-24): their personal items, and the claimable items
  -- they claimed. So an unclaimed item is in no bag, and a claimed one
  -- only in its claimer's (ruling 2026-10-08, narrower than the ERD's
  -- "owner or claimer").
  if new.parent_id is not null then
    select * into parent from item where id = new.parent_id;
    if not found or parent.kind <> 'container' then
      raise exception using
        message = 'Pick a bag or box.',
        hint    = 'NOT_A_CONTAINER';
    end if;
    bag_owner := case when new.type = 'claimable' then new.claimed_by_id
                      else new.owner_id end;
    if parent.owner_id is distinct from bag_owner then
      raise exception using
        message = 'You can''t change this.',
        hint    = 'NOT_ALLOWED';
    end if;
  end if;

  -- BR-28: an item with vendor details must stay claimable.
  if tg_op = 'UPDATE'
     and new.type is distinct from 'claimable'
     and exists (select 1 from vendor_details where item_id = new.id) then
    raise exception using
      message = 'Release the claim and remove the vendor details before making this personal.',
      hint    = 'TYPE_CHANGE_NOT_ALLOWED';
  end if;

  return new;
end;
$$;

create trigger item_integrity before insert or update on item
  for each row execute function check_item_integrity();

create function check_vendor_details_integrity() returns trigger
language plpgsql as $$
begin
  if not exists (
    select 1 from item
    where id = new.item_id and kind = 'item' and type = 'claimable'
  ) then
    raise exception using
      message = 'Vendor details can only be added to claimable items.',
      hint    = 'VENDOR_NOT_ALLOWED';
  end if;
  return new;
end;
$$;

create trigger vendor_details_integrity before insert or update on vendor_details
  for each row execute function check_vendor_details_integrity();

-- ---------------------------------------------------------------------
-- 5. Cars (BR-13 to BR-19)
-- ---------------------------------------------------------------------

create table car (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null references member (id),
  trip               trip not null,
  seats              int not null check (seats >= 0),
  departure_earliest time not null,
  departure_latest   time not null,
  home_area          area,
  home_area_other    text,
  minutes_to_bride   int check (minutes_to_bride >= 0),
  minutes_to_hotel   int check (minutes_to_hotel >= 0),
  trunk_percent      int not null check (trunk_percent in (0, 25, 50, 75, 100)),
  notes              text,
  withdrawn_at       timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),

  -- Target of the composite foreign keys from request, car_stop, and car_dropoff_area.
  constraint car_id_trip_unique unique (id, trip),
  constraint car_window check (departure_earliest <= departure_latest),
  -- BR-14: home area and travel times exist only for the To the hotel trip.
  constraint car_to_hotel_fields check (
    (trip = 'to_hotel' and home_area is not null)
    or
    (trip <> 'to_hotel' and home_area is null and home_area_other is null
      and minutes_to_bride is null and minutes_to_hotel is null)
  ),
  -- "Other" text is required for "other" and forbidden otherwise.
  constraint car_home_area_other check (
    home_area is null or ((home_area = 'other') = (home_area_other is not null))
  )
);

-- One active car per member per trip. A withdrawn car frees the slot.
create unique index car_one_per_trip on car (owner_id, trip) where withdrawn_at is null;

create trigger car_updated_at before update on car
  for each row execute function set_updated_at();

-- BR-14: stops exist only for the To the hotel trip, enforced by the
-- composite foreign key on (car_id, car_trip).
create table car_stop (
  id          uuid primary key default gen_random_uuid(),
  car_id      uuid not null,
  car_trip    trip not null default 'to_hotel' check (car_trip = 'to_hotel'),
  position    int not null check (position >= 0),
  description text not null check (btrim(description) <> ''),
  purpose     stop_purpose not null,
  foreign key (car_id, car_trip) references car (id, trip) on delete cascade,
  unique (car_id, position)
);

-- BR-15: drop-off areas exist only for the Return home trip.
create table car_dropoff_area (
  id         uuid primary key default gen_random_uuid(),
  car_id     uuid not null,
  car_trip   trip not null default 'return_home' check (car_trip = 'return_home'),
  area       area not null,
  area_other text,
  foreign key (car_id, car_trip) references car (id, trip) on delete cascade,
  unique (car_id, area),
  check ((area = 'other') = (area_other is not null))
);

-- ---------------------------------------------------------------------
-- 6. Requests (BR-20 to BR-25)
-- ---------------------------------------------------------------------

create table request (
  id            uuid primary key default gen_random_uuid(),
  car_id        uuid not null,
  trip          trip not null,
  direction     request_direction not null,
  kind          request_kind not null,
  created_by_id uuid not null references member (id),
  passenger_id  uuid references member (id),
  item_id       uuid references item (id) on delete set null,  -- see note below
  state         request_state not null default 'pending',
  cancel_reason cancel_reason,
  pickup_type   pickup_type,
  pickup_address text,
  ready_at      time,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- The request's trip always matches its car's trip.
  foreign key (car_id, trip) references car (id, trip),

  -- Passenger requests have a passenger and no cargo fields. Cargo requests
  -- have an item and pickup details. A deleted item leaves its cancelled
  -- request behind with item_id = null, so the car owner still sees it.
  constraint request_kind_fields check (
    (kind = 'passenger'
      and passenger_id is not null and item_id is null
      and pickup_type is null and pickup_address is null and ready_at is null)
    or
    (kind = 'cargo'
      and passenger_id is null and pickup_type is not null
      and (item_id is not null or state = 'cancelled'))
  ),
  constraint request_custom_address check (
    pickup_type is null or ((pickup_type = 'custom') = (pickup_address is not null))
  ),
  constraint request_cancel_reason check ((state = 'cancelled') = (cancel_reason is not null))
);

-- BR-22: one confirmed car per trip, for passengers and for cargo.
create unique index request_one_car_per_trip_passenger
  on request (trip, passenger_id) where state = 'confirmed' and kind = 'passenger';
create unique index request_one_car_per_trip_item
  on request (trip, item_id) where state = 'confirmed' and kind = 'cargo';

-- No duplicate pending requests for the same subject and car.
create unique index request_no_duplicate_pending_passenger
  on request (car_id, passenger_id) where state = 'pending' and kind = 'passenger';
create unique index request_no_duplicate_pending_item
  on request (car_id, item_id) where state = 'pending' and kind = 'cargo';

create index request_car_idx       on request (car_id);
create index request_passenger_idx on request (passenger_id);
create index request_item_idx      on request (item_id);
create index request_creator_idx   on request (created_by_id);
create index request_updated_idx   on request (updated_at);

create trigger request_updated_at before update on request
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------
-- 7. Display labels (UI builds dropdowns and badges from these)
-- ---------------------------------------------------------------------

create table option_label (
  option_set text not null,
  value      text not null,
  label      text not null,
  emoji      text,
  sort_order int not null,
  primary key (option_set, value)
);

insert into option_label (option_set, value, label, emoji, sort_order) values
  ('role', 'bride',         'Bride',         '👰', 1),
  ('role', 'maid_of_honor', 'Maid of Honor', '💐', 2),
  ('role', 'bridesmaid',    'Bridesmaid',    '🌸', 3),

  ('status', 'at_home',                 'At home',                         '🏠', 1),
  ('status', 'at_brides_house',         'At the bride''s house',           '👰', 2),
  ('status', 'transporting_to_hotel',   'Transporting to the hotel',       '🚗', 3),
  ('status', 'doing_makeup',            'Doing makeup',                    '💄', 4),
  ('status', 'dressing_up',             'Dressing up',                     '👗', 5),
  ('status', 'photo_session',           'Photo session',                   '📸', 6),
  ('status', 'between_hotel_and_venue', 'Between the hotel and the venue', '🚙', 7),
  ('status', 'at_venue',                'At the venue',                    '🎉', 8),
  ('status', 'personal_errand',         'Running a personal errand',       '🏃', 9),
  ('status', 'errand_for_bride',        'Running an errand for the bride', '🛍️', 10),
  ('status', 'heading_home',            'Heading home',                    '🌙', 11),

  ('item_kind', 'item',      'Item',       null, 1),
  ('item_kind', 'container', 'Bag or box', '👜', 2),

  ('item_visibility', 'private', 'Private', '🔒', 1),
  ('item_visibility', 'shared',  'Shared',  '👥', 2),

  ('item_type', 'personal',  'Personal',  null, 1),
  ('item_type', 'claimable', 'Claimable', null, 2),

  ('trip', 'to_hotel',       'To the hotel',   '🏨', 1),
  ('trip', 'hotel_to_venue', 'Hotel to venue', '💒', 2),
  ('trip', 'return_home',    'Return home',    '🏠', 3),

  ('area', 'maadi',           'Maadi',           null, 1),
  ('area', 'zahraa_el_maadi', 'Zahraa El Maadi', null, 2),
  ('area', 'october',         'October',         null, 3),
  ('area', 'other',           'Other',           null, 4),

  ('trunk_percent', '0',   '0% (full)', null, 1),
  ('trunk_percent', '25',  '25%',       null, 2),
  ('trunk_percent', '50',  '50%',       null, 3),
  ('trunk_percent', '75',  '75%',       null, 4),
  ('trunk_percent', '100', '100% (empty)', null, 5),

  ('stop_purpose', 'myself', 'For myself',   null, 1),
  ('stop_purpose', 'bride',  'For the bride', null, 2),

  ('request_state', 'pending',   'Pending',   null, 1),
  ('request_state', 'confirmed', 'Confirmed', null, 2),
  ('request_state', 'declined',  'Declined',  null, 3),
  ('request_state', 'cancelled', 'Cancelled', null, 4),

  ('pickup_type', 'bride_home',     'Bride''s home',    null, 1),
  ('pickup_type', 'vendor_address', 'Vendor''s address', null, 2),
  ('pickup_type', 'custom',         'Other address',   null, 3);

-- ---------------------------------------------------------------------
-- 8. Access: no direct table access
-- ---------------------------------------------------------------------
-- The UI never touches tables. Every read and write goes through the
-- server functions (next file), which run as SECURITY DEFINER and check
-- the rules themselves. Row-level security is enabled with no policies,
-- so direct table access from the browser is denied.

alter table member           enable row level security;
alter table member_session   enable row level security;
alter table item             enable row level security;
alter table vendor_details   enable row level security;
alter table car              enable row level security;
alter table car_stop         enable row level security;
alter table car_dropoff_area enable row level security;
alter table request          enable row level security;
alter table option_label     enable row level security;

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, authenticated, public;
