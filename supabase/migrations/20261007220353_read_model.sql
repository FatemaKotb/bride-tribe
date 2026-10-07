-- =====================================================================
-- Read endpoints and forms (contract Sections 1, 3, and 5; BR-01,
-- BR-05 to BR-11a, BR-18, BR-25 to BR-28, BR-32, BR-34)
--
-- Rulings that fill gaps in the design documents:
-- - option_label holds every label for a value: badges, dropdowns, and
--   filter choices. Action labels, field labels, titles, and messages
--   are written in these functions, like error messages (2026-10-08).
-- - A request records who cancelled it and when. "Needs your attention"
--   shows a cancellation to the other party only (2026-10-08).
-- - Time fields ask for 24-hour time, trunk space is required, and a
--   Return home window can cross midnight (2026-10-08).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Who cancelled a request, and when
-- ---------------------------------------------------------------------

alter table request
  add column cancelled_at    timestamptz,
  add column cancelled_by_id uuid references member (id),
  add constraint request_cancelled_at check ((state = 'cancelled') = (cancelled_at is not null));

-- Stamps each cancellation with its time and the signed-in member whose
-- action caused it, whichever function did the cancelling.
create function stamp_cancellation() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.state = 'cancelled' then
    if tg_op = 'INSERT' or old.state <> 'cancelled' then
      new.cancelled_at    := now();
      new.cancelled_by_id := current_member_id();
    end if;
  else
    new.cancelled_at    := null;
    new.cancelled_by_id := null;
  end if;
  return new;
end;
$$;

create trigger request_stamp_cancellation before insert or update on request
  for each row execute function stamp_cancellation();

-- ---------------------------------------------------------------------
-- 2. Labels for the remaining values: request kinds, cancel reasons,
--    filter choices, and badges
-- ---------------------------------------------------------------------

insert into option_label (option_set, value, label, emoji, sort_order) values
  ('request_kind', 'passenger', 'Passenger', null, 1),
  ('request_kind', 'cargo',     'Cargo',     null, 2),

  ('cancel_reason', 'by_sender',     'Cancelled by sender',     null, 1),
  ('cancel_reason', 'left_car',      'Left the car',            null, 2),
  ('cancel_reason', 'car_withdrawn', 'Car withdrawn',           null, 3),
  ('cancel_reason', 'auto',          'Cancelled automatically', null, 4),

  ('filter_owner', 'mine',   'Mine',   null, 1),
  ('filter_owner', 'shared', 'Shared', null, 2),

  ('filter_packed', 'packed',     'Packed',     null, 1),
  ('filter_packed', 'not_packed', 'Not packed', null, 2),

  ('filter_vendor', 'has_vendor', 'Has vendor details', null, 1),

  ('filter_container', 'none', 'Not in a bag', null, 1),

  ('filter_direction', 'sent',     'Sent',     null, 1),
  ('filter_direction', 'received', 'Received', null, 2),

  ('badge', 'full',         'Full',         null, 1),
  ('badge', 'trunk',        'Trunk',        null, 2),
  ('badge', 'unclaimed',    'Unclaimed',    null, 3),
  ('badge', 'claimed_by',   'Claimed by',   null, 4),
  ('badge', 'on_your_list', 'On your list', null, 5),
  ('badge', 'withdrawn',    'Withdrawn',    null, 6);

-- ---------------------------------------------------------------------
-- 3. Display helpers (Africa/Cairo times are stored as local times of
--    day, so formatting needs no time zone conversion)
-- ---------------------------------------------------------------------

create function label_of(label_set text, label_value text) returns text
language sql stable set search_path = public as $$
  select l.label from option_label l where l.option_set = $1 and l.value = $2;
$$;

create function emoji_of(label_set text, label_value text) returns text
language sql stable set search_path = public as $$
  select l.emoji from option_label l where l.option_set = $1 and l.value = $2;
$$;

-- [{value, label, emoji}] for a dropdown or a filter, in display order.
create function label_options(label_set text) returns jsonb
language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('value', l.value, 'label', l.label, 'emoji', l.emoji)
                            order by l.sort_order), '[]')
  from option_label l where l.option_set = $1;
$$;

-- "9:00 am"
create function fmt_time(t time) returns text
language sql immutable set search_path = public as $$
  select to_char(date '2000-01-01' + t, 'FMHH12:MI am');
$$;

-- "HH:MM", the form value for a time of day.
create function hhmm(t time) returns text
language sql immutable set search_path = public as $$
  select to_char(date '2000-01-01' + t, 'HH24:MI');
$$;

-- "9:00 am–10:30 am", or one time when both ends match.
create function fmt_window(earliest time, latest time) returns text
language sql immutable set search_path = public as $$
  select case when earliest = latest then fmt_time(earliest)
              else fmt_time(earliest) || '–' || fmt_time(latest) end;
$$;

-- "just now", "12 min ago", "3 hr ago", "2 days ago"
create function fmt_ago(at timestamptz) returns text
language sql stable set search_path = public as $$
  select case
    when minutes < 1    then 'just now'
    when minutes < 60   then minutes || ' min ago'
    when minutes < 1440 then (minutes / 60) || ' hr ago'
    when minutes < 2880 then '1 day ago'
    else (minutes / 1440) || ' days ago'
  end
  from (select floor(extract(epoch from now() - at) / 60)::int as minutes) elapsed;
$$;

-- "2,000 EGP"
create function fmt_egp(amount numeric) returns text
language sql immutable set search_path = public as $$
  select case when amount = trunc(amount) then to_char(amount, 'FM999,999,999,990')
              else to_char(amount, 'FM999,999,999,990.00') end || ' EGP';
$$;

-- Joins the non-empty parts with " · ".
create function join_parts(parts text[]) returns text
language sql immutable set search_path = public as $$
  select nullif(array_to_string(array(select p from unnest(parts) p where p <> ''), ' · '), '');
$$;

create function member_name(member_id uuid) returns text
language sql stable set search_path = public as $$
  select m.name from member m where m.id = $1;
$$;

-- BR-01: "Sara (Bridesmaid)"
create function member_title(member_id uuid) returns text
language sql stable set search_path = public as $$
  select m.name || ' (' || label_of('role', m.role::text) || ')' from member m where m.id = $1;
$$;

-- ---------------------------------------------------------------------
-- 4. Building blocks: actions, rows, badges, fields (contract Section 1)
-- ---------------------------------------------------------------------

create function make_action(
  action_id text, action_label text, action_style text,
  call_function text, call_args jsonb, confirm_text text default null
) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_object(
    'id', action_id, 'label', action_label, 'style', action_style, 'confirm', confirm_text,
    'call', jsonb_build_object('function', call_function, 'args', call_args),
    'form', null);
$$;

create function form_action(
  action_id text, action_label text, action_style text, form_name text, form_context jsonb
) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_object(
    'id', action_id, 'label', action_label, 'style', action_style, 'confirm', null,
    'call', null,
    'form', jsonb_build_object('name', form_name, 'context', form_context));
$$;

create function make_badge(badge_label text, tone text) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_object('label', badge_label, 'tone', tone);
$$;

create function make_row(
  row_id text, emoji text, title text, subtitle text, badges jsonb,
  open_detail text, open_id uuid, actions jsonb
) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_object(
    'id', row_id, 'emoji', emoji, 'title', title, 'subtitle', subtitle,
    'badges', coalesce(badges, '[]'),
    'open', case when open_detail is null then null
                 else jsonb_build_object('detail', open_detail, 'id', open_id) end,
    'actions', coalesce(actions, '[]'));
$$;

-- {label, value} for a detail section, or null when there's no value.
create function make_pair(pair_label text, pair_value text) returns jsonb
language sql immutable set search_path = public as $$
  select case when nullif(pair_value, '') is null then null
              else jsonb_build_object('label', pair_label, 'value', pair_value) end;
$$;

-- The pairs that have a value, as a JSON array.
create function pairs(items jsonb[]) returns jsonb
language sql immutable set search_path = public as $$
  select coalesce(jsonb_agg(p), '[]') from unnest(items) p where p is not null;
$$;

create function make_filter(filter_key text, filter_label text, options jsonb, selected text)
returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_object(
    'key', filter_key, 'label', filter_label, 'multi', false, 'options', options,
    'selected', case when selected is null then '[]'::jsonb else jsonb_build_array(selected) end);
$$;

-- A filter's chosen value, from {"key": ["value"]} or {"key": "value"}.
create function filter_value(filters jsonb, filter_key text) returns text
language sql immutable set search_path = public as $$
  select case jsonb_typeof(filters -> filter_key)
    when 'array'  then filters -> filter_key ->> 0
    when 'string' then filters ->> filter_key
  end;
$$;

create function make_field(
  field_key text, field_label text, field_type text, is_required boolean default false,
  options jsonb default null, hint text default null, default_value jsonb default null,
  current_value jsonb default null, visible_if jsonb default null, nested jsonb default null
) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_object(
    'key', field_key, 'label', field_label, 'type', field_type, 'required', is_required,
    'options', options, 'hint', hint, 'default', default_value, 'value', current_value,
    'visible_if', visible_if, 'fields', nested);
$$;

-- A field is visible when another field equals this value. For a
-- multiselect, "equals" means "includes". An array of values means "any
-- of these".
create function shown_if(field_key text, field_value jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_object('field', field_key, 'equals', field_value);
$$;

create function make_form(
  form_name text, form_title text, form_context jsonb, fields jsonb,
  submit_function text, submit_label text
) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_object(
    'name', form_name, 'title', form_title, 'context', form_context, 'fields', fields,
    'submit', jsonb_build_object('function', submit_function, 'label', submit_label));
$$;

-- ---------------------------------------------------------------------
-- 5. Items: rows and the actions each member may use (contract
--    Section 3, list_items row actions)
-- ---------------------------------------------------------------------

-- BR-10: a container is shared once it holds a shared item.
create function item_visibility_of(target item) returns item_visibility
language sql stable set search_path = public as $$
  select coalesce(target.visibility,
    case when exists (select 1 from item inside
                      where inside.parent_id = target.id and inside.visibility = 'shared')
         then 'shared' else 'private' end::item_visibility);
$$;

-- BR-08: "Claimed by Sara" or "Unclaimed".
create function claim_badge(target item) returns jsonb
language sql stable set search_path = public as $$
  select case when target.claimed_by_id is null
    then make_badge(label_of('badge', 'unclaimed'), 'warning')
    else make_badge(label_of('badge', 'claimed_by') || ' ' || member_name(target.claimed_by_id), 'success')
  end;
$$;

-- The row actions the member may use right now. Edit and Delete are the
-- owner's (ruling 2026-10-07); packing and bags are the cargo owner's
-- (ruling 2026-10-08).
create function item_actions(target item, me uuid) returns jsonb
language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(a.action order by a.ord), '[]')
  from (
    select 1, make_action('claim', 'Claim', 'primary', 'claim_item',
                          jsonb_build_object('item_id', target.id))
    where target.type = 'claimable' and target.claimed_by_id is null
    union all
    select 2, make_action('release', 'Release', 'secondary', 'release_claim',
                          jsonb_build_object('item_id', target.id),
                          format('Release your claim on %s?', target.name))
    where target.type = 'claimable' and target.claimed_by_id = me
    union all
    select 3, make_action(case when target.is_packed then 'unpack' else 'pack' end,
                          case when target.is_packed then 'Mark unpacked' else 'Mark packed' end,
                          'secondary', 'set_packed',
                          jsonb_build_object('item_id', target.id, 'packed', not target.is_packed))
    where cargo_owner(target) = me
    union all
    select 4, form_action('move_to_bag', 'Move to bag', 'secondary', 'move_to_container',
                          jsonb_build_object('item_id', target.id))
    where target.kind = 'item' and target.parent_id is null and cargo_owner(target) = me
      and exists (select 1 from item bag where bag.kind = 'container' and bag.owner_id = me)
    union all
    select 5, make_action('remove_from_bag', 'Remove from bag', 'secondary', 'move_to_container',
                          jsonb_build_object('item_id', target.id, 'container_id', null))
    where target.parent_id is not null and cargo_owner(target) = me
    union all
    select 6, form_action('edit', 'Edit', 'secondary',
                          case when target.kind = 'container' then 'container' else 'item' end,
                          jsonb_build_object('item_id', target.id))
    where target.owner_id = me
    union all
    select 7, make_action('delete', 'Delete', 'danger', 'delete_item',
                          jsonb_build_object('item_id', target.id),
                          format('Delete %s?', target.name))
    where target.owner_id = me
  ) as a (ord, action);
$$;

-- One item or container (BR-11a: "Perfume · In: Blue bag").
create function item_row(target item, me uuid) returns jsonb
language sql stable set search_path = public as $$
  select make_row(
    target.id::text,
    coalesce(target.emoji, emoji_of('item_kind', target.kind::text)),
    target.name,
    join_parts(array[
      case when target.kind = 'container' then
        (select case count(*) when 0 then 'Empty' when 1 then '1 item' else count(*) || ' items' end
         from item inside where inside.parent_id = target.id)
      end,
      'In: ' || (select bag.name from item bag where bag.id = target.parent_id),
      case when target.is_packed then label_of('filter_packed', 'packed') end
    ]),
    case when target.type = 'claimable' then jsonb_build_array(claim_badge(target))
         else jsonb_build_array(make_badge(label_of('item_visibility', item_visibility_of(target)::text), 'neutral'))
    end,
    'item', target.id,
    item_actions(target, me));
$$;

-- BR-07a: one row per group of shared personal copies, anchored to the
-- earliest one, so the group outlives its original (BR-07b).
create function group_row(anchor item, me uuid) returns jsonb
language sql stable set search_path = public as $$
  select make_row(
    anchor.id::text, anchor.emoji, anchor.name,
    (select string_agg(m.name, ', ' order by copied.created_at, copied.id)
     from item copied join member m on m.id = copied.owner_id
     where copied.group_id = anchor.group_id and copied.kind = 'item'
       and copied.type = 'personal' and copied.visibility = 'shared'),
    case when has_it then jsonb_build_array(make_badge(label_of('badge', 'on_your_list'), 'success'))
         else '[]'::jsonb end,
    'item', anchor.id,
    case when has_it then '[]'::jsonb
         else jsonb_build_array(form_action('add_to_list', 'Add to my list', 'primary', 'item',
                                            jsonb_build_object('copy_of', anchor.id))) end)
  from (select exists (select 1 from item mine
                       where mine.owner_id = me and mine.group_id = anchor.group_id) as has_it) s;
$$;

-- BR-32: "Photographer · 5:00 pm · 2,000 EGP", with the claimer.
create function vendor_row(target item, vendor vendor_details, me uuid) returns jsonb
language sql stable set search_path = public as $$
  select make_row(
    target.id::text, target.emoji, vendor.vendor_name,
    join_parts(array[vendor.service, fmt_time(vendor.expected_time), fmt_egp(vendor.amount_egp)]),
    jsonb_build_array(claim_badge(target)),
    'item', target.id,
    item_actions(target, me));
$$;

-- Tags in use on items I can see, as dropdown suggestions.
create function tag_options(me uuid) returns jsonb
language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('value', t.tag, 'label', t.tag) order by t.tag), '[]')
  from (select distinct unnest(i.tags) as tag from item i where can_see_item(i, me)) t;
$$;

-- ---------------------------------------------------------------------
-- 6. Cars and requests: rows and actions
-- ---------------------------------------------------------------------

create function car_title(ride car, me uuid) returns text
language sql stable set search_path = public as $$
  select case when ride.owner_id = me then 'Your car'
              else member_name(ride.owner_id) || '''s car' end;
$$;

-- The home area (To the hotel) or drop-off areas (Return home).
create function car_area(ride car) returns text
language sql stable set search_path = public as $$
  select case ride.trip
    when 'to_hotel' then
      case when ride.home_area = 'other' then ride.home_area_other
           else label_of('area', ride.home_area::text) end
    when 'return_home' then
      (select string_agg(case when d.area = 'other' then d.area_other
                              else label_of('area', d.area::text) end, ', ' order by d.area)
       from car_dropoff_area d where d.car_id = ride.id)
  end;
$$;

-- BR-18: "Maadi · leaves 9:00 am–10:30 am · 2 of 4 seats taken".
create function car_row(ride car, me uuid) returns jsonb
language sql stable set search_path = public as $$
  select make_row(
    ride.id::text, '🚗', car_title(ride, me),
    join_parts(array[
      case when ride.trip = 'return_home' then 'Drops off in ' || car_area(ride) else car_area(ride) end,
      'leaves ' || fmt_window(ride.departure_earliest, ride.departure_latest),
      taken || ' of ' || ride.seats || ' seats taken']),
    case when taken >= ride.seats
         then jsonb_build_array(make_badge(label_of('badge', 'full'), 'warning'))
         else '[]'::jsonb end
      || jsonb_build_array(make_badge(
           label_of('badge', 'trunk') || ' ' || label_of('trunk_percent', ride.trunk_percent::text), 'neutral')),
    'car', ride.id, '[]')
  from (select confirmed_passengers(ride.id) as taken) s;
$$;

-- The member is the sender, the car owner, or the passenger or cargo's
-- owner.
create function is_party(target request, me uuid) returns boolean
language sql stable set search_path = public as $$
  select target.created_by_id = me
      or exists (select 1 from car c where c.id = target.car_id and c.owner_id = me)
      or coalesce(subject_owner(target) = me, false);
$$;

-- "Pickup: Bride's home, ready 10:00 am"
create function pickup_text(target request) returns text
language sql stable set search_path = public as $$
  select 'Pickup: '
    || case when target.pickup_type = 'custom' then target.pickup_address
            else label_of('pickup_type', target.pickup_type::text) end
    || coalesce(', ready ' || fmt_time(target.ready_at), '');
$$;

-- A request from the member's point of view (BR-25): "Ride in Sara's
-- car", "To the hotel · You asked · Pending", with the actions she may
-- use on it.
create function request_row(target request, me uuid) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  ride       car%rowtype;
  cargo      item%rowtype;
  car_text   text;
  row_title  text;
  state_text text;
  row_emoji  text;
  sent_by    text;
  buttons    jsonb := '[]';
begin
  select * into ride from car c where c.id = target.car_id;
  car_text := case when ride.owner_id = me then 'your car'
                   else member_name(ride.owner_id) || '''s car' end;

  if target.kind = 'passenger' then
    row_emoji := emoji_of('trip', target.trip::text);
    row_title := case when target.passenger_id = me then 'Ride in ' || car_text
                      else member_name(target.passenger_id) || ' in ' || car_text end;
  else
    select * into cargo from item i where i.id = target.item_id;
    row_emoji := cargo.emoji;
    row_title := coalesce(cargo.name, 'A deleted item') || ' in ' || car_text;
  end if;

  sent_by := case when target.created_by_id = me then 'You'
                  else member_name(target.created_by_id) end
             || case when target.direction = 'ask' then ' asked' else ' offered' end;

  state_text := case when target.state = 'cancelled'
                     then label_of('cancel_reason', target.cancel_reason::text)
                     else label_of('request_state', target.state::text) end;

  if target.state = 'pending' and request_responder(target) = me then
    buttons := buttons || jsonb_build_array(
      make_action('accept', 'Accept', 'primary', 'respond_to_request',
                  jsonb_build_object('request_id', target.id, 'accept', true)),
      make_action('decline', 'Decline', 'secondary', 'respond_to_request',
                  jsonb_build_object('request_id', target.id, 'accept', false)));
  end if;

  if target.state = 'pending' and target.created_by_id = me then
    buttons := buttons || jsonb_build_array(
      make_action('cancel', 'Cancel request', 'secondary', 'cancel_request',
                  jsonb_build_object('request_id', target.id)));
  end if;

  if target.state = 'confirmed' and subject_owner(target) = me then
    if target.kind = 'passenger' then
      buttons := buttons || jsonb_build_array(
        make_action('leave', 'Leave this car', 'danger', 'leave_car',
                    jsonb_build_object('request_id', target.id), format('Leave %s?', car_text)));
    else
      buttons := buttons || jsonb_build_array(
        make_action('take_out', 'Take it out of this car', 'danger', 'leave_car',
                    jsonb_build_object('request_id', target.id),
                    format('Take %s out of %s?', cargo.name, car_text)));
    end if;
  end if;

  return make_row(
    target.id::text, row_emoji, row_title,
    join_parts(array[label_of('trip', target.trip::text), sent_by, state_text,
                     case when target.kind = 'cargo' then pickup_text(target) end]),
    '[]', 'car', target.car_id, buttons);
end;
$$;

-- Cargo the member could put in this car right now (contract Section 5:
-- claimed if claimable, not in a bag, not confirmed on this trip), and
-- with no pending request with this car. "Mine" is my own cargo; else
-- other members' cargo that I can see (BR-05).
create function eligible_cargo(ride car, me uuid, mine boolean) returns setof item
language sql stable set search_path = public as $$
  select i.* from item i
  where i.parent_id is null
    and cargo_owner(i) is not null
    and ((mine and cargo_owner(i) = me)
         or (not mine and cargo_owner(i) <> me and can_see_item(i, me)))
    and not exists (select 1 from request r
                    where r.kind = 'cargo' and r.item_id = i.id
                      and r.trip = ride.trip and r.state = 'confirmed')
    and not exists (select 1 from request r
                    where r.car_id = ride.id and r.item_id = i.id and r.state = 'pending')
  order by i.name;
$$;

-- Members the car owner can still offer a seat (contract Section 5).
create function eligible_passengers(ride car, me uuid) returns setof member
language sql stable set search_path = public as $$
  select m.* from member m
  where m.id <> me
    and not exists (select 1 from request r
                    where r.kind = 'passenger' and r.passenger_id = m.id
                      and r.trip = ride.trip and r.state = 'confirmed')
    and not exists (select 1 from request r
                    where r.car_id = ride.id and r.passenger_id = m.id and r.state = 'pending')
  order by m.name;
$$;

-- ---------------------------------------------------------------------
-- 7. Read endpoints (contract Section 3)
-- ---------------------------------------------------------------------

-- BR-26 to BR-28, BR-34. No side effects: refreshing never hides
-- anything.
create function get_home() returns json
language plpgsql stable security definer set search_path = public as $$
declare
  me        uuid := require_member();
  self      member%rowtype;
  waiting   jsonb;
  cancelled jsonb;
  board     jsonb;
begin
  select * into self from member m where m.id = me;

  -- Pending requests waiting for my answer.
  select coalesce(jsonb_agg(request_row(r, me) order by r.created_at desc, r.id), '[]')
  into waiting
  from request r
  where r.state = 'pending' and request_responder(r) = me;

  -- Cancellations since my last "Got it" that someone else caused.
  select coalesce(jsonb_agg(request_row(r, me) order by r.cancelled_at desc, r.id), '[]')
  into cancelled
  from request r
  where r.state = 'cancelled'
    and r.cancelled_at > self.attention_cleared_at
    and r.cancelled_by_id is distinct from me
    and is_party(r, me);

  if jsonb_array_length(cancelled) > 0 then
    cancelled := cancelled || jsonb_build_array(make_row(
      'got_it', null, null, null, '[]', null, null,
      jsonb_build_array(make_action('got_it', 'Got it', 'secondary', 'clear_attention', '{}'))));
  end if;

  select coalesce(jsonb_agg(make_row(
           m.id::text, emoji_of('status', m.status::text), member_title(m.id),
           join_parts(array[label_of('status', m.status::text), fmt_ago(m.status_updated_at)]),
           '[]', null, null, '[]')
         order by role_label.sort_order, m.name), '[]')
  into board
  from member m
  join option_label role_label on role_label.option_set = 'role' and role_label.value = m.role::text;

  return jsonb_build_object(
    'me', jsonb_build_object('name', self.name, 'role_label', label_of('role', self.role::text)),
    'my_status', jsonb_build_object(
      'value',   self.status,
      'label',   label_of('status', self.status::text),
      'updated', fmt_ago(self.status_updated_at),
      'options', label_options('status')),
    'attention', waiting || cancelled,
    'status_board', board)::json;
end;
$$;

-- BR-07a, BR-09a, BR-32. Filters arrive as {"key": ["value"]}.
create function list_items(filters jsonb default '{}') returns json
language plpgsql stable security definer set search_path = public as $$
declare
  me            uuid := require_member();
  owner_choice  text := filter_value(filters, 'owner');
  kind_choice   text := filter_value(filters, 'kind');
  type_choice   text := filter_value(filters, 'type');
  packed_choice text := filter_value(filters, 'packed');
  vendor_choice text := filter_value(filters, 'vendor');
  bag_choice    text := filter_value(filters, 'container');
  tag_choice    text := filter_value(filters, 'tag');
  row_list      jsonb;
  filter_list   jsonb;
  owner_filter  jsonb;
begin
  -- Unknown choices count as no choice.
  if owner_choice is null or owner_choice not in ('mine', 'shared') then owner_choice := 'mine'; end if;
  if kind_choice not in ('item', 'container') then kind_choice := null; end if;
  if type_choice not in ('personal', 'claimable') then type_choice := null; end if;
  if packed_choice not in ('packed', 'not_packed') then packed_choice := null; end if;
  if vendor_choice is distinct from 'has_vendor' then vendor_choice := null; end if;
  if bag_choice <> 'none' and not exists (
       select 1 from item bag
       where bag.id::text = bag_choice and bag.kind = 'container' and bag.owner_id = me) then
    bag_choice := null;
  end if;

  if vendor_choice is not null then
    -- BR-32: every vendor, whoever owns the item, by arrival time.
    select coalesce(jsonb_agg(vendor_row(i, v, me)
                              order by v.expected_time nulls last, v.vendor_name), '[]')
    into row_list
    from item i join vendor_details v on v.item_id = i.id
    where (packed_choice is null or i.is_packed = (packed_choice = 'packed'))
      and (tag_choice is null or tag_choice = any (i.tags));

    filter_list := jsonb_build_array(
      make_filter('vendor', 'Vendors', label_options('filter_vendor'), vendor_choice),
      make_filter('packed', 'Packed', label_options('filter_packed'), packed_choice),
      make_filter('tag', 'Tag', tag_options(me), tag_choice));

  elsif owner_choice = 'mine' then
    -- My items, items I claimed, and my bags, bags first.
    select coalesce(jsonb_agg(item_row(i, me) order by i.kind = 'container' desc, i.name, i.id), '[]')
    into row_list
    from item i
    where (i.owner_id = me or i.claimed_by_id = me)
      and (kind_choice is null or i.kind::text = kind_choice)
      and (type_choice is null or i.type::text = type_choice)
      and (packed_choice is null or i.is_packed = (packed_choice = 'packed'))
      and (bag_choice is null
           or (bag_choice = 'none' and i.kind = 'item' and i.parent_id is null)
           or i.parent_id::text = bag_choice)
      and (tag_choice is null or tag_choice = any (i.tags));

    filter_list := jsonb_build_array(
      make_filter('owner', 'Show', label_options('filter_owner'), owner_choice),
      make_filter('kind', 'Kind', label_options('item_kind'), kind_choice),
      make_filter('type', 'Type', label_options('item_type'), type_choice),
      make_filter('packed', 'Packed', label_options('filter_packed'), packed_choice),
      make_filter('vendor', 'Vendors', label_options('filter_vendor'), vendor_choice),
      make_filter('container', 'Bag',
        (select coalesce(jsonb_agg(jsonb_build_object('value', bag.id, 'label', bag.name,
                                                      'emoji', bag.emoji) order by bag.name), '[]')
         from item bag where bag.kind = 'container' and bag.owner_id = me)
        || label_options('filter_container'),
        bag_choice),
      make_filter('tag', 'Tag', tag_options(me), tag_choice));

  else
    -- One row per group of shared personal copies, and one per
    -- claimable item. Bags and packing are personal, so they're left out.
    select coalesce(jsonb_agg(shared.row_json order by shared.title, shared.row_id), '[]')
    into row_list
    from (
      select group_row(anchor, me) as row_json, anchor.name as title, anchor.id as row_id
      from item anchor
      where anchor.id in (select distinct on (i.group_id) i.id
                          from item i
                          where i.kind = 'item' and i.type = 'personal' and i.visibility = 'shared'
                          order by i.group_id, i.created_at, i.id)
        and (type_choice is null or type_choice = 'personal')
        and (kind_choice is null or kind_choice = 'item')
        and (tag_choice is null or tag_choice = any (anchor.tags))
      union all
      select item_row(i, me), i.name, i.id
      from item i
      where i.type = 'claimable'
        and (type_choice is null or type_choice = 'claimable')
        and (kind_choice is null or kind_choice = 'item')
        and (tag_choice is null or tag_choice = any (i.tags))
    ) shared;

    filter_list := jsonb_build_array(
      make_filter('owner', 'Show', label_options('filter_owner'), owner_choice),
      make_filter('type', 'Type', label_options('item_type'), type_choice),
      make_filter('vendor', 'Vendors', label_options('filter_vendor'), vendor_choice),
      make_filter('tag', 'Tag', tag_options(me), tag_choice));
  end if;

  return jsonb_build_object(
    'title', 'Items',
    'filters', filter_list,
    'rows', row_list,
    'empty_message', 'No items match these filters.',
    'actions', jsonb_build_array(
      form_action('add_item', 'Add item', 'primary', 'item', '{}'),
      form_action('add_bag', 'Add bag or box', 'secondary', 'container', '{}')))::json;
end;
$$;

create function get_item(item_id uuid) returns json
language plpgsql stable security definer set search_path = public as $$
declare
  me       uuid := require_member();
  target   item%rowtype;
  vendor   vendor_details%rowtype;
  sections jsonb;
  requests jsonb;
begin
  select * into target from item i where i.id = get_item.item_id;
  if not found or not can_see_item(target, me) then
    raise exception using
      message = 'This item was deleted.',
      hint    = 'NOT_FOUND';
  end if;

  if target.kind = 'item' then
    sections := jsonb_build_array(jsonb_build_object(
      'title', 'Details',
      'fields', pairs(array[
        make_pair('Description', target.description),
        make_pair('Quantity', target.quantity::text),
        make_pair('Tags', array_to_string(target.tags, ', ')),
        make_pair('Added by', member_name(target.owner_id)),
        make_pair('Visibility', label_of('item_visibility', target.visibility::text)),
        make_pair('Type', label_of('item_type', target.type::text)),
        make_pair('Claimed by', case when target.type = 'claimable'
                                     then coalesce(member_name(target.claimed_by_id),
                                                   label_of('badge', 'unclaimed')) end),
        make_pair('In', (select bag.name from item bag where bag.id = target.parent_id)),
        make_pair('Packing', label_of('filter_packed',
                                      case when target.is_packed then 'packed' else 'not_packed' end))
      ])));

    -- BR-29, BR-31: everyone can see vendor details.
    select * into vendor from vendor_details v where v.item_id = target.id;
    if found then
      sections := sections || jsonb_build_array(jsonb_build_object(
        'title', 'Vendor',
        'fields', pairs(array[
          make_pair('Vendor', vendor.vendor_name),
          make_pair('Service', vendor.service),
          make_pair('Phone', vendor.phone),
          make_pair('Address', vendor.address),
          make_pair('Time', fmt_time(vendor.expected_time)),
          make_pair('Amount', fmt_egp(vendor.amount_egp)),
          make_pair('Details', vendor.details)
        ])));
    end if;
  else
    sections := jsonb_build_array(
      jsonb_build_object(
        'title', 'Details',
        'fields', pairs(array[
          make_pair('Visibility', label_of('item_visibility', item_visibility_of(target)::text)),
          make_pair('Packing', label_of('filter_packed',
                                        case when target.is_packed then 'packed' else 'not_packed' end))
        ])),
      jsonb_build_object(
        'title', 'Contents',
        'rows', (select coalesce(jsonb_agg(item_row(inside, me) order by inside.name, inside.id), '[]')
                 from item inside
                 where inside.parent_id = target.id and can_see_item(inside, me)),
        'empty_message', 'Nothing in this bag yet.'));
  end if;

  -- Confirmed cargo is public (BR-18); the rest only to the people involved.
  select coalesce(jsonb_agg(request_row(r, me) order by r.updated_at desc, r.id), '[]')
  into requests
  from request r
  where r.item_id = target.id and (r.state = 'confirmed' or is_party(r, me));

  sections := sections || jsonb_build_array(jsonb_build_object(
    'title', 'Cargo requests', 'rows', requests, 'empty_message', 'No cargo requests yet.'));

  return jsonb_build_object(
    'emoji', coalesce(target.emoji, emoji_of('item_kind', target.kind::text)),
    'title', target.name,
    'subtitle', join_parts(array[
      case when target.kind = 'container' then label_of('item_kind', 'container')
           else label_of('item_type', target.type::text) end,
      label_of('item_visibility', item_visibility_of(target)::text)]),
    'sections', sections,
    'actions', item_actions(target, me))::json;
end;
$$;

-- BR-18. One row per active car on the trip, in departure order. A
-- Return home window can cross midnight, so it is ordered from noon.
create function list_cars(filters jsonb default '{}') returns json
language plpgsql stable security definer set search_path = public as $$
declare
  me          uuid := require_member();
  trip_choice text := filter_value(filters, 'trip');
  chosen_trip trip;
  row_list    jsonb;
begin
  if trip_choice is null or trip_choice not in (select unnest(enum_range(null::trip))::text) then
    trip_choice := 'to_hotel';
  end if;
  chosen_trip := trip_choice::trip;

  select coalesce(jsonb_agg(car_row(c, me)
           order by case when c.trip = 'return_home' then c.departure_earliest - interval '12 hours'
                         else c.departure_earliest end,
                    member_name(c.owner_id), c.id), '[]')
  into row_list
  from car c
  where c.trip = chosen_trip and c.withdrawn_at is null;

  return jsonb_build_object(
    'title', 'Cars',
    'filters', jsonb_build_array(make_filter('trip', 'Trip', label_options('trip'), trip_choice)),
    'rows', row_list,
    'empty_message', 'No cars on this trip yet.',
    'actions', case
      when exists (select 1 from car c
                   where c.owner_id = me and c.trip = chosen_trip and c.withdrawn_at is null)
      then '[]'::jsonb
      else jsonb_build_array(form_action('register_car', 'I''m coming with my car', 'primary', 'car',
                                         jsonb_build_object('trip', trip_choice)))
    end)::json;
end;
$$;

create function get_car(car_id uuid) returns json
language plpgsql stable security definer set search_path = public as $$
declare
  me         uuid := require_member();
  ride       car%rowtype;
  taken      int;
  is_mine    boolean;
  seat_free  boolean;
  sections   jsonb;
  buttons    jsonb := '[]';
begin
  select * into ride from car c where c.id = get_car.car_id;
  if not found then
    raise exception using
      message = 'This car no longer exists.',
      hint    = 'NOT_FOUND';
  end if;

  taken     := confirmed_passengers(ride.id);
  is_mine   := ride.owner_id = me;
  seat_free := taken < ride.seats;

  sections := jsonb_build_array(jsonb_build_object(
    'title', 'Details',
    'fields', pairs(array[
      make_pair(case when ride.trip = 'return_home' then 'Drops off in' else 'Home area' end,
                car_area(ride)),
      make_pair('Leaves', fmt_window(ride.departure_earliest, ride.departure_latest)),
      make_pair('To the bride''s house', ride.minutes_to_bride || ' min'),
      make_pair('To the hotel', ride.minutes_to_hotel || ' min'),
      make_pair('Seats', taken || ' of ' || ride.seats || ' taken'),
      make_pair('Trunk space', label_of('trunk_percent', ride.trunk_percent::text))
    ])));

  if ride.trip = 'to_hotel' then
    sections := sections || jsonb_build_array(jsonb_build_object(
      'title', 'Stops',
      'rows', (select coalesce(jsonb_agg(make_row(
                 s.id::text, null, s.description, label_of('stop_purpose', s.purpose::text),
                 '[]', null, null, '[]') order by s.position), '[]')
               from car_stop s where s.car_id = ride.id),
      'empty_message', 'No stops.'));
  end if;

  -- BR-16: notes are one-way and everyone can read them.
  if ride.notes is not null then
    sections := sections || jsonb_build_array(jsonb_build_object(
      'title', 'Notes', 'fields', pairs(array[make_pair('Notes', ride.notes)])));
  end if;

  -- BR-18: everyone sees who and what is confirmed.
  sections := sections || jsonb_build_array(
    jsonb_build_object(
      'title', 'Passengers',
      'rows', (select coalesce(jsonb_agg(make_row(
                 r.id::text, emoji_of('role', (select m.role::text from member m where m.id = r.passenger_id)),
                 member_title(r.passenger_id), null, '[]', null, null,
                 case when r.passenger_id = me then jsonb_build_array(make_action(
                   'leave', 'Leave this car', 'danger', 'leave_car',
                   jsonb_build_object('request_id', r.id), format('Leave %s?', car_title(ride, me))))
                 else '[]'::jsonb end)
               order by member_name(r.passenger_id)), '[]')
               from request r
               where r.car_id = ride.id and r.kind = 'passenger' and r.state = 'confirmed'),
      'empty_message', 'No passengers yet.'),
    jsonb_build_object(
      'title', 'Cargo',
      'rows', (select coalesce(jsonb_agg(make_row(
                 r.id::text, i.emoji, i.name,
                 join_parts(array[member_name(cargo_owner(i)), pickup_text(r)]),
                 '[]', 'item', i.id,
                 case when cargo_owner(i) = me then jsonb_build_array(make_action(
                   'take_out', 'Take it out of this car', 'danger', 'leave_car',
                   jsonb_build_object('request_id', r.id),
                   format('Take %s out of %s?', i.name, car_title(ride, me))))
                 else '[]'::jsonb end)
               order by i.name), '[]')
               from request r join item i on i.id = r.item_id
               where r.car_id = ride.id and r.kind = 'cargo' and r.state = 'confirmed'),
      'empty_message', 'No cargo yet.'));

  -- Actions (contract Section 3, get_car), only while the car is active.
  if ride.withdrawn_at is null then
    if not is_mine and seat_free
       and not exists (select 1 from request r
                       where r.kind = 'passenger' and r.passenger_id = me
                         and r.trip = ride.trip and r.state = 'confirmed')
       and not exists (select 1 from request r
                       where r.car_id = ride.id and r.passenger_id = me and r.state = 'pending') then
      buttons := buttons || jsonb_build_array(make_action(
        'ask_to_ride', 'Ask to ride', 'primary', 'send_request',
        jsonb_build_object('car_id', ride.id, 'kind', 'passenger', 'direction', 'ask',
                           'passenger_id', me)));
    end if;

    if not is_mine and exists (select 1 from eligible_cargo(ride, me, true)) then
      buttons := buttons || jsonb_build_array(form_action(
        'ask_to_carry', 'Ask to carry an item', 'secondary', 'cargo_request',
        jsonb_build_object('car_id', ride.id)));
    end if;

    if is_mine and seat_free and exists (select 1 from eligible_passengers(ride, me)) then
      buttons := buttons || jsonb_build_array(form_action(
        'offer_seat', 'Offer a seat', 'primary', 'passenger_offer',
        jsonb_build_object('car_id', ride.id)));
    end if;

    if is_mine and exists (select 1 from eligible_cargo(ride, me, false)) then
      buttons := buttons || jsonb_build_array(form_action(
        'offer_to_carry', 'Offer to carry an item', 'secondary', 'cargo_offer',
        jsonb_build_object('car_id', ride.id)));
    end if;

    if is_mine then
      buttons := buttons || jsonb_build_array(
        form_action('edit', 'Edit', 'secondary', 'car', jsonb_build_object('car_id', ride.id)),
        make_action('withdraw', 'Withdraw', 'danger', 'withdraw_car',
                    jsonb_build_object('car_id', ride.id),
                    'Withdraw your car from this trip? Everyone in it will see that it''s no longer coming.'));
    end if;
  end if;

  return jsonb_build_object(
    'emoji', '🚗',
    'title', car_title(ride, me),
    'subtitle', join_parts(array[
      label_of('trip', ride.trip::text),
      case when ride.withdrawn_at is not null then label_of('badge', 'withdrawn') end]),
    'sections', sections,
    'actions', buttons)::json;
end;
$$;

-- BR-25. A missing state filter means Pending; an empty one means all.
create function list_requests(filters jsonb default '{}') returns json
language plpgsql stable security definer set search_path = public as $$
declare
  me               uuid := require_member();
  direction_choice text := filter_value(filters, 'direction');
  state_choice     text := case when filters ? 'state' then filter_value(filters, 'state')
                                else 'pending' end;
  kind_choice      text := filter_value(filters, 'kind');
  row_list         jsonb;
begin
  if direction_choice not in ('sent', 'received') then direction_choice := null; end if;
  if state_choice not in (select unnest(enum_range(null::request_state))::text) then
    state_choice := null;
  end if;
  if kind_choice not in ('passenger', 'cargo') then kind_choice := null; end if;

  select coalesce(jsonb_agg(request_row(r, me) order by r.updated_at desc, r.id), '[]')
  into row_list
  from request r
  where is_party(r, me)
    and (direction_choice is null
         or (direction_choice = 'sent') = (r.created_by_id = me))
    and (state_choice is null or r.state::text = state_choice)
    and (kind_choice is null or r.kind::text = kind_choice);

  return jsonb_build_object(
    'title', 'Requests',
    'filters', jsonb_build_array(
      make_filter('direction', 'Direction', label_options('filter_direction'), direction_choice),
      make_filter('state', 'State', label_options('request_state'), state_choice),
      make_filter('kind', 'Kind', label_options('request_kind'), kind_choice)),
    'rows', row_list,
    'empty_message', 'No requests match these filters.',
    'actions', '[]'::jsonb)::json;
end;
$$;

-- ---------------------------------------------------------------------
-- 8. Forms (contract Section 5)
-- ---------------------------------------------------------------------

-- New item, edit ({item_id}, owner only), or "Add to my list"
-- ({copy_of}, pre-filled from the shared item).
create function item_form(context jsonb, me uuid) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  editing uuid := (context ->> 'item_id')::uuid;
  copying uuid := (context ->> 'copy_of')::uuid;
  base    item%rowtype;
  vendor  vendor_details%rowtype;
begin
  if editing is not null then
    select * into base from item i where i.id = editing;
    if not found then
      raise exception using message = 'This item was deleted.', hint = 'NOT_FOUND';
    end if;
    if base.owner_id <> me or base.kind <> 'item' then
      raise exception using message = 'You can''t change this.', hint = 'NOT_ALLOWED';
    end if;
    select * into vendor from vendor_details v where v.item_id = base.id;
  elsif copying is not null then
    select * into base from item i where i.id = copying;
    if not found then
      raise exception using message = 'This item was deleted.', hint = 'NOT_FOUND';
    end if;
    if base.type is distinct from 'personal' or base.visibility is distinct from 'shared' then
      raise exception using message = 'This item can''t be copied.', hint = 'COPY_NOT_ALLOWED';
    end if;
    if exists (select 1 from item mine where mine.owner_id = me and mine.group_id = base.group_id) then
      raise exception using message = 'This is already on your list.', hint = 'ALREADY_ON_YOUR_LIST';
    end if;
  end if;

  return make_form(
    'item',
    case when editing is not null then 'Edit item'
         when copying is not null then 'Add to my list'
         else 'Add item' end,
    case when editing is not null then jsonb_build_object('item_id', editing)
         when copying is not null then jsonb_build_object('copy_of', copying)
         else '{}'::jsonb end,
    jsonb_build_array(
      make_field('name', 'Name', 'text', true, current_value => to_jsonb(base.name)),
      make_field('emoji', 'Emoji', 'emoji', current_value => to_jsonb(base.emoji)),
      make_field('description', 'Description', 'textarea', current_value => to_jsonb(base.description)),
      make_field('quantity', 'Quantity', 'number', current_value => to_jsonb(base.quantity)),
      make_field('tags', 'Tags', 'tags', options => tag_options(me),
                 hint => 'Pick a tag in use or type a new one.',
                 current_value => to_jsonb(coalesce(base.tags, '{}'))),
      make_field('type', 'Type', 'select', true, options => label_options('item_type'),
                 default_value => '"personal"', current_value => to_jsonb(base.type)),
      make_field('visibility', 'Who can see it', 'select', true,
                 options => label_options('item_visibility'),
                 default_value => '"private"', current_value => to_jsonb(base.visibility),
                 visible_if => shown_if('type', '"personal"')),
      make_field('vendor', 'Vendor details', 'group',
                 visible_if => shown_if('type', '"claimable"'),
                 nested => jsonb_build_array(
                   make_field('vendor_name', 'Vendor name', 'text',
                              hint => 'Needed once you fill in any vendor detail.',
                              current_value => to_jsonb(vendor.vendor_name)),
                   make_field('service', 'Service', 'text', current_value => to_jsonb(vendor.service)),
                   make_field('phone', 'Phone number', 'text', current_value => to_jsonb(vendor.phone)),
                   make_field('address', 'Address', 'text', hint => 'Can be used as a pickup location.',
                              current_value => to_jsonb(vendor.address)),
                   make_field('expected_time', 'Arrival or ready-for-pickup time', 'time',
                              hint => 'Use 24-hour time, like 17:00.',
                              current_value => to_jsonb(hhmm(vendor.expected_time))),
                   make_field('amount_egp', 'Amount to be paid (EGP)', 'number',
                              current_value => to_jsonb(vendor.amount_egp)),
                   make_field('details', 'Extra details', 'textarea',
                              current_value => to_jsonb(vendor.details))))),
    case when editing is not null then 'update_item' else 'create_item' end,
    'Save');
end;
$$;

create function container_form(context jsonb, me uuid) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  editing uuid := (context ->> 'item_id')::uuid;
  base    item%rowtype;
begin
  if editing is not null then
    select * into base from item i where i.id = editing;
    if not found then
      raise exception using message = 'This bag or box was deleted.', hint = 'NOT_FOUND';
    end if;
    if base.owner_id <> me or base.kind <> 'container' then
      raise exception using message = 'You can''t change this.', hint = 'NOT_ALLOWED';
    end if;
  end if;

  return make_form(
    'container',
    case when editing is not null then 'Edit bag or box' else 'Add bag or box' end,
    case when editing is not null then jsonb_build_object('item_id', editing) else '{}'::jsonb end,
    jsonb_build_array(
      make_field('name', 'Name', 'text', true, current_value => to_jsonb(base.name)),
      make_field('emoji', 'Emoji', 'emoji', current_value => to_jsonb(base.emoji))),
    case when editing is not null then 'update_item' else 'create_container' end,
    'Save');
end;
$$;

create function move_form(context jsonb, me uuid) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  target item%rowtype;
begin
  select * into target from item i where i.id = (context ->> 'item_id')::uuid;
  if not found then
    raise exception using message = 'This item was deleted.', hint = 'NOT_FOUND';
  end if;
  if target.kind <> 'item' or cargo_owner(target) is distinct from me then
    raise exception using message = 'You can''t change this.', hint = 'NOT_ALLOWED';
  end if;

  return make_form(
    'move_to_container', 'Move to bag',
    jsonb_build_object('item_id', target.id),
    jsonb_build_array(make_field(
      'container_id', 'Bag', 'select', true,
      options => (select coalesce(jsonb_agg(jsonb_build_object(
                    'value', bag.id, 'label', bag.name,
                    'emoji', coalesce(bag.emoji, emoji_of('item_kind', 'container')))
                  order by bag.name), '[]')
                  from item bag
                  where bag.kind = 'container' and bag.owner_id = me
                    and bag.id is distinct from target.parent_id))),
    'move_to_container', 'Move');
end;
$$;

-- "I'm coming with my car" ({trip}) or edit ({car_id}, owner only).
-- Only the fields of the car's trip are included (BR-14, BR-15).
create function car_form(context jsonb, me uuid) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  editing     uuid := (context ->> 'car_id')::uuid;
  ride        car%rowtype;
  car_trip    trip;
  leave_from  text;
  window_hint text;
  fields      jsonb;
begin
  if editing is not null then
    select * into ride from car c where c.id = editing;
    if not found then
      raise exception using message = 'This car no longer exists.', hint = 'NOT_FOUND';
    end if;
    if ride.owner_id <> me then
      raise exception using message = 'You can''t change this.', hint = 'NOT_ALLOWED';
    end if;
    if ride.withdrawn_at is not null then
      raise exception using message = 'This car is no longer available.', hint = 'CAR_WITHDRAWN';
    end if;
    car_trip := ride.trip;
  else
    car_trip := (context ->> 'trip')::trip;
    if car_trip is null then
      raise exception 'the car form needs a trip or a car_id';
    end if;
    if exists (select 1 from car c
               where c.owner_id = me and c.trip = car_trip and c.withdrawn_at is null) then
      raise exception using message = 'You already have a car on this trip.', hint = 'ALREADY_HAS_CAR';
    end if;
  end if;

  leave_from := case car_trip when 'to_hotel' then 'home'
                              when 'hotel_to_venue' then 'the hotel'
                              else 'the venue' end;
  window_hint := 'Only choose times you''re truly fine with. The bride may pick any time in this window. '
                 || 'Use 24-hour time, like 09:30.'
                 || case when car_trip = 'return_home'
                         then ' The window can cross midnight, like 23:30 to 00:30.' else '' end;

  fields := jsonb_build_array(
    make_field('seats', 'Available seats', 'number', true, hint => 'Seats for passengers.',
               current_value => to_jsonb(ride.seats)),
    make_field('departure_earliest', format('Earliest time to leave %s', leave_from), 'time', true,
               hint => window_hint, current_value => to_jsonb(hhmm(ride.departure_earliest))),
    make_field('departure_latest', format('Latest time to leave %s', leave_from), 'time', true,
               hint => window_hint, current_value => to_jsonb(hhmm(ride.departure_latest))));

  if car_trip = 'to_hotel' then
    fields := fields || jsonb_build_array(
      make_field('home_area', 'Where do you live?', 'select', true, options => label_options('area'),
                 current_value => to_jsonb(ride.home_area)),
      make_field('home_area_other', 'Your area', 'text', true,
                 current_value => to_jsonb(ride.home_area_other),
                 visible_if => shown_if('home_area', '"other"')),
      make_field('minutes_to_bride', 'Minutes to the bride''s house', 'number',
                 hint => 'Check Google Maps for the estimate.',
                 current_value => to_jsonb(ride.minutes_to_bride)),
      make_field('minutes_to_hotel', 'Minutes to the hotel', 'number',
                 hint => 'Check Google Maps for the estimate.',
                 current_value => to_jsonb(ride.minutes_to_hotel)),
      make_field('stops', 'Stops before the hotel', 'list',
                 current_value => (select coalesce(jsonb_agg(jsonb_build_object(
                                     'description', s.description, 'purpose', s.purpose)
                                     order by s.position), '[]')
                                   from car_stop s where s.car_id = ride.id),
                 nested => jsonb_build_array(
                   make_field('description', 'Stop', 'text', true),
                   make_field('purpose', 'For', 'select', true, options => label_options('stop_purpose')))));
  elsif car_trip = 'return_home' then
    fields := fields || jsonb_build_array(
      make_field('dropoff_areas', 'Areas I can drop people off in', 'multiselect',
                 options => label_options('area'),
                 current_value => (select coalesce(jsonb_agg(d.area order by d.area), '[]')
                                   from car_dropoff_area d where d.car_id = ride.id)),
      make_field('dropoff_area_other', 'Other area', 'text', true,
                 current_value => (select to_jsonb(d.area_other) from car_dropoff_area d
                                   where d.car_id = ride.id and d.area = 'other'),
                 visible_if => shown_if('dropoff_areas', '"other"')));
  end if;

  fields := fields || jsonb_build_array(
    make_field('trunk_percent', 'Guaranteed trunk space', 'select', true,
               options => label_options('trunk_percent'),
               current_value => to_jsonb(ride.trunk_percent::text)),
    make_field('notes', 'Notes', 'textarea', hint => 'Everyone can read this.',
               current_value => to_jsonb(ride.notes)));

  return make_form(
    'car',
    case when editing is not null then 'Edit my car' else 'I''m coming with my car' end,
    case when editing is not null then jsonb_build_object('car_id', editing)
         else jsonb_build_object('trip', car_trip) end,
    fields,
    case when editing is not null then 'update_car' else 'register_car' end,
    'Save');
end;
$$;

-- The car, active, for the passenger and cargo forms. An Offer needs my
-- car; an Ask needs someone else's.
create function form_car(context jsonb, me uuid, direction request_direction) returns car
language plpgsql stable set search_path = public as $$
declare
  ride car%rowtype;
begin
  select * into ride from car c where c.id = (context ->> 'car_id')::uuid;
  if not found then
    raise exception using message = 'This car no longer exists.', hint = 'NOT_FOUND';
  end if;
  if ride.withdrawn_at is not null then
    raise exception using message = 'This car is no longer available.', hint = 'CAR_WITHDRAWN';
  end if;
  if direction = 'ask' and ride.owner_id = me then
    raise exception using message = 'That''s your own car.', hint = 'OWN_CAR';
  end if;
  if direction = 'offer' and ride.owner_id <> me then
    raise exception using message = 'You can''t change this.', hint = 'NOT_ALLOWED';
  end if;
  return ride;
end;
$$;

create function passenger_offer_form(context jsonb, me uuid) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  ride car%rowtype := form_car(context, me, 'offer');
begin
  return make_form(
    'passenger_offer', 'Offer a seat',
    jsonb_build_object('car_id', ride.id, 'kind', 'passenger', 'direction', 'offer'),
    jsonb_build_array(make_field(
      'passenger_id', 'Who', 'select', true,
      options => (select coalesce(jsonb_agg(jsonb_build_object(
                    'value', m.id, 'label', member_title(m.id), 'emoji', null)
                  order by m.name), '[]')
                  from eligible_passengers(ride, me) m))),
    'send_request', 'Send offer');
end;
$$;

-- cargo_request (Ask: my cargo) and cargo_offer (Offer: someone else's).
create function cargo_form(context jsonb, me uuid, direction request_direction) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  ride        car%rowtype := form_car(context, me, direction);
  item_list   jsonb;
  vendor_ids  jsonb;
  pickups     jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'value', i.id,
           'label', i.name || case when direction = 'offer'
                                   then ' (' || member_name(cargo_owner(i)) || ')' else '' end,
           'emoji', coalesce(i.emoji, emoji_of('item_kind', i.kind::text)))
         order by i.name), '[]'),
         coalesce(jsonb_agg(i.id) filter (where exists (
           select 1 from vendor_details v where v.item_id = i.id and clean_text(v.address) is not null)), '[]')
  into item_list, vendor_ids
  from eligible_cargo(ride, me, direction = 'ask') i;

  -- BR-24: the vendor's address only for items whose vendor has one.
  select coalesce(jsonb_agg(
           jsonb_build_object('value', l.value, 'label', l.label, 'emoji', l.emoji)
           || case when l.value = 'vendor_address'
                   then jsonb_build_object('visible_if', shown_if('item_id', vendor_ids))
                   else '{}'::jsonb end
           order by l.sort_order), '[]')
  into pickups
  from option_label l
  where l.option_set = 'pickup_type'
    and (l.value <> 'vendor_address' or jsonb_array_length(vendor_ids) > 0);

  return make_form(
    case when direction = 'ask' then 'cargo_request' else 'cargo_offer' end,
    case when direction = 'ask' then 'Ask to carry an item' else 'Offer to carry an item' end,
    jsonb_build_object('car_id', ride.id, 'kind', 'cargo', 'direction', direction),
    jsonb_build_array(
      make_field('item_id', 'What', 'select', true, options => item_list),
      make_field('pickup_type', 'Pickup from', 'select', true, options => pickups),
      make_field('pickup_address', 'Pickup address', 'text', true,
                 visible_if => shown_if('pickup_type', '"custom"')),
      make_field('ready_at', 'Ready for pickup at', 'time',
                 hint => 'Use 24-hour time, like 10:00.')),
    'send_request',
    case when direction = 'ask' then 'Send request' else 'Send offer' end);
end;
$$;

create function get_form(name text, context jsonb default '{}') returns json
language plpgsql stable security definer set search_path = public as $$
declare
  me   uuid  := require_member();
  ctx  jsonb := coalesce(get_form.context, '{}');
begin
  case get_form.name
    when 'item'              then return item_form(ctx, me)::json;
    when 'container'         then return container_form(ctx, me)::json;
    when 'move_to_container' then return move_form(ctx, me)::json;
    when 'car'               then return car_form(ctx, me)::json;
    when 'passenger_offer'   then return passenger_offer_form(ctx, me)::json;
    when 'cargo_request'     then return cargo_form(ctx, me, 'ask')::json;
    when 'cargo_offer'       then return cargo_form(ctx, me, 'offer')::json;
    else
      raise exception using message = 'This form doesn''t exist.', hint = 'NOT_FOUND';
  end case;
end;
$$;

-- ---------------------------------------------------------------------
-- 9. Access
-- ---------------------------------------------------------------------

revoke all on function
  stamp_cancellation(),
  label_of(text, text), emoji_of(text, text), label_options(text),
  fmt_time(time), hhmm(time), fmt_window(time, time), fmt_ago(timestamptz), fmt_egp(numeric),
  join_parts(text[]), member_name(uuid), member_title(uuid),
  make_action(text, text, text, text, jsonb, text), form_action(text, text, text, text, jsonb),
  make_badge(text, text), make_row(text, text, text, text, jsonb, text, uuid, jsonb),
  make_pair(text, text), pairs(jsonb[]), make_filter(text, text, jsonb, text),
  filter_value(jsonb, text),
  make_field(text, text, text, boolean, jsonb, text, jsonb, jsonb, jsonb, jsonb),
  shown_if(text, jsonb), make_form(text, text, jsonb, jsonb, text, text),
  item_visibility_of(item), claim_badge(item), item_actions(item, uuid), item_row(item, uuid),
  group_row(item, uuid), vendor_row(item, vendor_details, uuid), tag_options(uuid),
  car_title(car, uuid), car_area(car), car_row(car, uuid), is_party(request, uuid),
  pickup_text(request), request_row(request, uuid),
  eligible_cargo(car, uuid, boolean), eligible_passengers(car, uuid),
  item_form(jsonb, uuid), container_form(jsonb, uuid), move_form(jsonb, uuid),
  car_form(jsonb, uuid), form_car(jsonb, uuid, request_direction),
  passenger_offer_form(jsonb, uuid), cargo_form(jsonb, uuid, request_direction)
  from public, anon, authenticated;

revoke all on function
  get_home(), list_items(jsonb), get_item(uuid), list_cars(jsonb), get_car(uuid),
  list_requests(jsonb), get_form(text, jsonb)
  from public, anon;

grant execute on function
  get_home(), list_items(jsonb), get_item(uuid), list_cars(jsonb), get_car(uuid),
  list_requests(jsonb), get_form(text, jsonb)
  to authenticated;
