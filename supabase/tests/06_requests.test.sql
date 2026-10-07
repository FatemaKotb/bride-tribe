-- send_request, respond_to_request, cancel_request, leave_car
-- (contract Section 4, BR-05, BR-11, BR-20 to BR-25).
begin;
\ir _helpers.psql

select plan(66);

select tests.reset_members();
insert into member (name, role) values
  ('Rana', 'bridesmaid'), ('Laila', 'bridesmaid'), ('Hana', 'bridesmaid'), ('Dina', 'bridesmaid');

-- Cars. To the hotel: Sara (2 seats), Mai, Dina. Hotel to venue: Bride
-- (1 seat, taken by Laila), Nour, Rana. Return home: Hana's, withdrawn.
select tests.add_car('Sara') as sara_car \gset
select tests.add_car('Mai') as mai_car \gset
select tests.add_car('Dina') as dina_car \gset
select tests.add_car('Bride', 'hotel_to_venue') as bride_car \gset
select tests.add_car('Nour', 'hotel_to_venue') as nour_venue \gset
select tests.add_car('Rana', 'hotel_to_venue') as rana_venue \gset
select tests.add_car('Hana', 'return_home') as gone_car \gset
update car set seats = 2 where id = :'sara_car';
update car set seats = 1 where id = :'bride_car';
update car set withdrawn_at = now() where id = :'gone_car';
select tests.add_passenger_request(:'bride_car', 'Laila', 'confirmed');

-- Items. Blue bag is shared because it holds the shared Scarf.
select tests.act_as('Sara');
select create_item(name => 'Shoes', visibility => 'shared');
select create_item(name => 'Hair clip');
select create_item(name => 'Lipstick');
select create_item(name => 'Scarf', visibility => 'shared');
select create_container(name => 'Blue bag');
select create_container(name => 'Tote');
select move_to_container(tests.item_id('Lipstick'), tests.item_id('Blue bag'));
select move_to_container(tests.item_id('Scarf'), tests.item_id('Blue bag'));

select tests.act_as('Mai');
select create_item(name => 'Giveaways', type => 'claimable');
select create_item(name => 'Cake', type => 'claimable');
select create_item(name => 'Cake topper', type => 'claimable',
                   vendor => '{"vendor_name": "Sweet Corner", "address": "9 Road 200"}');
select create_item(name => 'Diary');

select tests.act_as('Sara');
select claim_item(tests.item_id('Giveaways'));
select tests.act_as('Nour');
select claim_item(tests.item_id('Cake topper'));

-- ---------------------------------------------------------------------
-- send_request: passengers
-- ---------------------------------------------------------------------

select has_function('public', 'send_request', array[
  'uuid', 'request_kind', 'request_direction', 'uuid', 'uuid', 'pickup_type', 'text',
  'time without time zone']);

select tests.no_session();

select tests.throws_error(
  format('select send_request(%L, %L, %L, passenger_id => %L)',
         :'sara_car', 'passenger', 'ask', tests.member_id('Nour')),
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'send_request without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Nour');

select tests.throws_error(
  format('select send_request(%L, %L, %L, passenger_id => %L)',
         gen_random_uuid(), 'passenger', 'ask', tests.member_id('Nour')),
  'NOT_FOUND', 'This car no longer exists.',
  'asking an unknown car raises NOT_FOUND'
);

select send_request(:'sara_car', 'passenger', 'ask', passenger_id => tests.member_id('Nour'));

select is(
  tests.request_fields(tests.request_on(:'sara_car', 'Nour')),
  '{"car": "Sara", "trip": "to_hotel", "direction": "ask", "kind": "passenger",
    "sent_by": "Nour", "passenger": "Nour", "item": null, "state": "pending",
    "cancel_reason": null, "pickup_type": null, "pickup_address": null, "ready_at": null}',
  'a passenger asks to ride a car (BR-20)'
);

select tests.throws_error(
  format('select send_request(%L, %L, %L, passenger_id => %L)',
         :'sara_car', 'passenger', 'ask', tests.member_id('Nour')),
  'DUPLICATE_REQUEST', 'There''s already a pending request for this.',
  'one pending request per passenger and car'
);

select tests.throws_error(
  format('select send_request(%L, %L, %L, passenger_id => %L)',
         :'mai_car', 'passenger', 'ask', tests.member_id('Rana')),
  'NOT_ALLOWED', 'You can''t change this.',
  'an Ask is for a seat for me, not someone else'
);

select tests.throws_error(
  format('select send_request(%L, %L, %L, passenger_id => %L)',
         :'mai_car', 'passenger', 'ask', gen_random_uuid()),
  'UNKNOWN_MEMBER', 'We couldn''t find that name.',
  'the passenger must be a member'
);

select tests.throws_error(
  format('select send_request(%L, %L, %L, passenger_id => %L)',
         :'gone_car', 'passenger', 'ask', tests.member_id('Nour')),
  'CAR_WITHDRAWN', 'This car is no longer available.',
  'a withdrawn car takes no requests'
);

select tests.throws_error(
  format('select send_request(%L, %L, %L, passenger_id => %L)',
         :'bride_car', 'passenger', 'ask', tests.member_id('Nour')),
  'CAR_FULL', 'Bride''s car has no free seats.',
  'no one can ask for a seat in a full car (BR-23)'
);

select tests.act_as('Bride');

select tests.throws_error(
  format('select send_request(%L, %L, %L, passenger_id => %L)',
         :'bride_car', 'passenger', 'offer', tests.member_id('Nour')),
  'CAR_FULL', 'Your car has no free seats.',
  'and no one can offer a seat in a full car'
);

select tests.act_as('Laila');

select tests.throws_error(
  format('select send_request(%L, %L, %L, passenger_id => %L)',
         :'nour_venue', 'passenger', 'ask', tests.member_id('Laila')),
  'ALREADY_CONFIRMED_ON_TRIP', 'You already have a ride on this trip.',
  'a confirmed passenger can''t ask another car on the same trip (BR-22)'
);

select tests.act_as('Nour');

select tests.throws_error(
  format('select send_request(%L, %L, %L, passenger_id => %L)',
         :'nour_venue', 'passenger', 'offer', tests.member_id('Laila')),
  'ALREADY_CONFIRMED_ON_TRIP', 'Laila already has a ride on this trip.',
  'nor be offered a seat in one, and the message names her'
);

select tests.act_as('Sara');

select tests.throws_error(
  format('select send_request(%L, %L, %L, passenger_id => %L)',
         :'sara_car', 'passenger', 'ask', tests.member_id('Sara')),
  'OWN_CAR', 'That''s your own car.',
  'I can''t ask to ride my own car'
);

select tests.throws_error(
  format('select send_request(%L, %L, %L, passenger_id => %L)',
         :'sara_car', 'passenger', 'offer', tests.member_id('Sara')),
  'OWN_CAR', 'That''s your own car.',
  'I can''t offer myself a seat in my own car'
);

select send_request(:'sara_car', 'passenger', 'offer', passenger_id => tests.member_id('Rana'));

select is(
  tests.request_fields(tests.request_on(:'sara_car', 'Rana')) - 'car' - 'trip' - 'kind'
    - 'item' - 'cancel_reason' - 'pickup_type' - 'pickup_address' - 'ready_at',
  '{"direction": "offer", "sent_by": "Sara", "passenger": "Rana", "state": "pending"}',
  'a car owner offers a seat (BR-20)'
);

select tests.throws_error(
  format('select send_request(%L, %L, %L, passenger_id => %L)',
         :'mai_car', 'passenger', 'offer', tests.member_id('Rana')),
  'NOT_ALLOWED', 'You can''t change this.',
  'I can only offer seats in my own car'
);

-- ---------------------------------------------------------------------
-- send_request: cargo
-- ---------------------------------------------------------------------

select send_request(:'bride_car', 'cargo', 'ask', item_id => tests.item_id('Shoes'),
                    pickup_type => 'bride_home');

select is(
  tests.request_fields(tests.request_on(:'bride_car', 'Shoes')) ->> 'state', 'pending',
  'cargo can be sent to a full car: seats limit passengers only (ruling)'
);

select tests.throws_error(
  format('select send_request(%L, %L, %L, item_id => %L, pickup_type => %L)',
         :'mai_car', 'cargo', 'ask', tests.item_id('Lipstick'), 'bride_home'),
  'CARGO_IN_CONTAINER', 'This item travels with its bag. Send the bag instead.',
  'an item in a bag can''t be sent on its own (BR-11)'
);

select tests.throws_error(
  format('select send_request(%L, %L, %L, item_id => %L)',
         :'mai_car', 'cargo', 'ask', tests.item_id('Shoes')),
  'PICKUP_INVALID', 'Please choose a valid pickup location.',
  'cargo needs a pickup location'
);

select tests.throws_error(
  format('select send_request(%L, %L, %L, item_id => %L, pickup_type => %L, pickup_address => %L)',
         :'mai_car', 'cargo', 'ask', tests.item_id('Shoes'), 'custom', ' '),
  'PICKUP_INVALID', 'Please choose a valid pickup location.',
  'a custom pickup needs an address'
);

select tests.throws_error(
  format('select send_request(%L, %L, %L, item_id => %L, pickup_type => %L)',
         :'mai_car', 'cargo', 'ask', tests.item_id('Shoes'), 'vendor_address'),
  'PICKUP_INVALID', 'Please choose a valid pickup location.',
  'the vendor''s address is only for items whose vendor has one (BR-24)'
);

select send_request(:'mai_car', 'cargo', 'ask', item_id => tests.item_id('Blue bag'),
                    pickup_type => 'custom', pickup_address => ' 9 Road 200 ', ready_at => '10:00');

select is(
  tests.request_fields(tests.request_on(:'mai_car', 'Blue bag')),
  '{"car": "Mai", "trip": "to_hotel", "direction": "ask", "kind": "cargo",
    "sent_by": "Sara", "passenger": null, "item": "Blue bag", "state": "pending",
    "cancel_reason": null, "pickup_type": "custom", "pickup_address": "9 Road 200",
    "ready_at": "10:00:00"}',
  'a bag is sent as cargo with its pickup details (BR-24)'
);

select send_request(:'dina_car', 'cargo', 'ask', item_id => tests.item_id('Blue bag'),
                    pickup_type => 'bride_home', pickup_address => 'stray');

select is(
  tests.request_fields(tests.request_on(:'dina_car', 'Blue bag')) ->> 'pickup_address', null,
  'an address is kept only for a custom pickup'
);

select tests.act_as('Mai');

select tests.throws_error(
  format('select send_request(%L, %L, %L, item_id => %L, pickup_type => %L)',
         :'sara_car', 'cargo', 'ask', tests.item_id('Cake'), 'bride_home'),
  'UNCLAIMED_CARGO', 'Someone needs to claim this item first.',
  'unclaimed items can''t be cargo (BR-24)'
);

select tests.throws_error(
  format('select send_request(%L, %L, %L, item_id => %L, pickup_type => %L)',
         :'sara_car', 'cargo', 'ask', tests.item_id('Giveaways'), 'bride_home'),
  'NOT_YOUR_CARGO', 'You can only send your own items.',
  'the claimer sends a claimed item, not its owner (BR-24)'
);

select tests.act_as('Nour');

select tests.throws_error(
  format('select send_request(%L, %L, %L, item_id => %L, pickup_type => %L)',
         :'mai_car', 'cargo', 'ask', tests.item_id('Shoes'), 'bride_home'),
  'NOT_YOUR_CARGO', 'You can only send your own items.',
  'I can only ask a car to carry my own cargo'
);

select send_request(:'sara_car', 'cargo', 'ask', item_id => tests.item_id('Cake topper'),
                    pickup_type => 'vendor_address');

select is(
  tests.request_fields(tests.request_on(:'sara_car', 'Cake topper')) ->> 'pickup_type', 'vendor_address',
  'the claimer can send a vendor item for pickup at the vendor''s address'
);

-- Offers to carry, from the car owner.
select tests.act_as('Mai');

select send_request(:'mai_car', 'cargo', 'offer', item_id => tests.item_id('Shoes'),
                    pickup_type => 'bride_home');

select is(
  tests.request_fields(tests.request_on(:'mai_car', 'Shoes')) - 'car' - 'trip' - 'passenger'
    - 'cancel_reason' - 'pickup_address' - 'ready_at',
  '{"direction": "offer", "kind": "cargo", "sent_by": "Mai", "item": "Shoes",
    "state": "pending", "pickup_type": "bride_home"}',
  'a car owner offers to carry someone''s item'
);

select send_request(:'mai_car', 'cargo', 'offer', item_id => tests.item_id('Giveaways'),
                    pickup_type => 'bride_home');

select is(
  tests.request_fields(tests.request_on(:'mai_car', 'Giveaways')) ->> 'state', 'pending',
  'the item''s owner can offer to carry it when someone else claimed it'
);

select tests.throws_error(
  format('select send_request(%L, %L, %L, item_id => %L, pickup_type => %L)',
         :'mai_car', 'cargo', 'offer', tests.item_id('Hair clip'), 'bride_home'),
  'NOT_ALLOWED', 'You can''t change this.',
  'a car owner can''t offer to carry a private item she can''t see (BR-05)'
);

select tests.throws_error(
  format('select send_request(%L, %L, %L, item_id => %L, pickup_type => %L)',
         :'mai_car', 'cargo', 'offer', tests.item_id('Tote'), 'bride_home'),
  'NOT_ALLOWED', 'You can''t change this.',
  'nor a bag with no shared item in it (BR-10)'
);

select tests.throws_error(
  format('select send_request(%L, %L, %L, item_id => %L, pickup_type => %L)',
         :'mai_car', 'cargo', 'offer', tests.item_id('Blue bag'), 'bride_home'),
  'DUPLICATE_REQUEST', 'There''s already a pending request for this.',
  'a shared bag can be offered, but an Offer and an Ask for the same item and car are duplicates'
);

select tests.throws_error(
  format('select send_request(%L, %L, %L, item_id => %L, pickup_type => %L)',
         :'mai_car', 'cargo', 'offer', tests.item_id('Diary'), 'bride_home'),
  'OWN_CAR', 'That''s your own car.',
  'I can''t offer to carry my own item in my own car'
);

-- ---------------------------------------------------------------------
-- respond_to_request
-- ---------------------------------------------------------------------

select has_function('public', 'respond_to_request', array['uuid', 'boolean']);

select tests.request_on(:'sara_car', 'Nour') as nour_ask \gset
select tests.request_on(:'sara_car', 'Rana') as rana_offer \gset

select tests.no_session();

select tests.throws_error(
  format('select respond_to_request(%L, true)', :'nour_ask'),
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'respond_to_request without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Nour');

select tests.throws_error(
  format('select respond_to_request(%L, true)', gen_random_uuid()),
  'NOT_FOUND', 'This request no longer exists.',
  'answering an unknown request raises NOT_FOUND (ruling)'
);

select tests.throws_error(
  format('select respond_to_request(%L, true)', :'nour_ask'),
  'NOT_ALLOWED', 'You can''t change this.',
  'the sender can''t answer her own request'
);

select tests.act_as('Mai');

select tests.throws_error(
  format('select respond_to_request(%L, true)', :'nour_ask'),
  'NOT_ALLOWED', 'You can''t change this.',
  'only the responder answers: for an Ask, the car owner'
);

select tests.act_as('Rana');
select respond_to_request(:'rana_offer', false);

select is(
  tests.request_state(:'rana_offer'), 'declined',
  'the responder can decline: for an Offer, the passenger (BR-21)'
);

select tests.throws_error(
  format('select respond_to_request(%L, true)', :'rana_offer'),
  'NOT_PENDING', 'This request has already been answered.',
  'a request is answered once'
);

-- BR-22: Nour's other pending requests on the same trip.
select tests.act_as('Nour');
select send_request(:'mai_car', 'passenger', 'ask', passenger_id => tests.member_id('Nour'));
select send_request(:'rana_venue', 'passenger', 'ask', passenger_id => tests.member_id('Nour'));
select tests.act_as('Dina');
select send_request(:'dina_car', 'passenger', 'offer', passenger_id => tests.member_id('Nour'));

select tests.act_as('Sara');
select respond_to_request(:'nour_ask', true);

select is(
  tests.request_state(:'nour_ask'), 'confirmed',
  'the responder can accept, which confirms the request (BR-21)'
);

select is(
  array[tests.request_state(tests.request_on(:'mai_car', 'Nour')),
        tests.request_state(tests.request_on(:'dina_car', 'Nour'))],
  array['cancelled/auto', 'cancelled/auto'],
  'confirming cancels the passenger''s other pending requests on the trip, sent and received (BR-22)'
);

select is(
  tests.request_state(tests.request_on(:'rana_venue', 'Nour')), 'pending',
  'her requests on other trips stay'
);

-- BR-23: filling the last seat.
select tests.act_as('Hana');
select send_request(:'sara_car', 'passenger', 'ask', passenger_id => tests.member_id('Hana'));
select tests.act_as('Laila');
select send_request(:'sara_car', 'passenger', 'ask', passenger_id => tests.member_id('Laila'));

select tests.act_as('Sara');
select respond_to_request(tests.request_on(:'sara_car', 'Hana'), true);

select is(
  tests.request_state(tests.request_on(:'sara_car', 'Laila')), 'cancelled/auto',
  'filling the last seat cancels the car''s remaining pending passenger requests (BR-23)'
);

select is(
  tests.request_state(tests.request_on(:'sara_car', 'Cake topper')), 'pending',
  'pending cargo requests stay: cargo doesn''t use seats'
);

-- Accepting re-checks the rules, in case things changed.
select tests.add_passenger_request(:'sara_car', 'Rana', 'pending') as rana_late \gset

select tests.throws_error(
  format('select respond_to_request(%L, true)', :'rana_late'),
  'CAR_FULL', 'Your car has no free seats.',
  'accepting re-checks the free seats'
);

select tests.add_passenger_request(:'nour_venue', 'Laila', 'pending') as laila_late \gset
select tests.act_as('Nour');

select tests.throws_error(
  format('select respond_to_request(%L, true)', :'laila_late'),
  'ALREADY_CONFIRMED_ON_TRIP', 'Laila already has a ride on this trip.',
  'accepting re-checks one car per trip'
);

-- Cargo.
select tests.act_as('Mai');
select respond_to_request(tests.request_on(:'mai_car', 'Blue bag'), true);

select is(
  array[tests.request_state(tests.request_on(:'mai_car', 'Blue bag')),
        tests.request_state(tests.request_on(:'dina_car', 'Blue bag'))],
  array['confirmed', 'cancelled/auto'],
  'confirming cargo cancels its other pending requests on the trip (BR-22)'
);

select tests.throws_error(
  format('select respond_to_request(%L, true)', tests.request_on(:'mai_car', 'Giveaways')),
  'NOT_ALLOWED', 'You can''t change this.',
  'an Offer to carry a claimed item is answered by the claimer, not the item''s owner'
);

select tests.act_as('Sara');
select respond_to_request(tests.request_on(:'mai_car', 'Giveaways'), true);

select is(
  tests.request_state(tests.request_on(:'mai_car', 'Giveaways')), 'confirmed',
  'the claimer accepts the Offer'
);

-- ---------------------------------------------------------------------
-- cancel_request
-- ---------------------------------------------------------------------

select has_function('public', 'cancel_request', array['uuid']);

select tests.request_on(:'mai_car', 'Shoes') as shoes_offer \gset

select tests.no_session();

select tests.throws_error(
  format('select cancel_request(%L)', :'shoes_offer'),
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'cancel_request without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Sara');

select tests.throws_error(
  format('select cancel_request(%L)', gen_random_uuid()),
  'NOT_FOUND', 'This request no longer exists.',
  'cancelling an unknown request raises NOT_FOUND'
);

select tests.throws_error(
  format('select cancel_request(%L)', :'shoes_offer'),
  'NOT_ALLOWED', 'You can''t change this.',
  'only the sender can cancel; the responder declines instead'
);

select tests.act_as('Mai');
select cancel_request(:'shoes_offer');

select is(
  tests.request_state(:'shoes_offer'), 'cancelled/by_sender',
  'the sender can cancel a pending request (BR-21)'
);

select tests.throws_error(
  format('select cancel_request(%L)', :'shoes_offer'),
  'NOT_PENDING', 'This request has already been answered.',
  'only a pending request can be cancelled'
);

select tests.act_as('Nour');

select tests.throws_error(
  format('select cancel_request(%L)', :'nour_ask'),
  'NOT_PENDING', 'This request has already been answered.',
  'a confirmed request can''t be cancelled; the passenger leaves the car instead'
);

-- ---------------------------------------------------------------------
-- leave_car
-- ---------------------------------------------------------------------

select has_function('public', 'leave_car', array['uuid']);

select tests.no_session();

select tests.throws_error(
  format('select leave_car(%L)', :'nour_ask'),
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'leave_car without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Nour');

select tests.throws_error(
  format('select leave_car(%L)', gen_random_uuid()),
  'NOT_FOUND', 'This request no longer exists.',
  'leaving an unknown request raises NOT_FOUND'
);

select tests.act_as('Sara');

select tests.throws_error(
  format('select leave_car(%L)', :'nour_ask'),
  'NOT_ALLOWED', 'You can''t change this.',
  'a car owner can''t remove a confirmed passenger (BR-21)'
);

select tests.act_as('Laila');

select tests.throws_error(
  format('select leave_car(%L)', tests.request_on(:'sara_car', 'Laila')),
  'NOT_CONFIRMED', 'This ride isn''t confirmed.',
  'only a confirmed ride can be left'
);

select tests.act_as('Nour');
select leave_car(:'nour_ask');

select is(
  tests.request_state(:'nour_ask'), 'cancelled/left_car',
  'the passenger can leave the car (BR-21)'
);

select tests.act_as('Sara');
select respond_to_request(:'rana_late', true);

select is(
  tests.request_state(:'rana_late'), 'confirmed',
  'leaving frees the seat for someone else'
);

select tests.act_as('Mai');

select tests.throws_error(
  format('select leave_car(%L)', tests.request_on(:'mai_car', 'Giveaways')),
  'NOT_ALLOWED', 'You can''t change this.',
  'the item''s owner can''t take a claimed item out of a car; the claimer can'
);

select tests.act_as('Sara');
select leave_car(tests.request_on(:'mai_car', 'Giveaways'));

select is(
  tests.request_state(tests.request_on(:'mai_car', 'Giveaways')), 'cancelled/left_car',
  'the cargo''s owner can take it out of the car'
);

select * from finish();
rollback;
