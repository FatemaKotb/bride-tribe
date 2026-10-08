-- create_item, create_container, update_item, delete_item
-- (contract Section 4, BR-04 to BR-07b, BR-10, BR-29 to BR-31).
begin;
\ir _helpers.psql

select plan(68);

select tests.reset_members();

select hasnt_column('public', 'item', 'tags', 'items have no tags (ruling 2026-10-08)');

-- ---------------------------------------------------------------------
-- create_item
-- ---------------------------------------------------------------------

select has_function('public', 'create_item', array['text', 'text', 'text', 'integer', 'item_type', 'item_visibility', 'jsonb', 'uuid']);

select tests.no_session();

select tests.throws_error(
  $$ select create_item(name => 'Perfume') $$,
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'create_item without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Sara');

select create_item(
  name => '  Perfume ', emoji => '📿', description => '  ', quantity => 2,
  type => 'personal', visibility => 'shared'
);

select is(
  tests.item_fields(tests.item_id('Perfume')),
  '{"kind": "item", "owner": "Sara", "name": "Perfume", "emoji": "📿", "description": null,
    "quantity": 2, "visibility": "shared",
    "type": "personal", "claimed_by": null, "in": null, "packed": false}',
  'create_item saves my item, trimming text'
);

select create_item(name => 'Hair clip');

select is(
  tests.item_fields(tests.item_id('Hair clip')),
  '{"kind": "item", "owner": "Sara", "name": "Hair clip", "emoji": null, "description": null,
    "quantity": null, "visibility": "private",
    "type": "personal", "claimed_by": null, "in": null, "packed": false}',
  'create_item defaults to a private personal item'
);

select isnt(
  (select group_id from item where id = tests.item_id('Perfume')),
  (select group_id from item where id = tests.item_id('Hair clip')),
  'each new item starts its own group'
);

select create_item(name => 'Giveaways', type => 'claimable', visibility => 'private');

select is(
  (select visibility::text from item where id = tests.item_id('Giveaways')), 'shared',
  'claimable items are always shared (BR-06)'
);

select tests.throws_error(
  $$ select create_item(name => null) $$,
  'NAME_REQUIRED', 'Please give the item a name.',
  'create_item needs a name'
);

select tests.throws_error(
  $$ select create_item(name => '   ') $$,
  'NAME_REQUIRED', 'Please give the item a name.',
  'a blank name is no name'
);

select tests.throws_error(
  $$ select create_item(name => 'Pins', quantity => 0) $$,
  'INVALID_NUMBER', 'Quantity must be at least 1.',
  'quantity must be at least 1'
);

select tests.throws_error(
  $$ select create_item(name => 'Pins', vendor => '{"vendor_name": "Ahmed"}') $$,
  'VENDOR_NOT_ALLOWED', 'Vendor details can only be added to claimable items.',
  'a personal item can''t have vendor details'
);

select create_item(name => 'Pins', vendor => '{"vendor_name": "", "service": " ", "amount_egp": null}');

select is(
  (select count(*)::int from vendor_details where item_id = tests.item_id('Pins')), 0,
  'an empty vendor group means no vendor details'
);

-- The form starts the amount at 0, so a claimable item saved without
-- touching the vendor group sends just that.
select create_item(name => 'Balloons', type => 'claimable',
                   vendor => '{"vendor_name": null, "service": null, "amount_egp": 0}');

select is(
  (select count(*)::int from vendor_details where item_id = tests.item_id('Balloons')), 0,
  'an amount of 0 on its own means no vendor details (ruling)'
);

select create_item(name => 'Henna artist', type => 'claimable',
                   vendor => '{"vendor_name": "Nada", "amount_egp": 0}');

select is(
  (select amount_egp from vendor_details where item_id = tests.item_id('Henna artist')), 0::numeric,
  'with a vendor name, an amount of 0 is saved'
);

select create_item(
  name => 'Photographer', type => 'claimable',
  vendor => '{"vendor_name": " Ahmed Hassan ", "service": "Photographer",
              "phone": "01012345678", "address": "", "expected_time": "17:00",
              "amount_egp": 2000, "details": "Bring the shot list"}'
);

select is(
  tests.vendor_fields(tests.item_id('Photographer')),
  '{"vendor_name": "Ahmed Hassan", "service": "Photographer", "phone": "01012345678",
    "address": null, "expected_time": "17:00:00", "amount_egp": 2000,
    "details": "Bring the shot list"}',
  'create_item saves vendor details on a claimable item (BR-29)'
);

select tests.throws_error(
  $$ select create_item(name => 'Makeup artist', type => 'claimable',
                        vendor => '{"service": "Makeup"}') $$,
  'NAME_REQUIRED', 'Please add the vendor''s name.',
  'vendor details need the vendor''s name'
);

select is(
  (select count(*)::int from item where name = 'Makeup artist'), 0,
  'a rejected item is not saved'
);

select tests.throws_error(
  $$ select create_item(name => 'Makeup artist', type => 'claimable',
                        vendor => '{"vendor_name": "Mona", "amount_egp": -5}') $$,
  'INVALID_NUMBER', 'The amount can''t be negative.',
  'the vendor amount can''t be negative'
);

-- ---------------------------------------------------------------------
-- create_container, and editing one
-- ---------------------------------------------------------------------

select has_function('public', 'create_container', array['text', 'text']);

select tests.no_session();

select tests.throws_error(
  $$ select create_container(name => 'Blue bag') $$,
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'create_container without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Sara');
select create_container(name => ' Blue bag ', emoji => '👜');

select is(
  tests.item_fields(tests.item_id('Blue bag')),
  '{"kind": "container", "owner": "Sara", "name": "Blue bag", "emoji": "👜", "description": null,
    "quantity": null, "visibility": null,
    "type": null, "claimed_by": null, "in": null, "packed": false}',
  'create_container makes a bag that belongs to me (BR-10)'
);

select tests.throws_error(
  $$ select create_container(name => ' ') $$,
  'NAME_REQUIRED', 'Please give the bag or box a name.',
  'a bag needs a name'
);

select update_item(tests.item_id('Blue bag'), name => 'Blue bag', emoji => '🎒');

select is(
  (select emoji from item where id = tests.item_id('Blue bag')), '🎒',
  'update_item edits a container''s name and emoji'
);

select tests.throws_error(
  format('select update_item(%L, name => %L)', tests.item_id('Blue bag'), ''),
  'NAME_REQUIRED', 'Please give the bag or box a name.',
  'an edited bag still needs a name'
);

select tests.throws_error(
  format('select update_item(%L, name => %L, vendor => %L)',
         tests.item_id('Blue bag'), 'Blue bag', '{"vendor_name": "Ahmed"}'),
  'VENDOR_NOT_ALLOWED', 'Vendor details can only be added to claimable items.',
  'a bag can''t have vendor details'
);

-- ---------------------------------------------------------------------
-- Copies: "Add to my list" (BR-07, BR-07a)
-- ---------------------------------------------------------------------

select tests.act_as('Mai');

select create_item(
  name => 'Perfume', emoji => '📿', type => 'personal', visibility => 'shared',
  copy_of => tests.item_id('Perfume', 'Sara')
);

select is(
  tests.item_fields(tests.item_id('Perfume', 'Mai')),
  '{"kind": "item", "owner": "Mai", "name": "Perfume", "emoji": "📿", "description": null,
    "quantity": null, "visibility": "shared",
    "type": "personal", "claimed_by": null, "in": null, "packed": false}',
  'a copy is a new item of mine, with the fields as submitted'
);

select is(
  (select group_id from item where id = tests.item_id('Perfume', 'Mai')),
  (select group_id from item where id = tests.item_id('Perfume', 'Sara')),
  'a copy joins the original''s group'
);

select tests.throws_error(
  format('select create_item(name => %L, copy_of => %L)', 'Hair clip', tests.item_id('Hair clip')),
  'COPY_NOT_ALLOWED', 'This item can''t be copied.',
  'a private item can''t be copied'
);

select tests.throws_error(
  format('select create_item(name => %L, copy_of => %L)', 'Giveaways', tests.item_id('Giveaways')),
  'COPY_NOT_ALLOWED', 'This item can''t be copied.',
  'a claimable item can''t be copied'
);

select tests.throws_error(
  format('select create_item(name => %L, copy_of => %L)', 'Blue bag', tests.item_id('Blue bag')),
  'COPY_NOT_ALLOWED', 'This item can''t be copied.',
  'a bag can''t be copied'
);

select tests.throws_error(
  format('select create_item(name => %L, copy_of => %L)', 'Ghost', gen_random_uuid()),
  'NOT_FOUND', 'This item was deleted.',
  'copying an item that was deleted raises NOT_FOUND'
);

select tests.throws_error(
  format('select create_item(name => %L, copy_of => %L)', 'Perfume', tests.item_id('Perfume', 'Sara')),
  'ALREADY_ON_YOUR_LIST', 'This is already on your list.',
  'I can''t add an item twice'
);

update item set visibility = 'private' where id = tests.item_id('Perfume', 'Mai');

select tests.throws_error(
  format('select create_item(name => %L, copy_of => %L)', 'Perfume', tests.item_id('Perfume', 'Sara')),
  'ALREADY_ON_YOUR_LIST', 'This is already on your list.',
  'a copy I made private still counts as on my list'
);

update item set visibility = 'shared' where id = tests.item_id('Perfume', 'Mai');

select tests.act_as('Sara');

select tests.throws_error(
  format('select create_item(name => %L, copy_of => %L)', 'Perfume', tests.item_id('Perfume', 'Mai')),
  'ALREADY_ON_YOUR_LIST', 'This is already on your list.',
  'the original''s owner already has it'
);

select tests.act_as('Nour');

select create_item(
  name => 'Perfume', type => 'personal', visibility => 'shared',
  copy_of => tests.item_id('Perfume', 'Mai')
);

select is(
  (select group_id from item where id = tests.item_id('Perfume', 'Nour')),
  (select group_id from item where id = tests.item_id('Perfume', 'Sara')),
  'copying a copy joins the same group'
);

-- ---------------------------------------------------------------------
-- update_item
-- ---------------------------------------------------------------------

select has_function('public', 'update_item', array['uuid', 'text', 'text', 'text', 'integer', 'item_type', 'item_visibility', 'jsonb']);

select tests.no_session();

select tests.throws_error(
  format('select update_item(%L, name => %L)', tests.item_id('Hair clip'), 'Hair clip'),
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'update_item without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Mai');

select tests.throws_error(
  format('select update_item(%L, name => %L)', tests.item_id('Perfume', 'Sara'), 'Mine now'),
  'NOT_ALLOWED', 'You can''t change this.',
  'only the owner can edit an item'
);

select tests.throws_error(
  format('select update_item(%L, name => %L)', gen_random_uuid(), 'Ghost'),
  'NOT_FOUND', 'This item was deleted.',
  'editing an item that was deleted raises NOT_FOUND'
);

update item set claimed_by_id = tests.member_id('Mai') where id = tests.item_id('Photographer');

select tests.throws_error(
  format('select update_item(%L, name => %L, type => %L, vendor => %L)',
         tests.item_id('Photographer'), 'Photographer', 'claimable',
         '{"vendor_name": "Someone else"}'),
  'NOT_ALLOWED', 'You can''t change this.',
  'not even the claimer can edit vendor details, only the owner (ruling, overrides BR-31)'
);

select tests.act_as('Sara');

select update_item(
  tests.item_id('Perfume', 'Sara'),
  name => 'Perfume (Dior)', emoji => '🌸', description => 'The small bottle',
  quantity => 1, type => 'personal', visibility => 'shared'
);

select is(
  tests.item_fields(tests.item_id('Perfume (Dior)')),
  '{"kind": "item", "owner": "Sara", "name": "Perfume (Dior)", "emoji": "🌸",
    "description": "The small bottle", "quantity": 1, "visibility": "shared",
    "type": "personal", "claimed_by": null, "in": null, "packed": false}',
  'the owner can change every field'
);

select is(
  (select group_id from item where id = tests.item_id('Perfume (Dior)')),
  (select group_id from item where id = tests.item_id('Perfume', 'Mai')),
  'editing an item keeps it in its group (BR-07a)'
);

select is(
  (select count(*)::int from item where name = 'Perfume'), 2,
  'editing one copy leaves the others alone'
);

select tests.throws_error(
  format('select update_item(%L, name => %L)', tests.item_id('Hair clip'), ' '),
  'NAME_REQUIRED', 'Please give the item a name.',
  'an edited item still needs a name'
);

select tests.throws_error(
  format('select update_item(%L, name => %L, quantity => -1)', tests.item_id('Hair clip'), 'Hair clip'),
  'INVALID_NUMBER', 'Quantity must be at least 1.',
  'an edited quantity must be at least 1'
);

select tests.throws_error(
  format('select update_item(%L, name => %L, type => %L, vendor => %L)',
         tests.item_id('Hair clip'), 'Hair clip', 'personal', '{"vendor_name": "Ahmed"}'),
  'VENDOR_NOT_ALLOWED', 'Vendor details can only be added to claimable items.',
  'an edited personal item can''t get vendor details'
);

-- Personal to claimable: the item is unclaimed, so its cargo requests go.
select tests.add_car('Nour', 'to_hotel') as nour_to_hotel \gset
select tests.add_car('Bride', 'hotel_to_venue') as bride_to_venue \gset
select tests.add_car('Mai', 'return_home') as mai_return \gset

select tests.add_cargo_request(:'nour_to_hotel', tests.item_id('Hair clip'), 'pending') as clip_pending \gset
select tests.add_cargo_request(:'bride_to_venue', tests.item_id('Hair clip'), 'confirmed') as clip_confirmed \gset

select update_item(tests.item_id('Hair clip'), name => 'Hair clip', type => 'claimable', visibility => 'private');

select is(
  (select type::text || '/' || visibility::text from item where id = tests.item_id('Hair clip')),
  'claimable/shared',
  'an item made claimable becomes shared'
);

select is(
  array[tests.request_state(:'clip_pending'), tests.request_state(:'clip_confirmed')],
  array['cancelled/auto', 'cancelled/auto'],
  'making an item claimable cancels its cargo requests: it has no cargo owner until claimed (BR-24)'
);

-- An item in a bag that has a car, made claimable.
select create_item(name => 'Scarf');
select move_to_container(tests.item_id('Scarf'), tests.item_id('Blue bag'));
select tests.add_cargo_request(:'bride_to_venue', tests.item_id('Blue bag'), 'confirmed') as bag_confirmed \gset

select update_item(tests.item_id('Scarf'), name => 'Scarf', type => 'claimable');

select is(
  tests.item_fields(tests.item_id('Scarf')) ->> 'in', null,
  'an item made claimable leaves its bag: no one handles it until it''s claimed (ruling)'
);

select is(
  tests.request_state(:'bag_confirmed'), 'confirmed',
  'the bag keeps its car'
);

-- Claimable to personal: only unclaimed and without vendor details.
update item set claimed_by_id = tests.member_id('Nour') where id = tests.item_id('Giveaways');

select tests.throws_error(
  format('select update_item(%L, name => %L, type => %L)', tests.item_id('Giveaways'), 'Giveaways', 'personal'),
  'TYPE_CHANGE_NOT_ALLOWED', 'Release the claim and remove the vendor details before making this personal.',
  'a claimed item can''t become personal'
);

update item set claimed_by_id = null where id = tests.item_id('Photographer');

select tests.throws_error(
  format('select update_item(%L, name => %L, type => %L)', tests.item_id('Photographer'), 'Photographer', 'personal'),
  'TYPE_CHANGE_NOT_ALLOWED', 'Release the claim and remove the vendor details before making this personal.',
  'an item with vendor details can''t become personal'
);

update item set claimed_by_id = null where id = tests.item_id('Giveaways');

select update_item(tests.item_id('Giveaways'), name => 'Giveaways', type => 'personal', visibility => 'private');

select is(
  (select type::text || '/' || visibility::text from item where id = tests.item_id('Giveaways')),
  'personal/private',
  'an unclaimed item without vendor details can become personal'
);

-- Vendor details, edited by the owner.
select update_item(
  tests.item_id('Photographer'), name => 'Photographer', type => 'claimable',
  vendor => '{"vendor_name": "Ahmed Hassan", "service": "Photographer", "amount_egp": 2500}'
);

select is(
  tests.vendor_fields(tests.item_id('Photographer')),
  '{"vendor_name": "Ahmed Hassan", "service": "Photographer", "phone": null, "address": null,
    "expected_time": null, "amount_egp": 2500, "details": null}',
  'the owner can edit vendor details; the submitted group replaces the old one'
);

select update_item(tests.item_id('Photographer'), name => 'Photographer', type => 'claimable');

select is(
  (select count(*)::int from vendor_details where item_id = tests.item_id('Photographer')), 0,
  'an empty vendor group removes the vendor details'
);

-- ---------------------------------------------------------------------
-- delete_item
-- ---------------------------------------------------------------------

select has_function('public', 'delete_item', array['uuid']);

select create_item(name => 'Shoes');
select create_item(name => 'Lipstick');
select create_container(name => 'Tote');
select move_to_container(tests.item_id('Lipstick'), tests.item_id('Tote'));

select tests.add_cargo_request(:'nour_to_hotel', tests.item_id('Shoes'), 'pending') as shoes_pending \gset
select tests.add_cargo_request(:'bride_to_venue', tests.item_id('Shoes'), 'confirmed') as shoes_confirmed \gset
select tests.add_cargo_request(:'mai_return', tests.item_id('Shoes'), 'declined') as shoes_declined \gset
select tests.add_cargo_request(:'nour_to_hotel', tests.item_id('Shoes'), 'cancelled') as shoes_cancelled \gset
select tests.add_cargo_request(:'nour_to_hotel', tests.item_id('Tote'), 'pending') as tote_pending \gset

select tests.no_session();

select tests.throws_error(
  format('select delete_item(%L)', tests.item_id('Shoes')),
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'delete_item without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Mai');

select tests.throws_error(
  format('select delete_item(%L)', tests.item_id('Shoes')),
  'NOT_ALLOWED', 'You can''t change this.',
  'only the owner can delete an item'
);

select tests.throws_error(
  format('select delete_item(%L)', gen_random_uuid()),
  'NOT_FOUND', 'This item was deleted.',
  'deleting an item that was already deleted raises NOT_FOUND'
);

select tests.act_as('Sara');
select delete_item(tests.item_id('Shoes'));

select is(
  (select count(*)::int from item where name = 'Shoes'), 0,
  'delete_item deletes my item'
);

select is(
  array[tests.request_state(:'shoes_pending'), tests.request_state(:'shoes_confirmed')],
  array['cancelled/auto', 'cancelled/auto'],
  'deleting an item cancels its pending and confirmed cargo requests (auto)'
);

select is(
  (select count(*)::int from request
   where id in (:'shoes_pending', :'shoes_confirmed') and item_id is null),
  2,
  'the cancelled requests stay, without their item, so car owners still see them'
);

select is(
  tests.request_state(:'shoes_declined'), null,
  'deleting an item deletes its declined requests (ruling)'
);

select is(
  tests.request_state(:'shoes_cancelled'), 'cancelled/by_sender',
  'requests that were already cancelled keep their reason'
);

select delete_item(tests.item_id('Tote'));

select is(
  tests.item_fields(tests.item_id('Lipstick')) ->> 'in', null,
  'deleting a bag moves its contents out'
);

select is(
  tests.request_state(:'tote_pending'), 'cancelled/auto',
  'deleting a bag cancels its cargo requests'
);

select delete_item(tests.item_id('Perfume (Dior)'));

select is(
  (select count(distinct group_id)::int || ' group, ' || count(*)::int || ' copies'
   from item where name = 'Perfume'),
  '1 group, 2 copies',
  'deleting the original leaves the group to its copies (BR-07b)'
);

select update_item(
  tests.item_id('Photographer'), name => 'Photographer', type => 'claimable',
  vendor => '{"vendor_name": "Ahmed Hassan"}'
);
select tests.item_id('Photographer') as photographer_id \gset
select delete_item(:'photographer_id');

select is(
  (select count(*)::int from vendor_details where item_id = :'photographer_id'), 0,
  'deleting an item deletes its vendor details'
);

select * from finish();
rollback;
