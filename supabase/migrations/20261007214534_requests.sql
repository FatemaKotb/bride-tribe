-- =====================================================================
-- Request functions (contract Section 4, BR-05, BR-20 to BR-25)
--
-- Rulings that fill gaps in the design documents:
-- - Seat limits apply to passenger requests only: cargo can be sent to
--   a full car (2026-10-07; the contract's reading of BR-23).
-- - An unknown request id raises NOT_FOUND (2026-10-08).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Internal helpers (not callable through the API)
-- ---------------------------------------------------------------------

-- The request, locked until the calling function finishes, or NOT_FOUND
-- (declined cargo requests are deleted with their item). The car is
-- locked first, in the same order as the car functions, so seat counts
-- can't race.
create function lock_request(target_id uuid) returns request
language plpgsql set search_path = public as $$
declare
  ride_id     uuid;
  found_request request%rowtype;
begin
  select car_id into ride_id from request where id = target_id;
  if not found then
    raise exception using
      message = 'This request no longer exists.',
      hint    = 'NOT_FOUND';
  end if;
  perform 1 from car where id = ride_id for update;
  select * into found_request from request where id = target_id for update;
  return found_request;
end;
$$;

-- The member a request is about: the passenger, or the cargo's owner
-- (BR-24). Null for a cancelled request whose item was deleted.
create function subject_owner(target request) returns uuid
language sql stable set search_path = public as $$
  select case when target.kind = 'passenger' then target.passenger_id
              else (select cargo_owner(i) from item i where i.id = target.item_id) end;
$$;

-- BR-20: an Ask is answered by the car owner, an Offer by the passenger
-- or the cargo's owner.
create function request_responder(target request) returns uuid
language sql stable set search_path = public as $$
  select case when target.direction = 'ask'
              then (select c.owner_id from car c where c.id = target.car_id)
              else subject_owner(target) end;
$$;

-- BR-05, BR-10: private items are visible only to their owner, and a
-- container is shared once it holds a shared item.
create function can_see_item(target item, me uuid) returns boolean
language sql stable set search_path = public as $$
  select target.owner_id = me
      or (target.kind = 'item' and target.visibility = 'shared')
      or (target.kind = 'container' and exists (
            select 1 from item inside
            where inside.parent_id = target.id and inside.visibility = 'shared'));
$$;

-- BR-23: passengers need a free seat.
create function check_free_seat(ride car, me uuid) returns void
language plpgsql set search_path = public as $$
declare
  msg text;
begin
  if confirmed_passengers(ride.id) >= ride.seats then
    if ride.owner_id = me then
      msg := 'Your car has no free seats.';
    else
      msg := format('%s''s car has no free seats.',
                    (select m.name from member m where m.id = ride.owner_id));
    end if;
    raise exception using message = msg, hint = 'CAR_FULL';
  end if;
end;
$$;

-- BR-22: a passenger or an item rides in one car per trip.
create function check_not_confirmed_on_trip(
  subject_kind request_kind, on_trip trip, passenger uuid, cargo_item uuid, me uuid
) returns void
language plpgsql set search_path = public as $$
declare
  msg text;
begin
  if subject_kind = 'passenger' then
    if exists (select 1 from request r
               where r.kind = 'passenger' and r.trip = on_trip
                 and r.state = 'confirmed' and r.passenger_id = passenger) then
      if passenger = me then
        msg := 'You already have a ride on this trip.';
      else
        msg := format('%s already has a ride on this trip.',
                      (select m.name from member m where m.id = passenger));
      end if;
      raise exception using message = msg, hint = 'ALREADY_CONFIRMED_ON_TRIP';
    end if;
  elsif exists (select 1 from request r
                where r.kind = 'cargo' and r.trip = on_trip
                  and r.state = 'confirmed' and r.item_id = cargo_item) then
    msg := format('A car is already taking %s on this trip.',
                  (select i.name from item i where i.id = cargo_item));
    raise exception using message = msg, hint = 'ALREADY_CONFIRMED_ON_TRIP';
  end if;
end;
$$;

-- BR-22: once confirmed, the same passenger's or item's other pending
-- requests on that trip are cancelled (auto).
create function cancel_other_pending_on_trip(confirmed request) returns void
language sql set search_path = public as $$
  update request r
  set state = 'cancelled', cancel_reason = 'auto'
  where r.trip = confirmed.trip and r.kind = confirmed.kind
    and r.state = 'pending' and r.id <> confirmed.id
    and (r.passenger_id = confirmed.passenger_id or r.item_id = confirmed.item_id);
$$;

revoke all on function
  lock_request(uuid), subject_owner(request), request_responder(request),
  can_see_item(item, uuid), check_free_seat(car, uuid),
  check_not_confirmed_on_trip(request_kind, trip, uuid, uuid, uuid),
  cancel_other_pending_on_trip(request)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. Requests (BR-20 to BR-25)
-- ---------------------------------------------------------------------

-- The contract's "subject" is passenger_id or item_id, and its "pickup"
-- is pickup_type, pickup_address, and ready_at, so the forms' fields
-- map straight onto the arguments. Fields that don't apply to the kind
-- of request are ignored.
create function send_request(
  car_id         uuid,
  kind           request_kind,
  direction      request_direction,
  passenger_id   uuid        default null,
  item_id        uuid        default null,
  pickup_type    pickup_type default null,
  pickup_address text        default null,
  ready_at       time        default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  me       uuid := require_member();
  ride     car%rowtype;
  cargo    item%rowtype;
  owner_of uuid;  -- the passenger, or the cargo's owner
begin
  ride := lock_car(send_request.car_id);
  if ride.withdrawn_at is not null then
    raise exception using
      message = 'This car is no longer available.',
      hint    = 'CAR_WITHDRAWN';
  end if;

  -- BR-20: an Ask goes to someone else's car, an Offer comes from mine.
  if send_request.direction = 'ask' and ride.owner_id = me then
    raise exception using
      message = 'That''s your own car.',
      hint    = 'OWN_CAR';
  end if;
  if send_request.direction = 'offer' and ride.owner_id <> me then
    raise exception using
      message = 'You can''t change this.',
      hint    = 'NOT_ALLOWED';
  end if;

  if send_request.kind = 'passenger' then
    if not exists (select 1 from member m where m.id = send_request.passenger_id) then
      raise exception using
        message = 'We couldn''t find that name.',
        hint    = 'UNKNOWN_MEMBER';
    end if;
    owner_of := send_request.passenger_id;
  else
    cargo := lock_item(send_request.item_id);
    -- BR-24: unclaimed items can't be cargo.
    if cargo.type = 'claimable' and cargo.claimed_by_id is null then
      raise exception using
        message = 'Someone needs to claim this item first.',
        hint    = 'UNCLAIMED_CARGO';
    end if;
    owner_of := cargo_owner(cargo);
  end if;

  -- An Ask is about me or my cargo; an Offer is about someone else.
  if send_request.direction = 'ask' and owner_of <> me then
    if send_request.kind = 'cargo' then
      raise exception using
        message = 'You can only send your own items.',
        hint    = 'NOT_YOUR_CARGO';
    end if;
    raise exception using
      message = 'You can''t change this.',
      hint    = 'NOT_ALLOWED';
  end if;
  if send_request.direction = 'offer' and owner_of = me then
    raise exception using
      message = 'That''s your own car.',
      hint    = 'OWN_CAR';
  end if;

  if send_request.kind = 'cargo' then
    -- BR-05: a car owner can offer to carry only what she can see.
    if send_request.direction = 'offer' and not can_see_item(cargo, me) then
      raise exception using
        message = 'You can''t change this.',
        hint    = 'NOT_ALLOWED';
    end if;
    -- BR-11: an item in a bag travels with the bag.
    if cargo.parent_id is not null then
      raise exception using
        message = 'This item travels with its bag. Send the bag instead.',
        hint    = 'CARGO_IN_CONTAINER';
    end if;
    -- BR-24: the bride's home, the vendor's address when there is one,
    -- or a typed address.
    if send_request.pickup_type is null
       or (send_request.pickup_type = 'custom' and clean_text(send_request.pickup_address) is null)
       or (send_request.pickup_type = 'vendor_address' and not exists (
             select 1 from vendor_details v
             where v.item_id = cargo.id and clean_text(v.address) is not null)) then
      raise exception using
        message = 'Please choose a valid pickup location.',
        hint    = 'PICKUP_INVALID';
    end if;
  else
    -- Seats limit passengers only (ruling 2026-10-07).
    perform check_free_seat(ride, me);
  end if;

  perform check_not_confirmed_on_trip(send_request.kind, ride.trip,
                                      send_request.passenger_id, cargo.id, me);

  if exists (select 1 from request r
             where r.car_id = ride.id and r.state = 'pending' and r.kind = send_request.kind
               and (r.passenger_id = send_request.passenger_id or r.item_id = cargo.id)) then
    raise exception using
      message = 'There''s already a pending request for this.',
      hint    = 'DUPLICATE_REQUEST';
  end if;

  insert into request (car_id, trip, direction, kind, created_by_id, passenger_id, item_id,
                       pickup_type, pickup_address, ready_at)
  values (
    ride.id, ride.trip, send_request.direction, send_request.kind, me,
    case when send_request.kind = 'passenger' then send_request.passenger_id end,
    cargo.id,
    case when send_request.kind = 'cargo' then send_request.pickup_type end,
    case when send_request.kind = 'cargo' and send_request.pickup_type = 'custom'
         then clean_text(send_request.pickup_address) end,
    case when send_request.kind = 'cargo' then send_request.ready_at end
  );
end;
$$;

-- Only the responder, only while pending (BR-21). Accepting re-checks
-- the seat and one-car-per-trip rules, because things may have changed
-- since the request was sent.
create function respond_to_request(request_id uuid, accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  me     uuid := require_member();
  target request%rowtype;
  ride   car%rowtype;
begin
  target := lock_request(respond_to_request.request_id);
  if request_responder(target) is distinct from me then
    raise exception using
      message = 'You can''t change this.',
      hint    = 'NOT_ALLOWED';
  end if;
  if target.state <> 'pending' then
    raise exception using
      message = 'This request has already been answered.',
      hint    = 'NOT_PENDING';
  end if;
  if respond_to_request.accept is null then
    raise exception 'accept must be true or false';
  end if;

  if not respond_to_request.accept then
    update request set state = 'declined' where id = target.id;
    return;
  end if;

  select * into ride from car where id = target.car_id;
  if target.kind = 'passenger' then
    perform check_free_seat(ride, me);
  end if;
  perform check_not_confirmed_on_trip(target.kind, target.trip,
                                      target.passenger_id, target.item_id, me);

  update request set state = 'confirmed' where id = target.id;

  perform cancel_other_pending_on_trip(target);
  if target.kind = 'passenger' then
    perform cancel_passenger_requests_if_full(target.car_id);
  end if;
end;
$$;

-- Only the sender, only while pending (BR-21).
create function cancel_request(request_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me     uuid := require_member();
  target request%rowtype;
begin
  target := lock_request(cancel_request.request_id);
  if target.created_by_id <> me then
    raise exception using
      message = 'You can''t change this.',
      hint    = 'NOT_ALLOWED';
  end if;
  if target.state <> 'pending' then
    raise exception using
      message = 'This request has already been answered.',
      hint    = 'NOT_PENDING';
  end if;

  update request set state = 'cancelled', cancel_reason = 'by_sender' where id = target.id;
end;
$$;

-- BR-21: after confirmation, the passenger or the cargo's owner can
-- withdraw, which frees the seat. The car owner can't remove anyone;
-- she sees the change in "Needs your attention".
create function leave_car(request_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me     uuid := require_member();
  target request%rowtype;
begin
  target := lock_request(leave_car.request_id);
  if subject_owner(target) is distinct from me then
    raise exception using
      message = 'You can''t change this.',
      hint    = 'NOT_ALLOWED';
  end if;
  if target.state <> 'confirmed' then
    raise exception using
      message = 'This ride isn''t confirmed.',
      hint    = 'NOT_CONFIRMED';
  end if;

  update request set state = 'cancelled', cancel_reason = 'left_car' where id = target.id;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Access
-- ---------------------------------------------------------------------

revoke all on function
  send_request(uuid, request_kind, request_direction, uuid, uuid, pickup_type, text, time),
  respond_to_request(uuid, boolean),
  cancel_request(uuid),
  leave_car(uuid)
  from public, anon;

grant execute on function
  send_request(uuid, request_kind, request_direction, uuid, uuid, pickup_type, text, time),
  respond_to_request(uuid, boolean),
  cancel_request(uuid),
  leave_car(uuid)
  to authenticated;
