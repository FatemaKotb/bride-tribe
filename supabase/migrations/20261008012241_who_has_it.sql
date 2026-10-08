-- =====================================================================
-- "Who has it" on a shared personal item (ruling from the user,
-- 2026-10-08, adding to the contract's get_item).
--
-- The shared list shows the copies of an item as one row and opens the
-- first copy, so the other members' copies couldn't be reached. The
-- item's detail now lists every shared copy in its group, by who has
-- it. Each row opens that member's own copy, and the copy being viewed
-- is marked "This one". The section shows only when someone else has a
-- shared copy. A copy made private leaves the list, as it leaves the
-- shared row (BR-07a).
-- =====================================================================

insert into option_label (option_set, value, label, emoji, sort_order) values
  ('badge', 'this_one', 'This one', null, 7);

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

    -- Who has it: the shared copies in the group, in the order they were
    -- added, each opening its owner's copy. A copy's name shows when it
    -- differs from this one's.
    if target.type = 'personal' and exists (
         select 1 from item copied
         where copied.group_id = target.group_id and copied.id <> target.id
           and copied.kind = 'item' and copied.type = 'personal' and copied.visibility = 'shared') then
      sections := sections || jsonb_build_array(jsonb_build_object(
        'title', 'Who has it',
        'rows', (select jsonb_agg(make_row(
                   copied.id::text, null, member_title(copied.owner_id),
                   join_parts(array[case when copied.name <> target.name then copied.name end,
                                    copied.description]),
                   case when copied.id = target.id
                        then jsonb_build_array(make_badge(label_of('badge', 'this_one'), 'neutral'))
                        else '[]'::jsonb end,
                   case when copied.id <> target.id then 'item' end,
                   case when copied.id <> target.id then copied.id end,
                   '[]')
                 order by copied.created_at, copied.id)
                 from item copied
                 where copied.group_id = target.group_id and copied.kind = 'item'
                   and copied.type = 'personal' and copied.visibility = 'shared'),
        'empty_message', 'No one else has it yet.'));
    end if;

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
