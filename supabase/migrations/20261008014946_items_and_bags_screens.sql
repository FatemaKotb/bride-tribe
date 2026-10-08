-- =====================================================================
-- Items and bags on separate screens, with one filter each.
--
-- Rulings from the user (2026-10-08) that override the design documents:
-- - Items and bags are two screens: list_items lists items only, and
--   list_bags, a new read function, lists bags and boxes.
-- - Each screen has one filter, Show: Mine or Shared, or nothing chosen
--   for everything. The Kind, Type, Packed, Vendors, and Bag filters are
--   gone, and with them the vendor list by arrival time. Vendor details
--   stay on each item's page. Overrides BR-09a, BR-32, and the contract's
--   list_items filters.
-- - Someone else's bag says whose it is, and counts only the items I can
--   see.
-- =====================================================================

-- One item or bag (BR-11a: "Perfume · In: Blue bag"; "Sara · 2 items").
create or replace function item_row(target item, me uuid) returns jsonb
language sql stable set search_path = public as $$
  select make_row(
    target.id::text,
    coalesce(target.emoji, emoji_of('item_kind', target.kind::text)),
    target.name,
    join_parts(array[
      case when target.kind = 'container' and target.owner_id <> me then member_name(target.owner_id) end,
      case when target.kind = 'container' then
        (select case count(*) when 0 then 'Empty' when 1 then '1 item' else count(*) || ' items' end
         from item inside where inside.parent_id = target.id and can_see_item(inside, me))
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

-- BR-07a. Show starts on Mine when it isn't sent; an empty or unknown
-- choice means everything.
create or replace function list_items(filters jsonb default '{}') returns json
language plpgsql stable security definer set search_path = public as $$
declare
  me           uuid := require_member();
  owner_choice text := filter_value(filters, 'owner');
  row_list     jsonb;
begin
  if not coalesce(filters ? 'owner', false) then
    owner_choice := 'mine';
  elsif owner_choice not in ('mine', 'shared') then
    owner_choice := null;
  end if;

  -- Everything is Mine plus the Shared rows that aren't already mine.
  select coalesce(jsonb_agg(listed.row_json order by listed.title, listed.row_id), '[]')
  into row_list
  from (
    -- Mine: my items and the items I claimed.
    select item_row(i, me) as row_json, i.name as title, i.id as row_id
    from item i
    where owner_choice is distinct from 'shared'
      and i.kind = 'item' and (i.owner_id = me or i.claimed_by_id = me)
    union all
    -- Shared: one row per group of shared personal copies (BR-07a)...
    select group_row(anchor, me), anchor.name, anchor.id
    from item anchor
    where owner_choice is distinct from 'mine'
      and anchor.id in (select distinct on (i.group_id) i.id
                        from item i
                        where i.kind = 'item' and i.type = 'personal' and i.visibility = 'shared'
                        order by i.group_id, i.created_at, i.id)
      and (owner_choice = 'shared'
           or not exists (select 1 from item mine
                          where mine.owner_id = me and mine.group_id = anchor.group_id))
    union all
    -- ...and one per claimable item.
    select item_row(i, me), i.name, i.id
    from item i
    where owner_choice is distinct from 'mine'
      and i.type = 'claimable'
      and (owner_choice = 'shared' or (i.owner_id <> me and i.claimed_by_id is distinct from me))
  ) listed;

  return jsonb_build_object(
    'title', 'Items',
    'filters', jsonb_build_array(make_filter('owner', 'Show', label_options('filter_owner'), owner_choice)),
    'rows', row_list,
    'empty_message', 'No items here yet.',
    'actions', jsonb_build_array(form_action('add_item', 'Add item', 'primary', 'item', '{}')))::json;
end;
$$;

-- BR-10. Mine: my bags. Shared: every bag the others can see, which is a
-- bag holding a shared item, mine included. Show works as on Items.
create function list_bags(filters jsonb default '{}') returns json
language plpgsql stable security definer set search_path = public as $$
declare
  me           uuid := require_member();
  owner_choice text := filter_value(filters, 'owner');
  row_list     jsonb;
begin
  if not coalesce(filters ? 'owner', false) then
    owner_choice := 'mine';
  elsif owner_choice not in ('mine', 'shared') then
    owner_choice := null;
  end if;

  select coalesce(jsonb_agg(item_row(bag, me) order by bag.name, bag.id), '[]')
  into row_list
  from item bag
  where bag.kind = 'container'
    and case owner_choice
          when 'mine'   then bag.owner_id = me
          when 'shared' then item_visibility_of(bag) = 'shared'
          else can_see_item(bag, me)
        end;

  return jsonb_build_object(
    'title', 'Bags',
    'filters', jsonb_build_array(make_filter('owner', 'Show', label_options('filter_owner'), owner_choice)),
    'rows', row_list,
    'empty_message', 'No bags or boxes here yet.',
    'actions', jsonb_build_array(form_action('add_bag', 'Add bag or box', 'primary', 'container', '{}')))::json;
end;
$$;

revoke all on function list_bags(jsonb) from public, anon;
grant execute on function list_bags(jsonb) to authenticated;

-- The vendor list and the filters' own labels are no longer used.
drop function vendor_row(item, vendor_details, uuid);
delete from option_label where option_set in ('filter_vendor', 'filter_container');
