-- list_cars and get_car: rows, details, and which actions each member
-- gets (contract Section 3, BR-14 to BR-23).
begin;
\ir _helpers.psql
\ir _read_helpers.psql

select plan(39);

select tests.wedding();

-- Return home: Rana leaves 23:30-00:30, Nour leaves 00:15-00:45.
select tests.act_as('Rana');
select register_car(trip => 'return_home', seats => 2, departure_earliest => '23:30',
                    departure_latest => '00:30', dropoff_areas => array['maadi', 'other']::area[],
                    dropoff_area_other => 'Nasr City', trunk_percent => 0);
select tests.act_as('Nour');
select register_car(trip => 'return_home', seats => 3, departure_earliest => '00:15',
                    departure_latest => '00:45', dropoff_areas => array['october']::area[],
                    trunk_percent => 25);

-- ---------------------------------------------------------------------
-- list_cars
-- ---------------------------------------------------------------------

select has_function('public', 'list_cars', array['jsonb']);

select tests.no_session();

select tests.throws_error(
  'select list_cars()',
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'list_cars without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Nour');

select is(
  tests.titles(list_cars()::jsonb),
  'Bride''s car, Sara''s car',
  'by default: To the hotel, in departure order'
);

select is(
  tests.row_titled(list_cars()::jsonb, 'Sara''s car') - 'id' - 'open' - 'actions',
  '{"emoji": "🚗", "title": "Sara''s car",
    "subtitle": "Maadi · leaves 9:00 am–10:30 am · 0 of 2 seats taken",
    "badges": [{"label": "Trunk 50%", "tone": "neutral"}]}',
  'a car row shows the area, the departure window, the seats, and the trunk space (BR-18)'
);

select is(
  tests.row_titled(list_cars()::jsonb, 'Sara''s car') -> 'open',
  jsonb_build_object('detail', 'car', 'id', tests.car_id('Sara')),
  'tapping a car opens it'
);

select is(
  list_cars()::jsonb -> 'actions' -> 0 -> 'form',
  '{"name": "car", "context": {"trip": "to_hotel"}}',
  'I''m coming with my car, for a trip where I have no car'
);

select is(
  tests.titles(list_cars('{"trip": ["return_home"]}')::jsonb),
  'Rana''s car, Your car',
  'Return home windows cross midnight, so 23:30 comes before 00:15 (ruling)'
);

select is(
  (select r ->> 'subtitle' || ' / ' || tests.badges(r)
   from (select tests.row_titled(list_cars('{"trip": ["return_home"]}')::jsonb, 'Rana''s car') as r) s),
  'Drops off in Maadi, Nasr City · leaves 11:30 pm–12:30 am · 0 of 2 seats taken / Trunk 0% (full)',
  'a Return home row shows its drop-off areas'
);

select is(
  tests.action_ids(list_cars('{"trip": ["return_home"]}')::jsonb),
  '',
  'no I''m coming with my car on a trip where I already have one'
);

select is(
  (select (f -> 'selected') || jsonb_build_array(tests.option_labels(f))
   from jsonb_array_elements(list_cars('{"trip": ["return_home"]}')::jsonb -> 'filters') f),
  '["return_home", "To the hotel, Hotel to venue, Return home"]',
  'the trip filter shows the chosen trip and every trip''s label'
);

select is(
  tests.titles(list_cars('{"trip": ["moon"]}')::jsonb),
  'Bride''s car, Sara''s car',
  'an unknown trip falls back to To the hotel'
);

select tests.act_as('Sara');

select is(
  tests.titles(list_cars()::jsonb),
  'Bride''s car, Your car',
  'my own car is Your car'
);

-- ---------------------------------------------------------------------
-- get_car: details
-- ---------------------------------------------------------------------

select has_function('public', 'get_car', array['uuid']);

select tests.no_session();

select tests.throws_error(
  format('select get_car(%L)', tests.car_id('Sara')),
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'get_car without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Rana');

select tests.throws_error(
  format('select get_car(%L)', gen_random_uuid()),
  'NOT_FOUND', 'This car no longer exists.',
  'an unknown car raises NOT_FOUND'
);

select is(
  get_car(tests.car_id('Sara'))::jsonb - 'sections' - 'actions',
  '{"emoji": "🚗", "title": "Sara''s car", "subtitle": "To the hotel"}',
  'a car''s heading'
);

select is(
  (select string_agg(s ->> 'title', ', ') from jsonb_array_elements(get_car(tests.car_id('Sara'))::jsonb -> 'sections') s),
  'Details, Stops, Notes, Passengers, Cargo',
  'a To the hotel car has details, stops, notes, passengers, and cargo'
);

select is(
  tests.pairs_text(tests.section(get_car(tests.car_id('Sara'))::jsonb, 'Details')),
  'Home area: Maadi; Leaves: 9:00 am–10:30 am; To the bride''s house: 20 min; To the hotel: 45 min; '
  || 'Seats: 0 of 2 taken; Trunk space: 50%',
  'To the hotel details (BR-14)'
);

select is(
  tests.row_titled(tests.section(get_car(tests.car_id('Sara'))::jsonb, 'Stops'), 'Pharmacy') ->> 'subtitle',
  'For the bride',
  'each stop says who it''s for'
);

select is(
  tests.pairs_text(tests.section(get_car(tests.car_id('Sara'))::jsonb, 'Notes')),
  'Notes: Leaving from Maadi',
  'everyone can read the notes (BR-16)'
);

select is(
  (select (select string_agg(s ->> 'title', ', ') from jsonb_array_elements(d -> 'sections') s)
          || ' / ' || tests.pairs_text(tests.section(d, 'Details'))
   from (select get_car(tests.car_id('Mai', 'hotel_to_venue'))::jsonb as d) x),
  'Details, Passengers, Cargo / Leaves: 6:00 pm–6:30 pm; Seats: 0 of 3 taken; Trunk space: 25%',
  'a Hotel to venue car has no stops, and no notes section without notes (BR-15)'
);

select is(
  tests.pairs_text(tests.section(get_car(tests.car_id('Rana', 'return_home'))::jsonb, 'Details')),
  'Drops off in: Maadi, Nasr City; Leaves: 11:30 pm–12:30 am; Seats: 0 of 2 taken; Trunk space: 0% (full)',
  'Return home details'
);

-- ---------------------------------------------------------------------
-- get_car: actions
-- ---------------------------------------------------------------------

select is(
  tests.action_ids(get_car(tests.car_id('Sara'))::jsonb),
  'ask_to_ride',
  'someone with no ride and no cargo can ask to ride'
);

select is(
  get_car(tests.car_id('Sara'))::jsonb -> 'actions' -> 0 -> 'call',
  jsonb_build_object('function', 'send_request',
    'args', jsonb_build_object('car_id', tests.car_id('Sara'), 'kind', 'passenger',
                               'direction', 'ask', 'passenger_id', tests.member_id('Rana'))),
  'Ask to ride sends a passenger Ask for me'
);

select tests.act_as('Nour');
select create_item(name => 'Shoes', visibility => 'shared');

select is(
  tests.action_ids(get_car(tests.car_id('Sara'))::jsonb),
  'ask_to_ride,ask_to_carry',
  'with eligible cargo, I can also ask to carry an item'
);

select send_request(tests.car_id('Sara'), 'passenger', 'ask', passenger_id => tests.member_id('Nour'));

select is(
  tests.action_ids(get_car(tests.car_id('Sara'))::jsonb),
  'ask_to_carry',
  'no Ask to ride while I have a pending request with this car'
);

select send_request(tests.car_id('Sara'), 'cargo', 'ask', item_id => tests.item_id('Shoes'),
                    pickup_type => 'bride_home');

select is(
  tests.action_ids(get_car(tests.car_id('Sara'))::jsonb),
  '',
  'no Ask to carry once every eligible item has a request with this car'
);

select tests.act_as('Sara');

select is(
  tests.action_ids(get_car(tests.car_id('Sara'))::jsonb),
  'offer_seat,offer_to_carry,edit,withdraw',
  'my car: offer a seat, offer to carry, edit, withdraw'
);

select is(
  (select a ->> 'style' || ' / ' || (a ->> 'confirm')
   from jsonb_array_elements(get_car(tests.car_id('Sara'))::jsonb -> 'actions') a
   where a ->> 'id' = 'withdraw'),
  'danger / Withdraw your car from this trip? Everyone in it will see that it''s no longer coming.',
  'withdrawing asks first'
);

select respond_to_request(tests.request_on(tests.car_id('Sara'), 'Nour'), true);
select tests.act_as('Nour');

select is(
  (select tests.action_ids(r) || ' / ' || (r -> 'actions' -> 0 ->> 'confirm')
   from (select tests.row_titled(tests.section(get_car(tests.car_id('Sara'))::jsonb, 'Passengers'),
                                 'Nour (Bridesmaid)') as r) s),
  'leave / Leave Sara''s car?',
  'a confirmed passenger sees herself listed, with Leave this car'
);

select tests.act_as('Sara');

select is(
  tests.action_ids(tests.row_titled(tests.section(get_car(tests.car_id('Sara'))::jsonb, 'Passengers'),
                                    'Nour (Bridesmaid)')),
  '',
  'the car owner can''t remove a passenger (BR-21)'
);

select tests.act_as('Rana');
select send_request(tests.car_id('Bride'), 'passenger', 'ask', passenger_id => tests.member_id('Rana'));
select tests.act_as('Bride');
select respond_to_request(tests.request_on(tests.car_id('Bride'), 'Rana'), true);
select tests.act_as('Rana');

select is(
  tests.action_ids(get_car(tests.car_id('Sara'))::jsonb),
  '',
  'no Ask to ride once I''m confirmed in another car on this trip (BR-22)'
);

select tests.act_as('Mai');
select send_request(tests.car_id('Sara'), 'passenger', 'ask', passenger_id => tests.member_id('Mai'));
select tests.act_as('Sara');
select respond_to_request(tests.request_on(tests.car_id('Sara'), 'Mai'), true);

select is(
  tests.action_ids(get_car(tests.car_id('Sara'))::jsonb),
  'offer_to_carry,edit,withdraw',
  'a full car offers no seat'
);

select tests.act_as('Bride');

select is(
  tests.action_ids(get_car(tests.car_id('Sara'))::jsonb),
  '',
  'and no one can ask to ride it (BR-23)'
);

select tests.act_as('Sara');
select respond_to_request(tests.request_on(tests.car_id('Sara'), 'Shoes'), true);

select is(
  (select r ->> 'subtitle' || ' / ' || tests.action_ids(r)
   from (select tests.row_titled(tests.section(get_car(tests.car_id('Sara'))::jsonb, 'Cargo'), 'Shoes') as r) s),
  'Nour · Pickup: Bride''s home / ',
  'confirmed cargo shows its owner and pickup (BR-18)'
);

select tests.act_as('Nour');

select is(
  tests.action_ids(tests.row_titled(tests.section(get_car(tests.car_id('Sara'))::jsonb, 'Cargo'), 'Shoes')),
  'take_out',
  'the cargo''s owner can take it out of the car'
);

select tests.car_id('Nour', 'return_home') as nour_return \gset
select withdraw_car(:'nour_return');

select is(
  (select d ->> 'subtitle' || ' / ' || tests.action_ids(d)
   from (select get_car(:'nour_return')::jsonb as d) s),
  'Return home · Withdrawn / ',
  'a withdrawn car says so and has no actions'
);

select is(
  tests.titles(list_cars('{"trip": ["return_home"]}')::jsonb),
  'Rana''s car',
  'withdrawn cars leave the list'
);

select is(
  tests.badges(tests.row_titled(list_cars()::jsonb, 'Sara''s car')) || ' / '
    || (tests.row_titled(list_cars()::jsonb, 'Sara''s car') ->> 'subtitle'),
  'Full, Trunk 50% / Maadi · leaves 9:00 am–10:30 am · 2 of 2 seats taken',
  'a full car is marked Full'
);

select * from finish();
rollback;
