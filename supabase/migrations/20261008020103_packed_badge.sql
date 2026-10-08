-- =====================================================================
-- "Packed" is a badge beside Shared or Private (or the claim badge),
-- not a word in the subtitle (ruling from the user, 2026-10-08).
-- =====================================================================

insert into option_label (option_set, value, label, emoji, sort_order) values
  ('badge', 'packed', 'Packed', null, 8);

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
      'In: ' || (select bag.name from item bag where bag.id = target.parent_id)
    ]),
    case when target.type = 'claimable' then jsonb_build_array(claim_badge(target))
         else jsonb_build_array(make_badge(label_of('item_visibility', item_visibility_of(target)::text), 'neutral'))
    end
      || case when target.is_packed then jsonb_build_array(make_badge(label_of('badge', 'packed'), 'neutral'))
              else '[]'::jsonb end,
    'item', target.id,
    item_actions(target, me));
$$;
