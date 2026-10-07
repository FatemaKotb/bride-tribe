-- =====================================================================
-- Car functions (contract Section 4, BR-13 to BR-19, BR-23)
--
-- Rulings that fill gaps in the design documents:
-- - Lowering seats to exactly the confirmed passengers fills the car,
--   so its pending passenger requests are cancelled (2026-10-07).
-- - Negative seats or travel minutes raise INVALID_NUMBER (2026-10-08).
-- - An unknown car id raises NOT_FOUND (2026-10-08).
-- - A Return home departure window can cross midnight (2026-10-08).
-- - Trunk space is required, like seats and the departure window: the
--   form marks it required and the column is NOT NULL (2026-10-08).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Internal helpers (not callable through the API)
-- ---------------------------------------------------------------------

-- The car, locked until the calling function finishes, or NOT_FOUND.
-- Cars are never deleted, so this only happens with a bad id. A
-- withdrawn car is still found; callers check withdrawn_at.
create function lock_car(target_id uuid) returns car
language plpgsql set search_path = public as $$
declare
  found_car car%rowtype;
begin
  select * into found_car from car where id = target_id for update;
  if not found then
    raise exception using
      message = 'This car no longer exists.',
      hint    = 'NOT_FOUND';
  end if;
  return found_car;
end;
$$;

create function confirmed_passengers(target_car_id uuid) returns int
language sql stable set search_path = public as $$
  select count(*)::int from request
  where car_id = target_car_id and kind = 'passenger' and state = 'confirmed';
$$;

-- BR-23: once every seat is taken, the car's remaining pending passenger
-- requests are cancelled (auto). Cargo doesn't use seats.
create function cancel_passenger_requests_if_full(target_car_id uuid) returns void
language sql set search_path = public as $$
  update request
  set state = 'cancelled', cancel_reason = 'auto'
  where car_id = target_car_id and kind = 'passenger' and state = 'pending'
    and confirmed_passengers(target_car_id) >= (select seats from car where id = target_car_id);
$$;

-- The stops the member actually filled in. The form's list can hold
-- rows left completely empty; those are dropped.
create function clean_stops(stops jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select coalesce(jsonb_agg(stop order by pos), '[]')
  from jsonb_array_elements(
         case when jsonb_typeof(stops) = 'array' then stops else '[]' end
       ) with ordinality as t (stop, pos)
  where clean_text(stop ->> 'description') is not null
     or clean_text(stop ->> 'purpose') is not null;
$$;

-- Checks shared by register_car and update_car (BR-14, BR-15).
create function check_car_fields(
  car_trip      trip,
  seat_count    int,
  earliest      time,
  latest        time,
  home          area,
  home_other    text,
  to_bride      int,
  to_hotel      int,
  stops         jsonb,
  dropoff       area[],
  dropoff_other text
) returns void
language plpgsql set search_path = public as $$
begin
  -- Each trip asks its own questions.
  if (car_trip <> 'to_hotel'
      and (home is not null or clean_text(home_other) is not null
           or to_bride is not null or to_hotel is not null
           or jsonb_array_length(clean_stops(stops)) > 0))
     or (car_trip <> 'return_home'
         and (coalesce(cardinality(dropoff), 0) > 0 or clean_text(dropoff_other) is not null)) then
    raise exception using
      message = 'This field doesn''t apply to this trip.',
      hint    = 'FIELD_NOT_ALLOWED';
  end if;

  if seat_count < 0 then
    raise exception using
      message = 'Seats can''t be negative.',
      hint    = 'INVALID_NUMBER';
  end if;

  if to_bride < 0 or to_hotel < 0 then
    raise exception using
      message = 'Travel time can''t be negative.',
      hint    = 'INVALID_NUMBER';
  end if;

  -- A Return home window can cross midnight (ruling 2026-10-08).
  if earliest > latest and car_trip <> 'return_home' then
    raise exception using
      message = 'The earliest time must be before the latest time.',
      hint    = 'INVALID_WINDOW';
  end if;

  if (home = 'other' and clean_text(home_other) is null)
     or ('other' = any (dropoff) and clean_text(dropoff_other) is null) then
    raise exception using
      message = 'Please type the area.',
      hint    = 'OTHER_AREA_REQUIRED';
  end if;

  if exists (select 1 from jsonb_array_elements(clean_stops(stops)) as s (stop)
             where clean_text(stop ->> 'description') is null) then
    raise exception using
      message = 'Please describe each stop.',
      hint    = 'NAME_REQUIRED';
  end if;
end;
$$;

-- Replaces a car's stops and drop-off areas with the submitted ones.
-- The composite foreign keys keep stops on To the hotel cars and
-- drop-off areas on Return home cars.
create function save_car_route(target_car_id uuid, stops jsonb, dropoff area[], dropoff_other text)
returns void
language sql set search_path = public as $$
  delete from car_stop where car_id = target_car_id;

  insert into car_stop (car_id, position, description, purpose)
  select target_car_id, pos - 1, clean_text(stop ->> 'description'),
         clean_text(stop ->> 'purpose')::stop_purpose
  from jsonb_array_elements(clean_stops(stops)) with ordinality as t (stop, pos);

  delete from car_dropoff_area where car_id = target_car_id;

  insert into car_dropoff_area (car_id, area, area_other)
  select distinct target_car_id, a,
         case when a = 'other' then clean_text(dropoff_other) end
  from unnest(dropoff) as a;
$$;

revoke all on function
  lock_car(uuid), confirmed_passengers(uuid), cancel_passenger_requests_if_full(uuid),
  clean_stops(jsonb),
  check_car_fields(trip, int, time, time, area, text, int, int, jsonb, area[], text),
  save_car_route(uuid, jsonb, area[], text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. Cars (BR-13 to BR-19)
-- ---------------------------------------------------------------------

-- "I'm coming with my car." The UI sends the car form's context (trip)
-- and its visible fields; fields hidden for this trip arrive as their
-- defaults.
create function register_car(
  trip               trip,
  seats              int    default null,
  departure_earliest time   default null,
  departure_latest   time   default null,
  home_area          area   default null,
  home_area_other    text   default null,
  minutes_to_bride   int    default null,
  minutes_to_hotel   int    default null,
  stops              jsonb  default '[]',
  dropoff_areas      area[] default '{}',
  dropoff_area_other text   default null,
  trunk_percent      int    default null,
  notes              text   default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  me     uuid := require_member();
  new_id uuid;
begin
  if exists (select 1 from car c
             where c.owner_id = me and c.trip = register_car.trip and c.withdrawn_at is null) then
    raise exception using
      message = 'You already have a car on this trip.',
      hint    = 'ALREADY_HAS_CAR';
  end if;

  perform check_car_fields(
    register_car.trip, register_car.seats,
    register_car.departure_earliest, register_car.departure_latest,
    register_car.home_area, register_car.home_area_other,
    register_car.minutes_to_bride, register_car.minutes_to_hotel,
    register_car.stops, register_car.dropoff_areas, register_car.dropoff_area_other);

  insert into car (owner_id, trip, seats, departure_earliest, departure_latest,
                   home_area, home_area_other, minutes_to_bride, minutes_to_hotel,
                   trunk_percent, notes)
  values (
    me, register_car.trip, register_car.seats,
    register_car.departure_earliest, register_car.departure_latest,
    register_car.home_area,
    -- The "other" text is kept only for the Other area.
    case when register_car.home_area = 'other' then clean_text(register_car.home_area_other) end,
    register_car.minutes_to_bride, register_car.minutes_to_hotel,
    register_car.trunk_percent,
    clean_text(register_car.notes)
  )
  returning id into new_id;

  perform save_car_route(new_id, register_car.stops,
                         register_car.dropoff_areas, register_car.dropoff_area_other);
end;
$$;

-- Owner only. The trip can't change. The form sends every visible
-- field, so the submitted values, stops, and drop-off areas replace the
-- stored ones.
create function update_car(
  car_id             uuid,
  seats              int    default null,
  departure_earliest time   default null,
  departure_latest   time   default null,
  home_area          area   default null,
  home_area_other    text   default null,
  minutes_to_bride   int    default null,
  minutes_to_hotel   int    default null,
  stops              jsonb  default '[]',
  dropoff_areas      area[] default '{}',
  dropoff_area_other text   default null,
  trunk_percent      int    default null,
  notes              text   default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  me        uuid := require_member();
  target    car%rowtype;
  confirmed int;
begin
  target := lock_car(update_car.car_id);
  if target.owner_id <> me then
    raise exception using
      message = 'You can''t change this.',
      hint    = 'NOT_ALLOWED';
  end if;
  if target.withdrawn_at is not null then
    raise exception using
      message = 'This car is no longer available.',
      hint    = 'CAR_WITHDRAWN';
  end if;

  perform check_car_fields(
    target.trip, update_car.seats,
    update_car.departure_earliest, update_car.departure_latest,
    update_car.home_area, update_car.home_area_other,
    update_car.minutes_to_bride, update_car.minutes_to_hotel,
    update_car.stops, update_car.dropoff_areas, update_car.dropoff_area_other);

  confirmed := confirmed_passengers(target.id);
  if update_car.seats < confirmed then
    raise exception using
      message = format('You already have %s confirmed %s.',
                       confirmed, case when confirmed = 1 then 'passenger' else 'passengers' end),
      hint    = 'SEATS_BELOW_CONFIRMED';
  end if;

  update car set
    seats              = update_car.seats,
    departure_earliest = update_car.departure_earliest,
    departure_latest   = update_car.departure_latest,
    home_area          = update_car.home_area,
    home_area_other    = case when update_car.home_area = 'other'
                              then clean_text(update_car.home_area_other) end,
    minutes_to_bride   = update_car.minutes_to_bride,
    minutes_to_hotel   = update_car.minutes_to_hotel,
    trunk_percent      = update_car.trunk_percent,
    notes              = clean_text(update_car.notes)
  where id = target.id;

  perform save_car_route(target.id, update_car.stops,
                         update_car.dropoff_areas, update_car.dropoff_area_other);

  -- Fewer seats can fill the car (ruling 2026-10-07).
  perform cancel_passenger_requests_if_full(target.id);
end;
$$;

-- BR-19: withdrawing cancels every pending and confirmed request for the
-- car, passengers and cargo alike. The affected members see it in "Needs
-- your attention". The member can register a car on this trip again.
create function withdraw_car(car_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me     uuid := require_member();
  target car%rowtype;
begin
  target := lock_car(withdraw_car.car_id);
  if target.owner_id <> me then
    raise exception using
      message = 'You can''t change this.',
      hint    = 'NOT_ALLOWED';
  end if;
  if target.withdrawn_at is not null then
    raise exception using
      message = 'This car is no longer available.',
      hint    = 'CAR_WITHDRAWN';
  end if;

  update car set withdrawn_at = now() where id = target.id;

  update request r
  set state = 'cancelled', cancel_reason = 'car_withdrawn'
  where r.car_id = target.id and r.state in ('pending', 'confirmed');
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Access
-- ---------------------------------------------------------------------

revoke all on function
  register_car(trip, int, time, time, area, text, int, int, jsonb, area[], text, int, text),
  update_car(uuid, int, time, time, area, text, int, int, jsonb, area[], text, int, text),
  withdraw_car(uuid)
  from public, anon;

grant execute on function
  register_car(trip, int, time, time, area, text, int, int, jsonb, area[], text, int, text),
  update_car(uuid, int, time, time, area, text, int, int, jsonb, area[], text, int, text),
  withdraw_car(uuid)
  to authenticated;
