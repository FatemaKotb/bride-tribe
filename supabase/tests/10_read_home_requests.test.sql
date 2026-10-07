-- get_home (BR-26 to BR-28, BR-34) and list_requests (BR-25).
begin;
\ir _helpers.psql
\ir _read_helpers.psql

select plan(39);

select tests.wedding();

-- now() doesn't move inside a test, so put everyone's last "Got it" in
-- the past; otherwise no cancellation here would count as new.
update member set attention_cleared_at = now() - interval '1 hour';

-- ---------------------------------------------------------------------
-- get_home: me, my status, the status board
-- ---------------------------------------------------------------------

select has_function('public', 'get_home', array[]::name[]);

select tests.no_session();

select tests.throws_error(
  'select get_home()',
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'get_home without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Sara');
select set_status('doing_makeup');
update member set status_updated_at = now() - interval '12 minutes' where name = 'Sara';

select is(
  get_home()::jsonb -> 'me',
  '{"name": "Sara", "role_label": "Bridesmaid"}',
  'me: my name and role, for the header (BR-03a)'
);

select is(
  (get_home()::jsonb -> 'my_status') - 'options',
  '{"value": "doing_makeup", "label": "Doing makeup", "updated": "12 min ago"}',
  'my status, with how long ago I set it (BR-27)'
);

select is(
  jsonb_build_array(jsonb_array_length(get_home()::jsonb -> 'my_status' -> 'options'),
                    get_home()::jsonb -> 'my_status' -> 'options' -> 0),
  '[11, {"value": "at_home", "label": "At home", "emoji": "🏠"}]',
  'the status picker offers every status, in order, with labels and emoji (BR-26)'
);

select is(
  (select string_agg(r ->> 'title', ', ' order by n)
   from jsonb_array_elements(get_home()::jsonb -> 'status_board') with ordinality as t (r, n)),
  'Bride (Bride), Mai (Maid of Honor), Nour (Bridesmaid), Rana (Bridesmaid), Sara (Bridesmaid)',
  'the status board lists every member with her role, by role then name (BR-01, BR-28)'
);

select is(
  (select r ->> 'emoji' || ' ' || (r ->> 'subtitle')
   from jsonb_array_elements(get_home()::jsonb -> 'status_board') r
   where r ->> 'title' = 'Sara (Bridesmaid)'),
  '💄 Doing makeup · 12 min ago',
  'each member''s status and how long ago it changed (BR-28)'
);

select is(
  array[fmt_ago(now()), fmt_ago(now() - interval '3 hours'),
        fmt_ago(now() - interval '25 hours'), fmt_ago(now() - interval '50 hours')],
  array['just now', '3 hr ago', '1 day ago', '2 days ago'],
  'relative times read naturally'
);

-- ---------------------------------------------------------------------
-- get_home: Needs your attention (BR-34)
-- ---------------------------------------------------------------------

select tests.act_as('Nour');
select send_request(tests.car_id('Sara'), 'passenger', 'ask', passenger_id => tests.member_id('Nour'));

select tests.act_as('Sara');

select is(
  (select r ->> 'title' || ' / ' || tests.action_ids(r)
   from jsonb_array_elements(get_home()::jsonb -> 'attention') r),
  'Nour in your car / accept,decline',
  'a pending request waiting for my answer, with Accept and Decline'
);

select tests.act_as('Nour');

select is(
  jsonb_array_length(get_home()::jsonb -> 'attention'), 0,
  'the sender isn''t asked to act on her own request'
);

select tests.act_as('Rana');
select send_request(tests.car_id('Bride'), 'passenger', 'ask', passenger_id => tests.member_id('Rana'));
select tests.act_as('Sara');
select send_request(tests.car_id('Sara'), 'passenger', 'offer', passenger_id => tests.member_id('Rana'));
select tests.act_as('Rana');

select is(
  (select r ->> 'title' || ' / ' || tests.action_ids(r)
   from jsonb_array_elements(get_home()::jsonb -> 'attention') r),
  'Ride in Sara''s car / accept,decline',
  'an Offer waits for the passenger''s answer'
);

-- Rana accepts Sara's offer, which cancels her ask to Bride's car.
select respond_to_request(tests.request_on(tests.car_id('Sara'), 'Rana'), true);

select is(
  (select member_name(r.cancelled_by_id) || ' / ' || (r.cancelled_at = now())::text
   from request r where r.id = tests.request_on(tests.car_id('Bride'), 'Rana')),
  'Rana / true',
  'a cancellation records who caused it and when (ruling)'
);

select is(
  jsonb_array_length(get_home()::jsonb -> 'attention'), 0,
  'whoever caused a cancellation doesn''t see it in Needs your attention (ruling)'
);

select tests.act_as('Bride');

select is(
  (select string_agg(coalesce(r ->> 'subtitle', '[' || tests.action_ids(r) || ']'), ' | ' order by n)
   from jsonb_array_elements(get_home()::jsonb -> 'attention') with ordinality as t (r, n)),
  'To the hotel · Rana asked · Cancelled automatically | [got_it]',
  'the other party sees the automatic cancellation, followed by Got it'
);

select is(
  get_home()::jsonb -> 'attention' -> -1,
  '{"id": "got_it", "emoji": null, "title": null, "subtitle": null, "badges": [], "open": null,
    "actions": [{"id": "got_it", "label": "Got it", "style": "secondary", "confirm": null,
                 "call": {"function": "clear_attention", "args": {}}, "form": null}]}',
  'Got it calls clear_attention'
);

select is(
  get_home()::jsonb -> 'attention', get_home()::jsonb -> 'attention',
  'get_home has no side effects: reading it again hides nothing'
);

select tests.act_as('Nour');
select send_request(tests.car_id('Bride'), 'passenger', 'ask', passenger_id => tests.member_id('Nour'));
select tests.act_as('Bride');
select clear_attention();

select is(
  (select string_agg(r ->> 'title', ', ') from jsonb_array_elements(get_home()::jsonb -> 'attention') r),
  'Nour in your car',
  'Got it clears the cancellations, but pending requests stay until answered'
);

-- Left the car: the car owner sees it.
select tests.act_as('Rana');
select leave_car(tests.request_on(tests.car_id('Sara'), 'Rana'));

select is(
  jsonb_array_length(get_home()::jsonb -> 'attention'), 0,
  'the passenger who left doesn''t see her own leaving'
);

select tests.act_as('Sara');

select is(
  (select string_agg(r ->> 'title' || ': ' || (r ->> 'subtitle'), ' | ' order by n)
   from jsonb_array_elements(get_home()::jsonb -> 'attention') with ordinality as t (r, n)
   where r ->> 'title' is not null),
  'Nour in your car: To the hotel · Nour asked · Pending | Rana in your car: To the hotel · You offered · Left the car',
  'the car owner sees a passenger leave (BR-21), after her pending requests'
);

-- Car withdrawn: the passenger sees it.
select tests.act_as('Bride');
select withdraw_car(tests.car_id('Bride'));

select is(
  jsonb_array_length(get_home()::jsonb -> 'attention'), 0,
  'the owner who withdrew doesn''t see her own withdrawal'
);

select tests.act_as('Nour');

select is(
  (select r ->> 'title' || ': ' || (r ->> 'subtitle')
   from jsonb_array_elements(get_home()::jsonb -> 'attention') r where r ->> 'title' is not null),
  'Ride in Bride''s car: To the hotel · You asked · Car withdrawn',
  'the passenger sees the car withdrawn (BR-19)'
);

-- Cancelled by the sender: the responder sees it.
select cancel_request(tests.request_on(tests.car_id('Sara'), 'Nour'));
select tests.act_as('Sara');

select ok(
  exists (select 1 from jsonb_array_elements(get_home()::jsonb -> 'attention') r
          where r ->> 'subtitle' = 'To the hotel · Nour asked · Cancelled by sender'),
  'the car owner sees that the sender cancelled'
);

-- Someone else's action: Mai deletes the Giveaways Sara was sending.
select send_request(tests.car_id('Mai', 'hotel_to_venue'), 'cargo', 'ask',
                    item_id => tests.item_id('Giveaways'), pickup_type => 'bride_home');
select tests.act_as('Mai');
select delete_item(tests.item_id('Giveaways'));
select tests.act_as('Sara');

select ok(
  exists (select 1 from jsonb_array_elements(get_home()::jsonb -> 'attention') r
          where r ->> 'title' = 'A deleted item in Mai''s car'
            and r ->> 'subtitle' like '%Cancelled automatically%'),
  'the cargo''s owner sees a request cancelled because its item was deleted'
);

-- ---------------------------------------------------------------------
-- list_requests (BR-25)
-- ---------------------------------------------------------------------

select has_function('public', 'list_requests', array['jsonb']);

select tests.no_session();

select tests.throws_error(
  'select list_requests()',
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'list_requests without a session raises NOT_SIGNED_IN'
);

-- Fresh requests on Mai's Hotel to venue car.
select tests.act_as('Nour');
select send_request(tests.car_id('Mai', 'hotel_to_venue'), 'passenger', 'ask',
                    passenger_id => tests.member_id('Nour'));
select tests.act_as('Sara');
select send_request(tests.car_id('Mai', 'hotel_to_venue'), 'cargo', 'ask',
                    item_id => tests.item_id('Blue bag'), pickup_type => 'custom',
                    pickup_address => '9 Road 200', ready_at => '10:00');
select tests.act_as('Mai');
select send_request(tests.car_id('Mai', 'hotel_to_venue'), 'passenger', 'offer',
                    passenger_id => tests.member_id('Rana'));

select is(
  (select string_agg(f ->> 'key', ',') || ' / ' || (list_requests()::jsonb -> 'filters' -> 1 ->> 'selected')
   from jsonb_array_elements(list_requests()::jsonb -> 'filters') f),
  'direction,state,kind / ["pending"]',
  'filters: direction, state (Pending by default), and kind'
);

select is(
  (select string_agg(r ->> 'title', ', ' order by r ->> 'title')
   from jsonb_array_elements(list_requests()::jsonb -> 'rows') r),
  'Blue bag in your car, Nour in your car, Rana in your car',
  'my pending requests, sent and received'
);

select is(
  tests.titles(list_requests('{"direction": ["sent"]}')::jsonb),
  'Rana in your car',
  'sent'
);

select is(
  (select string_agg(r ->> 'title', ', ' order by r ->> 'title')
   from jsonb_array_elements(list_requests('{"direction": ["received"]}')::jsonb -> 'rows') r),
  'Blue bag in your car, Nour in your car',
  'received'
);

select is(
  (select r ->> 'title' || ': ' || (r ->> 'subtitle') || ' / ' || tests.action_ids(r)
   from jsonb_array_elements(list_requests('{"kind": ["cargo"]}')::jsonb -> 'rows') r),
  'Blue bag in your car: Hotel to venue · Sara asked · Pending · Pickup: 9 Road 200, ready 10:00 am / accept,decline',
  'cargo: the pickup and ready time, with Accept and Decline for the responder'
);

select is(
  tests.action_ids(tests.row_titled(list_requests()::jsonb, 'Rana in your car')),
  'cancel',
  'the sender can cancel a pending request'
);

select is(
  tests.row_titled(list_requests()::jsonb, 'Nour in your car') -> 'open',
  jsonb_build_object('detail', 'car', 'id', tests.car_id('Mai', 'hotel_to_venue')),
  'tapping a request opens its car'
);

select tests.act_as('Nour');

select is(
  (select r ->> 'subtitle' || ' / ' || tests.action_ids(r)
   from (select tests.row_titled(list_requests()::jsonb, 'Ride in Mai''s car') as r) s),
  'Hotel to venue · You asked · Pending / cancel',
  'the passenger sees her own Ask from her side'
);

select tests.act_as('Mai');
select respond_to_request(tests.request_on(tests.car_id('Mai', 'hotel_to_venue'), 'Nour'), true);
select respond_to_request(tests.request_on(tests.car_id('Mai', 'hotel_to_venue'), 'Blue bag'), true);

select is(
  tests.action_ids(tests.row_titled(list_requests('{"state": ["confirmed"]}')::jsonb, 'Nour in your car')),
  '',
  'a confirmed passenger in my car: nothing for the car owner to do'
);

select tests.act_as('Nour');

select is(
  (select tests.action_ids(r) || ' / ' || (r -> 'actions' -> 0 ->> 'confirm')
   from (select tests.row_titled(list_requests('{"state": ["confirmed"]}')::jsonb, 'Ride in Mai''s car') as r) s),
  'leave / Leave Mai''s car?',
  'a confirmed passenger can leave the car'
);

select tests.act_as('Sara');

select is(
  tests.action_ids(tests.row_titled(list_requests('{"state": ["confirmed"]}')::jsonb, 'Blue bag in Mai''s car')),
  'take_out',
  'the owner of confirmed cargo can take it out'
);

select is(
  (select r ->> 'subtitle'
   from jsonb_array_elements(list_requests('{"state": ["cancelled"]}')::jsonb -> 'rows') r
   where r ->> 'title' = 'A deleted item in Mai''s car'),
  'Hotel to venue · You asked · Cancelled automatically · Pickup: Bride''s home',
  'cancelled requests say why, and a deleted item''s request remains'
);

select is(
  jsonb_array_length(list_requests('{"state": []}')::jsonb -> 'rows'),
  (select count(*)::int from request r where is_party(r, tests.member_id('Sara'))),
  'an empty state filter shows every state'
);

select tests.act_as('Bride');

select is(
  (select count(*)::int
   from jsonb_array_elements(list_requests('{"state": []}')::jsonb -> 'rows') r
   where r -> 'open' ->> 'id' = tests.car_id('Mai', 'hotel_to_venue')::text),
  0,
  'members not involved in a request don''t see it'
);

select * from finish();
rollback;
