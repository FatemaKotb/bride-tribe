-- list_items, list_bags, and get_item: rows, filters, and which actions
-- each member gets (contract Section 3, BR-05 to BR-11a, BR-29 to BR-31,
-- and the rulings of 2026-10-08: items and bags on separate screens,
-- each filtered by Show only).
begin;
\ir _helpers.psql
\ir _read_helpers.psql

select plan(52);

select tests.wedding();

-- ---------------------------------------------------------------------
-- list_items: my items
-- ---------------------------------------------------------------------

select has_function('public', 'list_items', array['jsonb']);

select tests.no_session();

select tests.throws_error(
  'select list_items()',
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'list_items without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Sara');

select is(
  tests.titles(list_items()::jsonb),
  'Giveaways, Hair clip, Perfume',
  'by default: my items and the items I claimed, by name, without bags'
);

select is(
  list_items()::jsonb -> 'filters',
  '[{"key": "owner", "label": "Show", "multi": false, "selected": ["mine"],
     "options": [{"value": "mine", "label": "Mine", "emoji": null},
                 {"value": "shared", "label": "Shared", "emoji": null}]}]',
  'Show is the only filter, starting on Mine, with its labels from option_label'
);

select is(
  tests.row_titled(list_items()::jsonb, 'Hair clip') - 'id' - 'open' - 'actions' - 'emoji',
  '{"title": "Hair clip", "subtitle": "In: Blue bag", "badges": [{"label": "Private", "tone": "neutral"}]}',
  'an item shows its bag and its visibility (BR-11a)'
);

select is(
  tests.action_ids(tests.row_titled(list_items()::jsonb, 'Hair clip')),
  'pack,remove_from_bag,edit,delete',
  'my item in a bag: pack, remove from the bag, edit, delete'
);

select is(
  tests.action_ids(tests.row_titled(list_items()::jsonb, 'Perfume')),
  'pack,move_to_bag,edit,delete',
  'my item not in a bag: pack, move to a bag, edit, delete'
);

select is(
  tests.badges(tests.row_titled(list_items()::jsonb, 'Giveaways')) || ' / '
    || tests.action_ids(tests.row_titled(list_items()::jsonb, 'Giveaways')),
  'Claimed by Sara / release,pack,move_to_bag',
  'an item I claimed: release, pack, move to a bag, but not edit or delete (rulings)'
);

select is(
  tests.row_titled(list_items()::jsonb, 'Giveaways') -> 'actions' -> 0 ->> 'confirm',
  'Release your claim on Giveaways?',
  'releasing a claim asks first'
);

select is(
  tests.row_titled(list_items()::jsonb, 'Hair clip') -> 'actions' -> 1 -> 'call',
  jsonb_build_object('function', 'move_to_container',
                     'args', jsonb_build_object('item_id', tests.item_id('Hair clip'), 'container_id', null)),
  'Remove from bag calls move_to_container with no bag'
);

select tests.act_as('Mai');

select is(
  tests.action_ids(tests.row_titled(list_items()::jsonb, 'Giveaways'))
    || ' / ' || tests.action_ids(tests.row_titled(list_items()::jsonb, 'Photographer')),
  'edit,delete / claim,edit,delete',
  'the owner of a claimed item can edit or delete it, but not pack, move, or release it'
);

select tests.act_as('Nour');
select create_item(name => 'Shoes');

select is(
  tests.action_ids(tests.row_titled(list_items()::jsonb, 'Shoes')),
  'pack,edit,delete',
  'Move to bag appears only for members who have a bag'
);

select tests.act_as('Sara');

select is(tests.titles(list_items('{"owner": "shared"}')::jsonb), 'Flowers, Giveaways, Perfume, Photographer',
  'a filter given as a plain value');
select is(tests.titles(list_items('{"type": ["claimable"], "vendor": ["has_vendor"], "kind": ["container"]}')::jsonb),
  'Giveaways, Hair clip, Perfume',
  'filters that no longer exist are ignored');

select is(
  tests.action_ids(list_items()::jsonb),
  'add_item',
  'screen action: Add item'
);

-- ---------------------------------------------------------------------
-- list_items: everything (ruling 2026-10-08)
-- ---------------------------------------------------------------------

select is(
  tests.titles(list_items('{"owner": []}')::jsonb),
  'Flowers, Giveaways, Hair clip, Perfume, Photographer',
  'an empty Show filter lists everything: my items, and claimable items others own'
);

select is(
  list_items('{"owner": []}')::jsonb -> 'filters' -> 0 -> 'selected',
  '[]',
  'with everything shown, Show has nothing chosen'
);

select is(tests.titles(list_items('{"owner": ["everyone"]}')::jsonb),
  'Flowers, Giveaways, Hair clip, Perfume, Photographer',
  'an unknown Show choice also means everything');

select tests.act_as('Nour');

select is(
  (select tests.titles(l) || ' / ' || (tests.row_titled(l, 'Perfume') ->> 'subtitle')
            || ' / ' || tests.action_ids(tests.row_titled(l, 'Perfume'))
   from (select list_items('{"owner": []}')::jsonb as l) s),
  'Flowers, Giveaways, Perfume, Photographer, Shoes / Sara, Mai / add_to_list',
  'a shared group I don''t have shows as one row, with Add to my list'
);

-- ---------------------------------------------------------------------
-- list_bags (ruling 2026-10-08)
-- ---------------------------------------------------------------------

select has_function('public', 'list_bags', array['jsonb']);

select tests.no_session();

select tests.throws_error(
  'select list_bags()',
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'list_bags without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Sara');

select is(
  jsonb_build_array(tests.titles(list_bags()::jsonb), list_bags()::jsonb -> 'filters' -> 0 -> 'selected',
                    tests.action_ids(list_bags()::jsonb), list_bags()::jsonb ->> 'title'),
  '["Blue bag, Tote", ["mine"], "add_bag", "Bags"]',
  'by default: my bags by name, with Show on Mine and Add bag or box'
);

select is(
  (select r ->> 'subtitle' || ' / ' || tests.action_ids(r) || ' / ' || (r -> 'actions' -> 1 -> 'form' ->> 'name')
   from (select tests.row_titled(list_bags()::jsonb, 'Blue bag') as r) s),
  '1 item / pack,edit,delete / container',
  'my bag: its item count, pack, edit with the bag form, delete'
);

select set_packed(tests.item_id('Blue bag'), true);

select is(
  (select r ->> 'subtitle' || ' / ' || tests.badges(r) || ' / ' || (r -> 'actions' -> 0 ->> 'label')
   from (select tests.row_titled(list_bags()::jsonb, 'Blue bag') as r) s),
  '1 item / Private, Packed / Mark unpacked',
  'a packed bag gets a Packed badge beside its visibility, and offers Mark unpacked (ruling 2026-10-08)'
);

-- The Tote holds the shared Perfume and a private Lipstick, so it's shared.
select create_item(name => 'Lipstick');
select move_to_container(tests.item_id('Perfume', 'Sara'), tests.item_id('Tote'));
select move_to_container(tests.item_id('Lipstick'), tests.item_id('Tote'));

select is(
  (select tests.titles(l) || ' / ' || (tests.row_titled(l, 'Tote') ->> 'subtitle')
   from (select list_bags('{"owner": ["shared"]}')::jsonb as l) s),
  'Tote / 2 items',
  'Shared: bags holding a shared item, mine included'
);

select tests.act_as('Nour');

select is(
  (select tests.titles(l) || ' / ' || (tests.row_titled(l, 'Tote') ->> 'subtitle')
            || ' / ' || tests.action_ids(tests.row_titled(l, 'Tote'))
   from (select list_bags('{"owner": ["shared"]}')::jsonb as l) s),
  'Tote / Sara · 1 item / ',
  'someone else''s bag says whose it is and counts only what I can see, with no actions'
);

select is(
  tests.titles(list_bags()::jsonb) || ' / ' || tests.titles(list_bags('{"owner": []}')::jsonb),
  ' / Tote',
  'Mine is only my bags; everything adds the shared ones'
);

-- ---------------------------------------------------------------------
-- list_items: shared (BR-07a)
-- ---------------------------------------------------------------------

select tests.act_as('Nour');

select is(
  tests.titles(list_items('{"owner": ["shared"]}')::jsonb),
  'Flowers, Giveaways, Perfume, Photographer',
  'shared: one row per shared personal group and one per claimable item, by name'
);

select is(
  (select r ->> 'subtitle' || ' / ' || tests.action_ids(r)
   from (select tests.row_titled(list_items('{"owner": ["shared"]}')::jsonb, 'Perfume') as r) s),
  'Sara, Mai / add_to_list',
  'a group lists who has it and offers Add to my list to the others'
);

select is(
  tests.row_titled(list_items('{"owner": ["shared"]}')::jsonb, 'Perfume') -> 'actions' -> 0 -> 'form',
  jsonb_build_object('name', 'item', 'context', jsonb_build_object('copy_of', tests.item_id('Perfume', 'Sara'))),
  'Add to my list opens the item form copying the original'
);

select is(
  tests.badges(tests.row_titled(list_items('{"owner": ["shared"]}')::jsonb, 'Giveaways'))
    || ' / ' || tests.action_ids(tests.row_titled(list_items('{"owner": ["shared"]}')::jsonb, 'Giveaways'))
    || ' / ' || tests.badges(tests.row_titled(list_items('{"owner": ["shared"]}')::jsonb, 'Flowers'))
    || ' / ' || tests.action_ids(tests.row_titled(list_items('{"owner": ["shared"]}')::jsonb, 'Flowers')),
  'Claimed by Sara /  / Unclaimed / claim',
  'claimable items show the claimer or Unclaimed, and Claim when unclaimed (BR-08)'
);

select tests.act_as('Mai');

select is(
  (select tests.badges(r) || ' / ' || tests.action_ids(r)
   from (select tests.row_titled(list_items('{"owner": ["shared"]}')::jsonb, 'Perfume') as r) s),
  'On your list / ',
  'a member who has it sees On your list'
);

select update_item(tests.item_id('Perfume', 'Mai'), name => 'Perfume', emoji => '📿',
                   type => 'personal', visibility => 'private');

select is(
  (select r ->> 'subtitle' || ' / ' || tests.badges(r)
   from (select tests.row_titled(list_items('{"owner": ["shared"]}')::jsonb, 'Perfume') as r) s),
  'Sara / On your list',
  'a copy made private leaves the group''s names but is still on my list'
);

select update_item(tests.item_id('Perfume', 'Mai'), name => 'Perfume', emoji => '📿',
                   type => 'personal', visibility => 'shared');
select tests.act_as('Sara');
select delete_item(tests.item_id('Perfume', 'Sara'));
select tests.act_as('Nour');

select is(
  (select r ->> 'subtitle' || ' / ' || (r -> 'actions' -> 0 -> 'form' -> 'context' ->> 'copy_of')
   from (select tests.row_titled(list_items('{"owner": ["shared"]}')::jsonb, 'Perfume') as r) s),
  'Mai / ' || tests.item_id('Perfume', 'Mai'),
  'when the original is deleted, the group stays, anchored to the next copy (BR-07b)'
);


-- ---------------------------------------------------------------------
-- get_item
-- ---------------------------------------------------------------------

select has_function('public', 'get_item', array['uuid']);

select tests.no_session();

select tests.throws_error(
  format('select get_item(%L)', tests.item_id('Photographer')),
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'get_item without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Nour');

select tests.throws_error(
  format('select get_item(%L)', gen_random_uuid()),
  'NOT_FOUND', 'This item was deleted.',
  'an unknown item raises NOT_FOUND'
);

select tests.throws_error(
  format('select get_item(%L)', tests.item_id('Hair clip')),
  'NOT_FOUND', 'This item was deleted.',
  'someone else''s private item is not found (BR-05)'
);

select is(
  get_item(tests.item_id('Photographer'))::jsonb - 'sections' - 'actions',
  '{"emoji": "📸", "title": "Photographer", "subtitle": "Claimable · Shared"}',
  'an item''s detail heading'
);

select is(
  tests.pairs_text(tests.section(get_item(tests.item_id('Photographer'))::jsonb, 'Details')),
  'Added by: Mai; Visibility: Shared; Type: Claimable; Claimed by: Unclaimed; Packing: Not packed',
  'its details, without empty fields'
);

select is(
  tests.pairs_text(tests.section(get_item(tests.item_id('Photographer'))::jsonb, 'Vendor')),
  'Vendor: Ahmed Hassan; Service: Photographer; Time: 5:00 pm; Amount: 2,000 EGP',
  'everyone sees the vendor details (BR-31)'
);

select is(
  tests.action_ids(get_item(tests.item_id('Photographer'))::jsonb),
  'claim',
  'the detail has the same actions as the row'
);

select tests.act_as('Sara');

select is(
  tests.pairs_text(tests.section(get_item(tests.item_id('Hair clip'))::jsonb, 'Details')),
  'Added by: Sara; Visibility: Private; Type: Personal; In: Blue bag; Packing: Not packed',
  'my item shows its bag'
);

-- Who has it (ruling 2026-10-08).
select is(
  (select string_agg(s ->> 'title', ', ')
   from jsonb_array_elements(get_item(tests.item_id('Hair clip'))::jsonb -> 'sections') s),
  'Details, Cargo requests',
  'an item no one else has shows no Who has it'
);

select tests.act_as('Nour');
select create_item(name => 'Perfume (Dior)', description => 'The small bottle', visibility => 'shared',
                   copy_of => tests.item_id('Perfume', 'Mai'));
select tests.item_id('Perfume (Dior)') as dior_id \gset
update item set created_at = created_at + interval '2 minutes' where id = :'dior_id';
select tests.act_as('Rana');

select is(
  (select jsonb_agg(r - 'id' - 'emoji' - 'actions' order by n)
   from jsonb_array_elements(
          tests.section(get_item(tests.item_id('Perfume', 'Mai'))::jsonb, 'Who has it') -> 'rows')
        with ordinality as t (r, n)),
  jsonb_build_array(
    jsonb_build_object('title', 'Mai 🎀', 'subtitle', null,
                       'badges', '[{"label": "This one", "tone": "neutral"}]'::jsonb, 'open', null),
    jsonb_build_object('title', 'Nour', 'subtitle', 'Perfume (Dior) · The small bottle', 'badges', '[]'::jsonb,
                       'open', jsonb_build_object('detail', 'item', 'id', :'dior_id'::uuid))),
  'Who has it lists each shared copy in the order added; the others open their own copy, named when it differs'
);

select tests.act_as('Nour');
select update_item(:'dior_id', name => 'Perfume (Dior)', description => 'The small bottle',
                   type => 'personal', visibility => 'private');

select is(
  (select string_agg(s ->> 'title', ', ')
   from jsonb_array_elements(get_item(tests.item_id('Perfume', 'Mai'))::jsonb -> 'sections') s)
    || ' / ' || tests.titles(tests.section(get_item(:'dior_id')::jsonb, 'Who has it')),
  'Details, Cargo requests / Mai 🎀',
  'a copy made private leaves the list, and its owner still sees who else has it (BR-07a)'
);

select tests.act_as('Nour');

select tests.throws_error(
  format('select get_item(%L)', tests.item_id('Blue bag')),
  'NOT_FOUND', 'This item was deleted.',
  'a bag holding only private items is private (BR-10)'
);

select tests.act_as('Sara');
select create_item(name => 'Scarf', visibility => 'shared');
select move_to_container(tests.item_id('Scarf'), tests.item_id('Blue bag'));

select is(
  tests.titles(tests.section(get_item(tests.item_id('Blue bag'))::jsonb, 'Contents')),
  'Hair clip, Scarf',
  'a bag lists its contents'
);

select tests.act_as('Nour');

select is(
  (select d ->> 'subtitle' || ' / ' || tests.titles(tests.section(d, 'Contents'))
   from (select get_item(tests.item_id('Blue bag'))::jsonb as d) s),
  'Bag or box · Shared / Scarf',
  'a bag with a shared item is shared, but others see only its shared contents'
);

-- Cargo requests on an item: confirmed ones are public, the rest only
-- for the people involved.
select tests.act_as('Sara');
select send_request(tests.car_id('Bride'), 'cargo', 'ask', item_id => tests.item_id('Blue bag'),
                    pickup_type => 'bride_home');

select is(
  tests.action_ids(tests.row_titled(tests.section(get_item(tests.item_id('Blue bag'))::jsonb, 'Cargo requests'),
                                    'Blue bag in Bride''s car')),
  'cancel',
  'the sender sees her pending cargo request, with Cancel'
);

select tests.act_as('Nour');

select is(
  tests.titles(tests.section(get_item(tests.item_id('Blue bag'))::jsonb, 'Cargo requests')),
  '',
  'others don''t see a pending cargo request'
);

select tests.act_as('Bride');
select respond_to_request(tests.request_on(tests.car_id('Bride'), 'Blue bag'), true);
select tests.act_as('Nour');

select is(
  tests.row_titled(tests.section(get_item(tests.item_id('Blue bag'))::jsonb, 'Cargo requests'),
                   'Blue bag in Bride''s car') ->> 'subtitle',
  'To the hotel · Sara asked · Confirmed · Pickup: Bride''s home',
  'once confirmed, everyone sees it (BR-18)'
);

select * from finish();
rollback;
