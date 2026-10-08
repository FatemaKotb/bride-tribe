-- =====================================================================
-- Changes after the first look at the app. The hosted project was linked
-- once the earlier migrations were final, so changes now go in new files.
--
-- Rulings from the user (2026-10-08) that override the design documents:
-- - Every filter can be left empty to see everything. Items gains an
--   "all" view: my things plus what others share. Cars gains an "all
--   trips" view. A Show or Trip filter that isn't sent still starts on
--   Mine or To the hotel; an empty or unknown one means all.
-- - Roles aren't shown as words. The bride's and maid of honor's names
--   carry an emoji instead ("Wana 👑", "Ghooda 🎀"), and bridesmaids show
--   just their name. Overrides BR-01's "(Bridesmaid)" labels; the
--   contract's role_label becomes title.
-- - Items have no tags (overrides BR-04, BR-09a, the contract, and the
--   ERD).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Names with an emoji instead of a role
-- ---------------------------------------------------------------------

-- The role labels stay, for ordering by role.
update option_label
set emoji = case value when 'bride' then '👑' when 'maid_of_honor' then '🎀' end
where option_set = 'role';

-- "Wana 👑", "Ghooda 🎀", "Sara"
create or replace function member_title(member_id uuid) returns text
language sql stable set search_path = public as $$
  select m.name || coalesce(' ' || emoji_of('role', m.role::text), '') from member m where m.id = $1;
$$;

create or replace function list_members_for_login() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'members', coalesce(json_agg(
      json_build_object('id', m.id, 'name', m.name, 'title', member_title(m.id))
      order by r.sort_order, m.name
    ), '[]'::json)
  )
  from member m
  left join option_label r on r.option_set = 'role' and r.value = m.role::text;
$$;

create or replace function sign_in(member_id uuid) returns json
language plpgsql security definer set search_path = public as $$
declare
  chosen member%rowtype;
begin
  if auth.uid() is null then
    raise exception using
      message = 'Please pick your name to continue.',
      hint    = 'NOT_SIGNED_IN';
  end if;

  select * into chosen from member where id = sign_in.member_id;
  if not found then
    raise exception using
      message = 'We couldn''t find that name.',
      hint    = 'UNKNOWN_MEMBER';
  end if;

  insert into member_session (auth_user_id, member_id)
  values (auth.uid(), chosen.id)
  on conflict (auth_user_id) do update
    set member_id = excluded.member_id, created_at = now();

  return json_build_object('me', json_build_object(
    'id', chosen.id,
    'name', chosen.name,
    'title', member_title(chosen.id)
  ));
end;
$$;

create or replace function get_home() returns json
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
    'me', jsonb_build_object('name', self.name, 'title', member_title(self.id)),
    'my_status', jsonb_build_object(
      'value',   self.status,
      'label',   label_of('status', self.status::text),
      'updated', fmt_ago(self.status_updated_at),
      'options', label_options('status')),
    'attention', waiting || cancelled,
    'status_board', board)::json;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Items without tags, and the "all" view
-- ---------------------------------------------------------------------

drop function create_item(text, text, text, int, text[], item_type, item_visibility, jsonb, uuid);
drop function update_item(uuid, text, text, text, int, text[], item_type, item_visibility, jsonb);

-- The UI sends the item form's visible fields. Hidden fields arrive as
-- their defaults: visibility (hidden for claimable) and vendor (hidden
-- for personal).
create function create_item(
  name        text            default null,
  emoji       text            default null,
  description text            default null,
  quantity    int             default null,
  type        item_type       default 'personal',
  visibility  item_visibility default null,
  vendor      jsonb           default null,
  copy_of     uuid            default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  me       uuid := require_member();
  source   item%rowtype;
  group_of uuid := gen_random_uuid();
  new_id   uuid;
begin
  perform check_item_fields(create_item.name, create_item.quantity, create_item.type, create_item.vendor);

  -- BR-07: a copy joins the group of the shared personal item it copies.
  if create_item.copy_of is not null then
    select * into source from item where id = create_item.copy_of;
    if not found then
      raise exception using
        message = 'This item was deleted.',
        hint    = 'NOT_FOUND';
    end if;
    if source.type is distinct from 'personal'
       or source.visibility is distinct from 'shared' then
      raise exception using
        message = 'This item can''t be copied.',
        hint    = 'COPY_NOT_ALLOWED';
    end if;
    if exists (select 1 from item where owner_id = me and group_id = source.group_id) then
      raise exception using
        message = 'This is already on your list.',
        hint    = 'ALREADY_ON_YOUR_LIST';
    end if;
    group_of := source.group_id;
  end if;

  insert into item
    (kind, owner_id, group_id, name, emoji, description, quantity, visibility, type)
  values (
    'item', me, group_of,
    clean_text(create_item.name),
    clean_text(create_item.emoji),
    clean_text(create_item.description),
    create_item.quantity,
    -- BR-06: claimable items are always shared.
    case when create_item.type = 'claimable' then 'shared'
         else coalesce(create_item.visibility, 'private') end,
    create_item.type
  )
  returning id into new_id;

  perform save_vendor_details(new_id, create_item.vendor);
end;
$$;

-- Owner only, for every field including vendor details. The form sends
-- every visible field, so the submitted values replace the stored ones.
-- A container takes only name and emoji.
create function update_item(
  item_id     uuid,
  name        text            default null,
  emoji       text            default null,
  description text            default null,
  quantity    int             default null,
  type        item_type       default null,
  visibility  item_visibility default null,
  vendor      jsonb           default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  me       uuid := require_member();
  target   item%rowtype;
  new_type item_type;
begin
  target := lock_item(update_item.item_id);
  if target.owner_id <> me then
    raise exception using
      message = 'You can''t change this.',
      hint    = 'NOT_ALLOWED';
  end if;

  if target.kind = 'container' then
    if clean_text(update_item.name) is null then
      raise exception using
        message = 'Please give the bag or box a name.',
        hint    = 'NAME_REQUIRED';
    end if;
    if vendor_given(update_item.vendor) then
      raise exception using
        message = 'Vendor details can only be added to claimable items.',
        hint    = 'VENDOR_NOT_ALLOWED';
    end if;
    update item
    set name = clean_text(update_item.name), emoji = clean_text(update_item.emoji)
    where id = target.id;
    return;
  end if;

  new_type := coalesce(update_item.type, target.type);
  perform check_item_fields(update_item.name, update_item.quantity, new_type, update_item.vendor);

  if target.type = 'claimable' and new_type = 'personal'
     and (target.claimed_by_id is not null
          or exists (select 1 from vendor_details v where v.item_id = target.id)) then
    raise exception using
      message = 'Release the claim and remove the vendor details before making this personal.',
      hint    = 'TYPE_CHANGE_NOT_ALLOWED';
  end if;

  update item set
    name        = clean_text(update_item.name),
    emoji       = clean_text(update_item.emoji),
    description = clean_text(update_item.description),
    quantity    = update_item.quantity,
    type        = new_type,
    -- BR-06: claimable items are always shared.
    visibility  = case when new_type = 'claimable' then 'shared'
                       else coalesce(update_item.visibility, target.visibility) end,
    -- A newly claimable item is unclaimed, so no one handles it: it leaves
    -- its bag, as when a claim is released (ruling 2026-10-08). The bag
    -- keeps its car.
    parent_id   = case when target.type = 'personal' and new_type = 'claimable' then null
                       else target.parent_id end
  where id = target.id;

  -- Unclaimed items can't be cargo (BR-24), so its cargo requests go too.
  if target.type = 'personal' and new_type = 'claimable' then
    perform cancel_cargo_requests(target.id);
  end if;

  if new_type = 'claimable' then
    perform save_vendor_details(target.id, update_item.vendor);
  end if;
end;
$$;

revoke all on function
  create_item(text, text, text, int, item_type, item_visibility, jsonb, uuid),
  update_item(uuid, text, text, text, int, item_type, item_visibility, jsonb)
  from public, anon;

grant execute on function
  create_item(text, text, text, int, item_type, item_visibility, jsonb, uuid),
  update_item(uuid, text, text, text, int, item_type, item_visibility, jsonb)
  to authenticated;

-- BR-07a, BR-09a, BR-32. Filters arrive as {"key": ["value"]}.
create or replace function list_items(filters jsonb default '{}') returns json
language plpgsql stable security definer set search_path = public as $$
declare
  me            uuid := require_member();
  owner_choice  text := filter_value(filters, 'owner');
  kind_choice   text := filter_value(filters, 'kind');
  type_choice   text := filter_value(filters, 'type');
  packed_choice text := filter_value(filters, 'packed');
  vendor_choice text := filter_value(filters, 'vendor');
  bag_choice    text := filter_value(filters, 'container');
  row_list      jsonb;
  filter_list   jsonb;
begin
  -- Show starts on Mine when it isn't sent. Otherwise, as for every
  -- filter, an empty or unknown choice means all (ruling 2026-10-08).
  if not coalesce(filters ? 'owner', false) then
    owner_choice := 'mine';
  elsif owner_choice not in ('mine', 'shared') then
    owner_choice := null;
  end if;
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
    where (packed_choice is null or i.is_packed = (packed_choice = 'packed'));

    filter_list := jsonb_build_array(
      make_filter('vendor', 'Vendors', label_options('filter_vendor'), vendor_choice),
      make_filter('packed', 'Packed', label_options('filter_packed'), packed_choice));

  elsif owner_choice = 'shared' then
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
      union all
      select item_row(i, me), i.name, i.id
      from item i
      where i.type = 'claimable'
        and (type_choice is null or type_choice = 'claimable')
        and (kind_choice is null or kind_choice = 'item')
    ) shared;

    filter_list := jsonb_build_array(
      make_filter('owner', 'Show', label_options('filter_owner'), owner_choice),
      make_filter('type', 'Type', label_options('item_type'), type_choice),
      make_filter('vendor', 'Vendors', label_options('filter_vendor'), vendor_choice));

  else
    -- Mine: my items, items I claimed, and my bags. All adds what others
    -- share that isn't mine: the groups of shared copies I don't have,
    -- and claimable items I neither own nor claimed. Packing and bags are
    -- personal, so with those filters on, only my things are left. Bags
    -- come first, then by name.
    select coalesce(jsonb_agg(listed.row_json order by listed.is_bag desc, listed.title, listed.row_id),
                    '[]')
    into row_list
    from (
      select item_row(i, me) as row_json, i.kind = 'container' as is_bag,
             i.name as title, i.id as row_id
      from item i
      where (i.owner_id = me or i.claimed_by_id = me)
        and (kind_choice is null or i.kind::text = kind_choice)
        and (type_choice is null or i.type::text = type_choice)
        and (packed_choice is null or i.is_packed = (packed_choice = 'packed'))
        and (bag_choice is null
             or (bag_choice = 'none' and i.kind = 'item' and i.parent_id is null)
             or i.parent_id::text = bag_choice)
      union all
      select group_row(anchor, me), false, anchor.name, anchor.id
      from item anchor
      where owner_choice is null and packed_choice is null and bag_choice is null
        and anchor.id in (select distinct on (i.group_id) i.id
                          from item i
                          where i.kind = 'item' and i.type = 'personal' and i.visibility = 'shared'
                          order by i.group_id, i.created_at, i.id)
        and not exists (select 1 from item mine
                        where mine.owner_id = me and mine.group_id = anchor.group_id)
        and (type_choice is null or type_choice = 'personal')
        and (kind_choice is null or kind_choice = 'item')
      union all
      select item_row(i, me), false, i.name, i.id
      from item i
      where owner_choice is null and packed_choice is null and bag_choice is null
        and i.type = 'claimable' and i.owner_id <> me and i.claimed_by_id is distinct from me
        and (type_choice is null or type_choice = 'claimable')
        and (kind_choice is null or kind_choice = 'item')
    ) listed;

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
        bag_choice));
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

create or replace function get_item(item_id uuid) returns json
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

-- New item, edit ({item_id}, owner only), or "Add to my list"
-- ({copy_of}, pre-filled from the shared item).
create or replace function item_form(context jsonb, me uuid) returns jsonb
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
      make_field('quantity', 'Quantity', 'number', default_value => '1',
                 current_value => to_jsonb(base.quantity)),
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
                              hint => 'Use 24-hour time, like 23:30.',
                              current_value => to_jsonb(hhmm(vendor.expected_time))),
                   make_field('amount_egp', 'Amount to be paid (EGP)', 'number',
                              current_value => to_jsonb(vendor.amount_egp)),
                   make_field('details', 'Extra details', 'textarea',
                              current_value => to_jsonb(vendor.details))))),
    case when editing is not null then 'update_item' else 'create_item' end,
    'Save');
end;
$$;

drop function tag_options(uuid);
drop function clean_tags(text[]);
drop index item_tags_idx;
alter table item drop column tags;

-- ---------------------------------------------------------------------
-- 3. Cars: every trip at once, and passengers by name
-- ---------------------------------------------------------------------

drop function car_row(car, uuid);

-- BR-18: "Maadi · leaves 9:00 am–10:30 am · 2 of 4 seats taken". When
-- every trip is listed, the trip comes first: "To the hotel · Maadi · …".
create function car_row(ride car, me uuid, with_trip boolean) returns jsonb
language sql stable set search_path = public as $$
  select make_row(
    ride.id::text, '🚗', car_title(ride, me),
    join_parts(array[
      case when with_trip then label_of('trip', ride.trip::text) end,
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

revoke all on function car_row(car, uuid, boolean) from public, anon, authenticated;

-- BR-18. One row per active car, by trip, then in departure order. A
-- Return home window can cross midnight, so it is ordered from noon.
create or replace function list_cars(filters jsonb default '{}') returns json
language plpgsql stable security definer set search_path = public as $$
declare
  me          uuid := require_member();
  trip_choice text := filter_value(filters, 'trip');
  row_list    jsonb;
begin
  -- Trip starts on To the hotel when it isn't sent. An empty or unknown
  -- choice means every trip (ruling 2026-10-08).
  if not coalesce(filters ? 'trip', false) then
    trip_choice := 'to_hotel';
  elsif trip_choice not in (select unnest(enum_range(null::trip))::text) then
    trip_choice := null;
  end if;

  select coalesce(jsonb_agg(car_row(c, me, trip_choice is null)
           order by trip_label.sort_order,
                    case when c.trip = 'return_home' then c.departure_earliest - interval '12 hours'
                         else c.departure_earliest end,
                    member_name(c.owner_id), c.id), '[]')
  into row_list
  from car c
  join option_label trip_label on trip_label.option_set = 'trip' and trip_label.value = c.trip::text
  where (trip_choice is null or c.trip::text = trip_choice) and c.withdrawn_at is null;

  return jsonb_build_object(
    'title', 'Cars',
    'filters', jsonb_build_array(make_filter('trip', 'Trip', label_options('trip'), trip_choice)),
    'rows', row_list,
    'empty_message', case when trip_choice is null then 'No cars yet.'
                          else 'No cars on this trip yet.' end,
    -- A car is registered for one trip, so the action needs a trip chosen.
    'actions', case
      when trip_choice is null
           or exists (select 1 from car c
                      where c.owner_id = me and c.trip::text = trip_choice and c.withdrawn_at is null)
      then '[]'::jsonb
      else jsonb_build_array(form_action('register_car', 'I''m coming with my car', 'primary', 'car',
                                         jsonb_build_object('trip', trip_choice)))
    end)::json;
end;
$$;

-- Passengers show their initial, not a role emoji, which their name now
-- carries.
create or replace function get_car(car_id uuid) returns json
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
                 r.id::text, null, member_title(r.passenger_id), null, '[]', null, null,
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
