-- claim_item, set_packed, move_to_container, release_claim
-- (contract Section 4, BR-02, BR-08 to BR-11).
begin;
\ir _helpers.psql

select plan(46);

select tests.reset_members();

select tests.act_as('Mai');
select create_item(name => 'Giveaways',   type => 'claimable');
select create_item(name => 'Gift box',    type => 'claimable');
select create_item(name => 'Flowers',     type => 'claimable');
select create_item(name => 'Cake topper', type => 'claimable',
                   vendor => '{"vendor_name": "Sweet Corner", "address": "9 Road 200"}');
select create_item(name => 'Tissues',     type => 'personal', visibility => 'shared');
select create_container(name => 'Mai bag');

select tests.act_as('Sara');
select create_item(name => 'Lipstick');
select create_container(name => 'Blue bag');
select create_container(name => 'Tote');

select tests.add_car('Nour', 'to_hotel') as nour_to_hotel \gset
select tests.add_car('Bride', 'hotel_to_venue') as bride_to_venue \gset
select tests.add_car('Mai', 'return_home') as mai_return \gset

-- ---------------------------------------------------------------------
-- claim_item
-- ---------------------------------------------------------------------

select has_function('public', 'claim_item', array['uuid']);

select tests.no_session();

select tests.throws_error(
  format('select claim_item(%L)', tests.item_id('Giveaways')),
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'claim_item without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Sara');

select tests.throws_error(
  format('select claim_item(%L)', tests.item_id('Tissues')),
  'NOT_CLAIMABLE', 'This item can''t be claimed.',
  'a personal item can''t be claimed'
);

select tests.throws_error(
  format('select claim_item(%L)', tests.item_id('Blue bag')),
  'NOT_CLAIMABLE', 'This item can''t be claimed.',
  'a bag can''t be claimed'
);

select tests.throws_error(
  format('select claim_item(%L)', gen_random_uuid()),
  'NOT_CLAIMABLE', 'This item can''t be claimed.',
  'an unknown item can''t be claimed'
);

select claim_item(tests.item_id('Giveaways'));

select is(
  tests.item_fields(tests.item_id('Giveaways')) ->> 'claimed_by', 'Sara',
  'any member can claim an unclaimed item (BR-08)'
);

select tests.act_as('Nour');

select tests.throws_error(
  format('select claim_item(%L)', tests.item_id('Giveaways')),
  'ALREADY_CLAIMED', 'Sara already claimed this.',
  'a claimed item can''t be claimed again, and the message names the claimer'
);

select tests.act_as('Sara');

select tests.throws_error(
  format('select claim_item(%L)', tests.item_id('Giveaways')),
  'ALREADY_CLAIMED', 'You already claimed this.',
  'claiming my own claim again says so'
);

select tests.act_as('Mai');
select claim_item(tests.item_id('Flowers'));

select is(
  tests.item_fields(tests.item_id('Flowers')) ->> 'claimed_by', 'Mai',
  'the owner can claim their own claimable item'
);

-- ---------------------------------------------------------------------
-- set_packed
-- ---------------------------------------------------------------------

select has_function('public', 'set_packed', array['uuid', 'boolean']);

select tests.no_session();

select tests.throws_error(
  format('select set_packed(%L, true)', tests.item_id('Lipstick')),
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'set_packed without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Sara');

select set_packed(tests.item_id('Lipstick'), true);

select is(
  (select is_packed from item where id = tests.item_id('Lipstick')), true,
  'the owner can mark a personal item packed (BR-09)'
);

select set_packed(tests.item_id('Lipstick'), false);

select is(
  (select is_packed from item where id = tests.item_id('Lipstick')), false,
  'and unpacked'
);

select set_packed(tests.item_id('Blue bag'), true);

select is(
  (select is_packed from item where id = tests.item_id('Blue bag')), true,
  'the owner can mark a bag packed'
);

select set_packed(tests.item_id('Giveaways'), true);

select is(
  (select is_packed from item where id = tests.item_id('Giveaways')), true,
  'the claimer can mark a claimable item packed'
);

select tests.act_as('Mai');

select tests.throws_error(
  format('select set_packed(%L, false)', tests.item_id('Giveaways')),
  'NOT_ALLOWED', 'You can''t change this.',
  'the owner can''t pack a claimable item someone else claimed'
);

select tests.throws_error(
  format('select set_packed(%L, true)', tests.item_id('Gift box')),
  'NOT_ALLOWED', 'You can''t change this.',
  'no one can pack an unclaimed item'
);

select tests.throws_error(
  format('select set_packed(%L, true)', tests.item_id('Lipstick')),
  'NOT_ALLOWED', 'You can''t change this.',
  'no one can pack another member''s item'
);

select tests.throws_error(
  format('select set_packed(%L, true)', gen_random_uuid()),
  'NOT_ALLOWED', 'You can''t change this.',
  'an unknown item can''t be packed'
);

-- ---------------------------------------------------------------------
-- move_to_container
-- ---------------------------------------------------------------------

select has_function('public', 'move_to_container', array['uuid', 'uuid']);

select tests.no_session();

select tests.throws_error(
  format('select move_to_container(%L, %L)', tests.item_id('Lipstick'), tests.item_id('Blue bag')),
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'move_to_container without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Sara');

select tests.add_cargo_request(:'nour_to_hotel', tests.item_id('Lipstick'), 'pending') as lipstick_pending \gset
select tests.add_cargo_request(:'bride_to_venue', tests.item_id('Lipstick'), 'confirmed') as lipstick_confirmed \gset
select tests.add_cargo_request(:'mai_return', tests.item_id('Lipstick'), 'declined') as lipstick_declined \gset

select move_to_container(tests.item_id('Lipstick'), tests.item_id('Blue bag'));

select is(
  tests.item_fields(tests.item_id('Lipstick')) ->> 'in', 'Blue bag',
  'I can put my item in my bag (BR-10)'
);

select is(
  array[tests.request_state(:'lipstick_pending'), tests.request_state(:'lipstick_confirmed')],
  array['cancelled/auto', 'cancelled/auto'],
  'moving an item into a bag cancels its pending and confirmed cargo requests (BR-11)'
);

select is(
  tests.request_state(:'lipstick_declined'), 'declined',
  'its declined requests stay declined'
);

select move_to_container(tests.item_id('Giveaways'), tests.item_id('Blue bag'));

select is(
  tests.item_fields(tests.item_id('Giveaways')) ->> 'in', 'Blue bag',
  'I can put an item I claimed in my bag'
);

select move_to_container(tests.item_id('Lipstick'), tests.item_id('Tote'));

select is(
  tests.item_fields(tests.item_id('Lipstick')) ->> 'in', 'Tote',
  'I can move an item from one of my bags to another'
);

select tests.throws_error(
  format('select move_to_container(%L, %L)', tests.item_id('Lipstick'), tests.item_id('Mai bag')),
  'NOT_ALLOWED', 'You can''t change this.',
  'I can''t put my item in someone else''s bag'
);

select tests.throws_error(
  format('select move_to_container(%L, %L)', tests.item_id('Lipstick'), tests.item_id('Giveaways')),
  'NOT_A_CONTAINER', 'Pick a bag or box.',
  'the target must be a bag or box'
);

select tests.throws_error(
  format('select move_to_container(%L, %L)', tests.item_id('Lipstick'), gen_random_uuid()),
  'NOT_A_CONTAINER', 'Pick a bag or box.',
  'an unknown target is not a bag'
);

select tests.throws_error(
  format('select move_to_container(%L, %L)', tests.item_id('Tote'), tests.item_id('Blue bag')),
  'NO_NESTING', 'A bag can''t go inside another bag.',
  'a bag can''t go inside another bag'
);

select tests.act_as('Nour');

select tests.throws_error(
  format('select move_to_container(%L, null)', tests.item_id('Lipstick')),
  'NOT_ALLOWED', 'You can''t change this.',
  'I can''t move someone else''s item'
);

select tests.throws_error(
  format('select move_to_container(%L, null)', gen_random_uuid()),
  'NOT_ALLOWED', 'You can''t change this.',
  'an unknown item can''t be moved'
);

select tests.act_as('Sara');
select move_to_container(tests.item_id('Lipstick'), null);

select is(
  tests.item_fields(tests.item_id('Lipstick')) ->> 'in', null,
  'a null container takes the item out of its bag'
);

select claim_item(tests.item_id('Gift box'));
select tests.act_as('Mai');
select move_to_container(tests.item_id('Gift box'), tests.item_id('Mai bag'));

select is(
  tests.item_fields(tests.item_id('Gift box')) ->> 'in', 'Mai bag',
  'the owner can put an item someone else claimed in their own bag (ERD)'
);

-- ---------------------------------------------------------------------
-- release_claim
-- ---------------------------------------------------------------------

select has_function('public', 'release_claim', array['uuid']);

select tests.no_session();

select tests.throws_error(
  format('select release_claim(%L)', tests.item_id('Giveaways')),
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'release_claim without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Mai');

select tests.throws_error(
  format('select release_claim(%L)', tests.item_id('Giveaways')),
  'NOT_ALLOWED', 'You can''t change this.',
  'no one can release someone else''s claim, not even the owner (BR-02)'
);

select tests.act_as('Nour');

select tests.throws_error(
  format('select release_claim(%L)', tests.item_id('Cake topper')),
  'NOT_ALLOWED', 'You can''t change this.',
  'an unclaimed item has no claim to release'
);

select tests.throws_error(
  format('select release_claim(%L)', gen_random_uuid()),
  'NOT_ALLOWED', 'You can''t change this.',
  'an unknown item has no claim to release'
);

select tests.act_as('Sara');
select claim_item(tests.item_id('Cake topper'));

select tests.add_cargo_request(:'nour_to_hotel', tests.item_id('Cake topper'), 'pending') as topper_pending \gset
select tests.add_cargo_request(:'bride_to_venue', tests.item_id('Cake topper'), 'confirmed') as topper_confirmed \gset
select tests.add_cargo_request(:'mai_return', tests.item_id('Cake topper'), 'declined') as topper_declined \gset

select release_claim(tests.item_id('Cake topper'));

select is(
  tests.item_fields(tests.item_id('Cake topper')) ->> 'claimed_by', null,
  'the claimer can release the claim (BR-08)'
);

select is(
  array[tests.request_state(:'topper_pending'), tests.request_state(:'topper_confirmed')],
  array['cancelled/auto', 'cancelled/auto'],
  'releasing a claim cancels the item''s pending and confirmed cargo requests (auto)'
);

select is(
  tests.request_state(:'topper_declined'), 'declined',
  'its declined requests stay declined'
);

select is(
  tests.vendor_fields(tests.item_id('Cake topper')) ->> 'vendor_name', 'Sweet Corner',
  'releasing a claim keeps the vendor details'
);

select release_claim(tests.item_id('Giveaways'));

select is(
  tests.item_fields(tests.item_id('Giveaways')) ->> 'in', null,
  'releasing a claim takes the item out of my bag'
);

select release_claim(tests.item_id('Gift box'));

select is(
  tests.item_fields(tests.item_id('Gift box')) ->> 'in', 'Mai bag',
  'an item in its owner''s bag stays there when the claimer releases it'
);

select tests.throws_error(
  format('select release_claim(%L)', tests.item_id('Giveaways')),
  'NOT_ALLOWED', 'You can''t change this.',
  'a released claim can''t be released again'
);

select * from finish();
rollback;
