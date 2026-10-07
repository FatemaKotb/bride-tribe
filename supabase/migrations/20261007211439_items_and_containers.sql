-- =====================================================================
-- Item and container functions (contract Section 4, BR-04 to BR-11a,
-- BR-24, BR-29 to BR-31)
--
-- Rulings that fill gaps in, or override, the design documents:
-- - Only an item's owner can edit it, vendor details included
--   (2026-10-07; overrides BR-31 and the contract's update_item).
-- - Out-of-range numbers raise INVALID_NUMBER, a code added to the
--   contract's list (2026-10-08).
-- - Deleting an item deletes its declined cargo requests (2026-10-08).
-- - Only the claimer moves a claimed item between bags, never its owner
--   (2026-10-08; narrower than the contract's move_to_container).
-- - An item made claimable leaves its bag, so a claimable item is only
--   ever in its claimer's bag (2026-10-08; the schema trigger enforces it).
-- - An id that points at nothing raises NOT_FOUND, a code added to the
--   contract's list (2026-10-08).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Internal helpers (not callable through the API)
-- ---------------------------------------------------------------------

-- Trimmed text, with blanks as null.
create function clean_text(value text) returns text
language sql immutable set search_path = public as $$
  select nullif(btrim(value), '');
$$;

-- Trimmed tags, without blanks or duplicates, in the order first typed.
create function clean_tags(tags text[]) returns text[]
language sql immutable set search_path = public as $$
  select coalesce(array_agg(tag order by first_pos), '{}')
  from (
    select btrim(raw) as tag, min(pos) as first_pos
    from unnest(tags) with ordinality as t (raw, pos)
    where btrim(raw) <> ''
    group by btrim(raw)
  ) cleaned;
$$;

-- True when the vendor group has at least one field filled in. A group
-- left empty means "no vendor details".
create function vendor_given(vendor jsonb) returns boolean
language sql immutable set search_path = public as $$
  select case when jsonb_typeof(vendor) = 'object' then exists (
    select 1 from jsonb_each_text(vendor)
    where key in ('vendor_name', 'service', 'phone', 'address',
                  'expected_time', 'amount_egp', 'details')
      and clean_text(value) is not null
  ) else false end;
$$;

-- Checks shared by create_item and update_item.
create function check_item_fields(item_name text, item_quantity int, new_type item_type, vendor jsonb)
returns void
language plpgsql set search_path = public as $$
begin
  if clean_text(item_name) is null then
    raise exception using
      message = 'Please give the item a name.',
      hint    = 'NAME_REQUIRED';
  end if;

  if item_quantity < 1 then
    raise exception using
      message = 'Quantity must be at least 1.',
      hint    = 'INVALID_NUMBER';
  end if;

  -- BR-29: vendor details live only on claimable items.
  if vendor_given(vendor) and new_type is distinct from 'claimable' then
    raise exception using
      message = 'Vendor details can only be added to claimable items.',
      hint    = 'VENDOR_NOT_ALLOWED';
  end if;
end;
$$;

-- Replaces an item's vendor details with the submitted group, or removes
-- them when the group is empty.
create function save_vendor_details(target_item_id uuid, vendor jsonb) returns void
language plpgsql set search_path = public as $$
declare
  amount numeric;
begin
  if not vendor_given(vendor) then
    delete from vendor_details where item_id = target_item_id;
    return;
  end if;

  if clean_text(vendor ->> 'vendor_name') is null then
    raise exception using
      message = 'Please add the vendor''s name.',
      hint    = 'NAME_REQUIRED';
  end if;

  amount := clean_text(vendor ->> 'amount_egp')::numeric;
  if amount < 0 then
    raise exception using
      message = 'The amount can''t be negative.',
      hint    = 'INVALID_NUMBER';
  end if;

  insert into vendor_details
    (item_id, vendor_name, service, phone, address, expected_time, amount_egp, details)
  values (
    target_item_id,
    clean_text(vendor ->> 'vendor_name'),
    clean_text(vendor ->> 'service'),
    clean_text(vendor ->> 'phone'),
    clean_text(vendor ->> 'address'),
    clean_text(vendor ->> 'expected_time')::time,
    amount,
    clean_text(vendor ->> 'details')
  )
  on conflict (item_id) do update set
    vendor_name   = excluded.vendor_name,
    service       = excluded.service,
    phone         = excluded.phone,
    address       = excluded.address,
    expected_time = excluded.expected_time,
    amount_egp    = excluded.amount_egp,
    details       = excluded.details;
end;
$$;

-- Cancels an item's pending and confirmed cargo requests (auto). The
-- affected members see them in "Needs your attention" (BR-34).
create function cancel_cargo_requests(target_item_id uuid) returns void
language sql set search_path = public as $$
  update request
  set state = 'cancelled', cancel_reason = 'auto'
  where kind = 'cargo' and item_id = target_item_id
    and state in ('pending', 'confirmed');
$$;

-- BR-24: the cargo's owner is the creator of a personal item or a
-- container, and the claimer of a claimable item (null while unclaimed).
-- The same member packs it (BR-09) and moves it between bags (ruling
-- 2026-10-08).
create function cargo_owner(target item) returns uuid
language sql immutable set search_path = public as $$
  select case when target.type = 'claimable' then target.claimed_by_id
              else target.owner_id end;
$$;

-- The item, locked until the calling function finishes, or NOT_FOUND
-- when it was deleted after the member's screen loaded.
create function lock_item(target_id uuid) returns item
language plpgsql set search_path = public as $$
declare
  found_item item%rowtype;
begin
  select * into found_item from item where id = target_id for update;
  if not found then
    raise exception using
      message = 'This item was deleted.',
      hint    = 'NOT_FOUND';
  end if;
  return found_item;
end;
$$;

revoke all on function
  clean_text(text), clean_tags(text[]), vendor_given(jsonb),
  check_item_fields(text, int, item_type, jsonb), save_vendor_details(uuid, jsonb),
  cancel_cargo_requests(uuid), cargo_owner(item), lock_item(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. Items and containers (BR-04 to BR-07b, BR-10, BR-29 to BR-31)
-- ---------------------------------------------------------------------

-- The UI sends the item form's visible fields. Hidden fields arrive as
-- their defaults: visibility (hidden for claimable) and vendor (hidden
-- for personal).
create function create_item(
  name        text            default null,
  emoji       text            default null,
  description text            default null,
  quantity    int             default null,
  tags        text[]          default '{}',
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
    (kind, owner_id, group_id, name, emoji, description, quantity, tags, visibility, type)
  values (
    'item', me, group_of,
    clean_text(create_item.name),
    clean_text(create_item.emoji),
    clean_text(create_item.description),
    create_item.quantity,
    clean_tags(create_item.tags),
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
  tags        text[]          default '{}',
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
    tags        = clean_tags(update_item.tags),
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

create function create_container(name text default null, emoji text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := require_member();
begin
  if clean_text(create_container.name) is null then
    raise exception using
      message = 'Please give the bag or box a name.',
      hint    = 'NAME_REQUIRED';
  end if;

  insert into item (kind, owner_id, name, emoji)
  values ('container', me, clean_text(create_container.name), clean_text(create_container.emoji));
end;
$$;

create function delete_item(item_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me     uuid := require_member();
  target item%rowtype;
begin
  target := lock_item(delete_item.item_id);
  if target.owner_id <> me then
    raise exception using
      message = 'You can''t change this.',
      hint    = 'NOT_ALLOWED';
  end if;

  -- Live requests are cancelled and kept without their item, so the car
  -- owner still sees them. Declined ones can't lose their item, so they
  -- are deleted (ruling 2026-10-08).
  perform cancel_cargo_requests(target.id);
  delete from request r
  where r.kind = 'cargo' and r.item_id = target.id and r.state = 'declined';

  -- A container's contents move out through parent_id's "on delete set
  -- null". Copies keep their group_id, so the group survives (BR-07b).
  delete from item where id = target.id;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Claims, packing, and bags (BR-08 to BR-11)
-- ---------------------------------------------------------------------

create function claim_item(item_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me     uuid := require_member();
  target item%rowtype;
begin
  target := lock_item(claim_item.item_id);
  if target.type is distinct from 'claimable' then
    raise exception using
      message = 'This item can''t be claimed.',
      hint    = 'NOT_CLAIMABLE';
  end if;

  if target.claimed_by_id = me then
    raise exception using
      message = 'You already claimed this.',
      hint    = 'ALREADY_CLAIMED';
  elsif target.claimed_by_id is not null then
    raise exception using
      message = format('%s already claimed this.',
                       (select m.name from member m where m.id = target.claimed_by_id)),
      hint    = 'ALREADY_CLAIMED';
  end if;

  update item set claimed_by_id = me where id = target.id;
end;
$$;

-- Only the claimer can release (BR-02, BR-08). A claimed item can only be
-- in its claimer's bag, so releasing always takes it out.
create function release_claim(item_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me     uuid := require_member();
  target item%rowtype;
begin
  target := lock_item(release_claim.item_id);
  if target.claimed_by_id is distinct from me then
    raise exception using
      message = 'You can''t change this.',
      hint    = 'NOT_ALLOWED';
  end if;

  perform cancel_cargo_requests(target.id);
  update item set claimed_by_id = null, parent_id = null where id = target.id;
end;
$$;

create function set_packed(item_id uuid, packed boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  me     uuid := require_member();
  target item%rowtype;
begin
  target := lock_item(set_packed.item_id);
  if cargo_owner(target) is distinct from me then
    raise exception using
      message = 'You can''t change this.',
      hint    = 'NOT_ALLOWED';
  end if;

  update item set is_packed = set_packed.packed where id = target.id;
end;
$$;

-- container_id null takes the item out of its bag. Only the cargo's
-- owner moves an item, so a claimable item is moved by its claimer and
-- never by its owner (ruling 2026-10-08, narrower than the contract's
-- "mine or claimed by me").
create function move_to_container(item_id uuid, container_id uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  me     uuid := require_member();
  target item%rowtype;
  bag    item%rowtype;
begin
  target := lock_item(move_to_container.item_id);
  if cargo_owner(target) is distinct from me then
    raise exception using
      message = 'You can''t change this.',
      hint    = 'NOT_ALLOWED';
  end if;

  if move_to_container.container_id is null then
    update item set parent_id = null where id = target.id;
    return;
  end if;

  if target.kind = 'container' then
    raise exception using
      message = 'A bag can''t go inside another bag.',
      hint    = 'NO_NESTING';
  end if;

  select * into bag from item where id = move_to_container.container_id;
  if not found then
    raise exception using
      message = 'This bag or box was deleted.',
      hint    = 'NOT_FOUND';
  end if;
  if bag.kind <> 'container' then
    raise exception using
      message = 'Pick a bag or box.',
      hint    = 'NOT_A_CONTAINER';
  end if;
  if bag.owner_id <> me then
    raise exception using
      message = 'You can''t change this.',
      hint    = 'NOT_ALLOWED';
  end if;

  if target.parent_id is distinct from bag.id then
    update item set parent_id = bag.id where id = target.id;
    -- BR-11: it travels with its bag now, not on its own.
    perform cancel_cargo_requests(target.id);
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Access
-- ---------------------------------------------------------------------

revoke all on function
  create_item(text, text, text, int, text[], item_type, item_visibility, jsonb, uuid),
  update_item(uuid, text, text, text, int, text[], item_type, item_visibility, jsonb),
  create_container(text, text),
  delete_item(uuid),
  claim_item(uuid),
  release_claim(uuid),
  set_packed(uuid, boolean),
  move_to_container(uuid, uuid)
  from public, anon;

grant execute on function
  create_item(text, text, text, int, text[], item_type, item_visibility, jsonb, uuid),
  update_item(uuid, text, text, text, int, text[], item_type, item_visibility, jsonb),
  create_container(text, text),
  delete_item(uuid),
  claim_item(uuid),
  release_claim(uuid),
  set_packed(uuid, boolean),
  move_to_container(uuid, uuid)
  to authenticated;
