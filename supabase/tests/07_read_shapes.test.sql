-- Every screen, for every member, has the contract's shapes (contract
-- Section 1), and every form action opens a well-formed form (Section 5).
begin;
\ir _helpers.psql
\ir _read_helpers.psql

select plan(16);

select tests.wedding();

-- Traffic in every request state, on every trip, and a withdrawn car.
select tests.act_as('Nour');
select create_item(name => 'Shoes', visibility => 'shared');
select send_request(tests.car_id('Sara'), 'passenger', 'ask', passenger_id => tests.member_id('Nour'));
select send_request(tests.car_id('Mai', 'hotel_to_venue'), 'passenger', 'ask',
                    passenger_id => tests.member_id('Nour'));

select tests.act_as('Rana');
select send_request(tests.car_id('Bride'), 'passenger', 'ask', passenger_id => tests.member_id('Rana'));
select register_car(trip => 'return_home', seats => 2, departure_earliest => '23:30',
                    departure_latest => '00:30', dropoff_areas => array['maadi', 'other']::area[],
                    dropoff_area_other => 'Nasr City', trunk_percent => 0);

select tests.act_as('Nour');
select send_request(tests.car_id('Rana', 'return_home'), 'passenger', 'ask',
                    passenger_id => tests.member_id('Nour'));

select tests.act_as('Bride');
select respond_to_request(tests.request_on(tests.car_id('Bride'), 'Rana'), true);

select tests.act_as('Mai');
select respond_to_request(tests.request_on(tests.car_id('Mai', 'hotel_to_venue'), 'Nour'), false);
select send_request(tests.car_id('Mai', 'hotel_to_venue'), 'cargo', 'offer',
                    item_id => tests.item_id('Giveaways'), pickup_type => 'bride_home');

select tests.act_as('Sara');
select respond_to_request(tests.request_on(tests.car_id('Mai', 'hotel_to_venue'), 'Giveaways'), true);
select send_request(tests.car_id('Bride'), 'cargo', 'ask', item_id => tests.item_id('Blue bag'),
                    pickup_type => 'custom', pickup_address => '9 Road 200', ready_at => '10:00');

select tests.act_as('Rana');
select withdraw_car(tests.car_id('Rana', 'return_home'));

-- ---------------------------------------------------------------------
-- The checks catch broken shapes.

select isnt_empty(
  $$ select * from tests.row_problems('{"id": "x", "title": "No badges or actions"}', 'row') $$,
  'the row check catches missing keys'
);

select isnt_empty(
  $$ select * from tests.action_problems(
       '{"id": "x", "label": "X", "style": "primary", "confirm": null,
         "call": {"function": "claim_item", "args": {}}, "form": {"name": "item", "context": {}}}',
       'action') $$,
  'the action check catches an action with both call and form'
);

select isnt_empty(
  $$ select * from tests.action_problems(
       '{"id": "x", "label": "X", "style": "primary", "confirm": null,
         "call": {"function": "cancel_cargo_requests", "args": {}}, "form": null}',
       'action') $$,
  'the action check catches a call to an internal helper the app can''t reach'
);

select isnt_empty(
  $$ select * from tests.field_problems(
       '{"key": "x", "label": "X", "type": "slider", "required": false, "options": null,
         "hint": null, "default": null, "value": null, "visible_if": null, "fields": null}',
       'field') $$,
  'the field check catches an unknown field type'
);

-- ---------------------------------------------------------------------

select tests.act_as('Sara');

select cmp_ok(
  (select count(*)::int from tests.screens()), '>=', 20,
  'the sweep opens Sara''s home, lists, and every item and car she can see'
);

select cmp_ok(
  (select count(*)::int from tests.screens() s, tests.all_actions(s.body) a), '>=', 40,
  'and finds plenty of actions on them'
);

select is_empty($$ select * from tests.screen_problems() $$,
  'Sara: every screen has the contract''s shapes');
select is_empty($$ select * from tests.form_action_problems() $$,
  'Sara: every form action opens a well-formed form');

select tests.act_as('Mai');
select is_empty($$ select * from tests.screen_problems() $$,
  'Mai: every screen has the contract''s shapes');
select is_empty($$ select * from tests.form_action_problems() $$,
  'Mai: every form action opens a well-formed form');

select tests.act_as('Bride');
select is_empty($$ select * from tests.screen_problems() $$,
  'Bride: every screen has the contract''s shapes');
select is_empty($$ select * from tests.form_action_problems() $$,
  'Bride: every form action opens a well-formed form');

select tests.act_as('Nour');
select is_empty($$ select * from tests.screen_problems() $$,
  'Nour: every screen has the contract''s shapes');
select is_empty($$ select * from tests.form_action_problems() $$,
  'Nour: every form action opens a well-formed form');

select tests.act_as('Rana');
select is_empty($$ select * from tests.screen_problems() $$,
  'Rana: every screen has the contract''s shapes');
select is_empty($$ select * from tests.form_action_problems() $$,
  'Rana: every form action opens a well-formed form');

select * from finish();
rollback;
