-- register_car, update_car, withdraw_car
-- (contract Section 4, BR-13 to BR-19, BR-23).
begin;
\ir _helpers.psql

select plan(43);

select tests.reset_members();
insert into member (name, role) values ('Rana', 'bridesmaid');

-- ---------------------------------------------------------------------
-- register_car
-- ---------------------------------------------------------------------

select has_function('public', 'register_car', array[
  'trip', 'integer', 'time without time zone', 'time without time zone', 'area', 'text',
  'integer', 'integer', 'jsonb', 'area[]', 'text', 'integer', 'text']);

select tests.no_session();

select tests.throws_error(
  $$ select register_car(trip => 'to_hotel', seats => 3, departure_earliest => '09:00',
                         departure_latest => '10:00', home_area => 'maadi') $$,
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'register_car without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Sara');

select register_car(
  trip => 'to_hotel', seats => 3,
  departure_earliest => '09:00', departure_latest => '10:30',
  home_area => 'maadi', home_area_other => 'ignored',
  minutes_to_bride => 20, minutes_to_hotel => 45,
  stops => '[{"description": " Pharmacy ", "purpose": "myself"},
             {"description": "", "purpose": null},
             {"description": "Flowers", "purpose": "bride"}]',
  trunk_percent => 50, notes => ' Leaving from Maadi '
);

select is(
  tests.car_fields(tests.car_id('Sara')),
  '{"owner": "Sara", "trip": "to_hotel", "seats": 3,
    "departure_earliest": "09:00:00", "departure_latest": "10:30:00",
    "home_area": "maadi", "home_area_other": null,
    "minutes_to_bride": 20, "minutes_to_hotel": 45, "trunk_percent": 50,
    "notes": "Leaving from Maadi", "withdrawn": false,
    "stops": [{"description": "Pharmacy", "purpose": "myself"},
              {"description": "Flowers", "purpose": "bride"}],
    "dropoff": []}',
  'register_car saves a To the hotel car, its stops in order, skipping empty stop rows and stray Other text (BR-14)'
);

select tests.throws_error(
  $$ select register_car(trip => 'to_hotel', seats => 2, departure_earliest => '09:00',
                         departure_latest => '10:00', home_area => 'maadi') $$,
  'ALREADY_HAS_CAR', 'You already have a car on this trip.',
  'one car per member per trip'
);

select register_car(trip => 'hotel_to_venue', seats => 2,
                    departure_earliest => '18:00', departure_latest => '18:30',
                    trunk_percent => 0);

select is(
  tests.car_fields(tests.car_id('Sara', 'hotel_to_venue')),
  '{"owner": "Sara", "trip": "hotel_to_venue", "seats": 2,
    "departure_earliest": "18:00:00", "departure_latest": "18:30:00",
    "home_area": null, "home_area_other": null,
    "minutes_to_bride": null, "minutes_to_hotel": null, "trunk_percent": 0,
    "notes": null, "withdrawn": false, "stops": [], "dropoff": []}',
  'a member registers separately for each trip (BR-13)'
);

select register_car(
  trip => 'return_home', seats => 4,
  departure_earliest => '23:00', departure_latest => '23:45',
  dropoff_areas => array['maadi', 'other', 'maadi']::area[], dropoff_area_other => ' Nasr City ',
  trunk_percent => 100
);

select is(
  tests.car_fields(tests.car_id('Sara', 'return_home')) -> 'dropoff',
  '[{"area": "maadi", "area_other": null}, {"area": "other", "area_other": "Nasr City"}]',
  'a Return home car keeps its drop-off areas, once each, with the Other text (BR-15)'
);

select tests.act_as('Mai');

select tests.throws_error(
  $$ select register_car(trip => 'hotel_to_venue', seats => 2, departure_earliest => '18:00',
                         departure_latest => '18:30', home_area => 'maadi') $$,
  'FIELD_NOT_ALLOWED', 'This field doesn''t apply to this trip.',
  'home area is for To the hotel only'
);

select tests.throws_error(
  $$ select register_car(trip => 'return_home', seats => 2, departure_earliest => '23:00',
                         departure_latest => '23:30', minutes_to_hotel => 30) $$,
  'FIELD_NOT_ALLOWED', 'This field doesn''t apply to this trip.',
  'travel times are for To the hotel only'
);

select tests.throws_error(
  $$ select register_car(trip => 'hotel_to_venue', seats => 2, departure_earliest => '18:00',
                         departure_latest => '18:30',
                         stops => '[{"description": "Pharmacy", "purpose": "myself"}]') $$,
  'FIELD_NOT_ALLOWED', 'This field doesn''t apply to this trip.',
  'stops are for To the hotel only'
);

select tests.throws_error(
  $$ select register_car(trip => 'to_hotel', seats => 2, departure_earliest => '09:00',
                         departure_latest => '10:00', home_area => 'maadi',
                         dropoff_areas => array['maadi']::area[]) $$,
  'FIELD_NOT_ALLOWED', 'This field doesn''t apply to this trip.',
  'drop-off areas are for Return home only'
);

select tests.throws_error(
  $$ select register_car(trip => 'to_hotel', seats => 2, departure_earliest => '11:00',
                         departure_latest => '10:00', home_area => 'maadi') $$,
  'INVALID_WINDOW', 'The earliest time must be before the latest time.',
  'the earliest departure can''t be after the latest'
);

select tests.throws_error(
  $$ select register_car(trip => 'hotel_to_venue', seats => 2, departure_earliest => '19:00',
                         departure_latest => '18:00', trunk_percent => 0) $$,
  'INVALID_WINDOW', 'The earliest time must be before the latest time.',
  'only a Return home window can cross midnight'
);

select throws_ok(
  $$ select register_car(trip => 'hotel_to_venue', seats => 2, departure_earliest => '18:00',
                         departure_latest => '18:30') $$,
  '23502', null,
  'trunk space is required (ruling): leaving it out fails like any required field'
);

select tests.throws_error(
  $$ select register_car(trip => 'to_hotel', seats => 2, departure_earliest => '09:00',
                         departure_latest => '10:00', home_area => 'other', home_area_other => ' ') $$,
  'OTHER_AREA_REQUIRED', 'Please type the area.',
  'an Other home area needs its text'
);

select tests.throws_error(
  $$ select register_car(trip => 'return_home', seats => 2, departure_earliest => '23:00',
                         departure_latest => '23:30', dropoff_areas => array['other']::area[]) $$,
  'OTHER_AREA_REQUIRED', 'Please type the area.',
  'an Other drop-off area needs its text'
);

select tests.throws_error(
  $$ select register_car(trip => 'hotel_to_venue', seats => -1, departure_earliest => '18:00',
                         departure_latest => '18:30') $$,
  'INVALID_NUMBER', 'Seats can''t be negative.',
  'seats can''t be negative (ruling)'
);

select tests.throws_error(
  $$ select register_car(trip => 'to_hotel', seats => 2, departure_earliest => '09:00',
                         departure_latest => '10:00', home_area => 'maadi', minutes_to_bride => -5) $$,
  'INVALID_NUMBER', 'Travel time can''t be negative.',
  'travel time can''t be negative (ruling)'
);

select tests.throws_error(
  $$ select register_car(trip => 'to_hotel', seats => 2, departure_earliest => '09:00',
                         departure_latest => '10:00', home_area => 'maadi',
                         stops => '[{"description": " ", "purpose": "bride"}]') $$,
  'NAME_REQUIRED', 'Please describe each stop.',
  'a stop needs a description'
);

select is(
  (select count(*)::int from car where owner_id = tests.member_id('Mai')), 0,
  'a rejected car is not saved'
);

select tests.act_as('Nour');

select register_car(
  trip => 'to_hotel', seats => 0, departure_earliest => '08:00', departure_latest => '08:00',
  home_area => 'other', home_area_other => ' Nasr City ', trunk_percent => 100
);

select is(
  (select home_area_other || ', ' || seats || ' seats, ' || departure_earliest || '-' || departure_latest
   from car where id = tests.car_id('Nour')),
  'Nasr City, 0 seats, 08:00:00-08:00:00',
  'an Other home area keeps its text; a car can have 0 seats (cargo only) and a single departure time'
);

-- ---------------------------------------------------------------------
-- update_car
-- ---------------------------------------------------------------------

select has_function('public', 'update_car', array[
  'uuid', 'integer', 'time without time zone', 'time without time zone', 'area', 'text',
  'integer', 'integer', 'jsonb', 'area[]', 'text', 'integer', 'text']);

select tests.no_session();

select tests.throws_error(
  format('select update_car(%L, seats => 3)', tests.car_id('Sara')),
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'update_car without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Mai');

select tests.throws_error(
  format('select update_car(%L, seats => 3)', gen_random_uuid()),
  'NOT_FOUND', 'This car no longer exists.',
  'an unknown car raises NOT_FOUND (ruling)'
);

select tests.throws_error(
  format('select update_car(%L, seats => 9, departure_earliest => %L, departure_latest => %L, home_area => %L)',
         tests.car_id('Sara'), '09:00', '10:00', 'maadi'),
  'NOT_ALLOWED', 'You can''t change this.',
  'only the owner can edit a car'
);

select tests.act_as('Sara');

select update_car(
  tests.car_id('Sara'), seats => 4,
  departure_earliest => '08:30', departure_latest => '09:30',
  home_area => 'zahraa_el_maadi', minutes_to_bride => 15, minutes_to_hotel => 40,
  stops => '[{"description": "Bakery", "purpose": "bride"}]', trunk_percent => 25
);

select is(
  tests.car_fields(tests.car_id('Sara')),
  '{"owner": "Sara", "trip": "to_hotel", "seats": 4,
    "departure_earliest": "08:30:00", "departure_latest": "09:30:00",
    "home_area": "zahraa_el_maadi", "home_area_other": null,
    "minutes_to_bride": 15, "minutes_to_hotel": 40, "trunk_percent": 25,
    "notes": null, "withdrawn": false,
    "stops": [{"description": "Bakery", "purpose": "bride"}],
    "dropoff": []}',
  'the owner can edit every field; the submitted stops replace the old ones'
);

select tests.throws_error(
  format('select update_car(%L, seats => 4, departure_earliest => %L, departure_latest => %L, home_area => %L, dropoff_areas => %L)',
         tests.car_id('Sara'), '08:30', '09:30', 'maadi', '{maadi}'),
  'FIELD_NOT_ALLOWED', 'This field doesn''t apply to this trip.',
  'an edited car keeps its trip, and only that trip''s fields'
);

select tests.throws_error(
  format('select update_car(%L, seats => 4, departure_earliest => %L, departure_latest => %L, home_area => %L)',
         tests.car_id('Sara'), '10:00', '09:00', 'maadi'),
  'INVALID_WINDOW', 'The earliest time must be before the latest time.',
  'an edited window is checked too'
);

select update_car(
  tests.car_id('Sara', 'return_home'), seats => 4,
  departure_earliest => '23:00', departure_latest => '23:45',
  dropoff_areas => array['october']::area[], trunk_percent => 100
);

select is(
  tests.car_fields(tests.car_id('Sara', 'return_home')) -> 'dropoff',
  '[{"area": "october", "area_other": null}]',
  'the submitted drop-off areas replace the old ones'
);

-- Seats against confirmed passengers.
select tests.act_as('Mai');
select create_item(name => 'Cake');
select tests.act_as('Sara');

select tests.add_passenger_request(tests.car_id('Sara'), 'Mai', 'confirmed') as mai_confirmed \gset
select tests.add_passenger_request(tests.car_id('Sara'), 'Nour', 'confirmed') as nour_confirmed \gset
select tests.add_passenger_request(tests.car_id('Sara'), 'Bride', 'pending') as bride_pending \gset
select tests.add_passenger_request(tests.car_id('Sara'), 'Rana', 'pending') as rana_pending \gset
select tests.add_cargo_request(tests.car_id('Sara'), tests.item_id('Cake'), 'pending') as cake_pending \gset

select tests.throws_error(
  format('select update_car(%L, seats => 1, departure_earliest => %L, departure_latest => %L, home_area => %L)',
         tests.car_id('Sara'), '08:30', '09:30', 'maadi'),
  'SEATS_BELOW_CONFIRMED', 'You already have 2 confirmed passengers.',
  'seats can''t go below the confirmed passengers'
);

select tests.add_passenger_request(tests.car_id('Sara', 'hotel_to_venue'), 'Mai', 'confirmed');

select tests.throws_error(
  format('select update_car(%L, seats => 0, departure_earliest => %L, departure_latest => %L)',
         tests.car_id('Sara', 'hotel_to_venue'), '18:00', '18:30'),
  'SEATS_BELOW_CONFIRMED', 'You already have 1 confirmed passenger.',
  'the message counts one passenger in the singular'
);

select update_car(
  tests.car_id('Sara'), seats => 2,
  departure_earliest => '08:30', departure_latest => '09:30', home_area => 'maadi',
  trunk_percent => 25
);

select is(
  array[tests.request_state(:'bride_pending'), tests.request_state(:'rana_pending')],
  array['cancelled/auto', 'cancelled/auto'],
  'lowering seats to the confirmed passengers fills the car and cancels its pending passenger requests (ruling)'
);

select is(
  array[tests.request_state(:'mai_confirmed'), tests.request_state(:'nour_confirmed'),
        tests.request_state(:'cake_pending')],
  array['confirmed', 'confirmed', 'pending'],
  'confirmed passengers stay, and cargo requests don''t use seats'
);

-- ---------------------------------------------------------------------
-- withdraw_car
-- ---------------------------------------------------------------------

select has_function('public', 'withdraw_car', array['uuid']);

select tests.car_id('Sara', 'return_home') as return_car \gset

select tests.add_passenger_request(:'return_car', 'Mai', 'confirmed') as w_confirmed \gset
select tests.add_passenger_request(:'return_car', 'Nour', 'pending') as w_pending \gset
select tests.add_passenger_request(:'return_car', 'Bride', 'declined') as w_declined \gset
select tests.add_passenger_request(:'return_car', 'Rana', 'cancelled') as w_cancelled \gset
select tests.add_cargo_request(:'return_car', tests.item_id('Cake'), 'pending') as w_cargo \gset

select tests.no_session();

select tests.throws_error(
  format('select withdraw_car(%L)', :'return_car'),
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'withdraw_car without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Mai');

select tests.throws_error(
  format('select withdraw_car(%L)', gen_random_uuid()),
  'NOT_FOUND', 'This car no longer exists.',
  'withdrawing an unknown car raises NOT_FOUND'
);

select tests.throws_error(
  format('select withdraw_car(%L)', :'return_car'),
  'NOT_ALLOWED', 'You can''t change this.',
  'only the owner can withdraw a car'
);

select tests.act_as('Sara');
select withdraw_car(:'return_car');

select is(
  tests.car_fields(:'return_car') ->> 'withdrawn', 'true',
  'withdraw_car withdraws my car (BR-19)'
);

select is(
  array[tests.request_state(:'w_confirmed'), tests.request_state(:'w_pending'),
        tests.request_state(:'w_cargo')],
  array['cancelled/car_withdrawn', 'cancelled/car_withdrawn', 'cancelled/car_withdrawn'],
  'withdrawing cancels every pending and confirmed request, passengers and cargo (car_withdrawn)'
);

select is(
  array[tests.request_state(:'w_declined'), tests.request_state(:'w_cancelled')],
  array['declined', 'cancelled/by_sender'],
  'requests already answered keep their outcome'
);

select tests.throws_error(
  format('select withdraw_car(%L)', :'return_car'),
  'CAR_WITHDRAWN', 'This car is no longer available.',
  'a car can''t be withdrawn twice'
);

select tests.throws_error(
  format('select update_car(%L, seats => 4, departure_earliest => %L, departure_latest => %L)',
         :'return_car', '23:00', '23:45'),
  'CAR_WITHDRAWN', 'This car is no longer available.',
  'a withdrawn car can''t be edited'
);

select register_car(trip => 'return_home', seats => 2,
                    departure_earliest => '23:30', departure_latest => '00:30',
                    trunk_percent => 50);

select isnt(
  tests.car_id('Sara', 'return_home'), :'return_car'::uuid,
  'withdrawing frees the trip, so I can register a new car on it'
);

select is(
  (select departure_earliest || '-' || departure_latest from car
   where id = tests.car_id('Sara', 'return_home')),
  '23:30:00-00:30:00',
  'a Return home window can cross midnight (ruling)'
);

select * from finish();
rollback;
