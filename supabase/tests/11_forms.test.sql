-- get_form for every form in contract Section 5.
begin;
\ir _helpers.psql
\ir _read_helpers.psql

select plan(51);

select tests.wedding();

select has_function('public', 'get_form', array['text', 'jsonb']);

select tests.no_session();

select tests.throws_error(
  $$ select get_form('item', '{}') $$,
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'get_form without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Sara');

select tests.throws_error(
  $$ select get_form('wishlist', '{}') $$,
  'NOT_FOUND', 'This form doesn''t exist.',
  'an unknown form raises NOT_FOUND'
);

-- ---------------------------------------------------------------------
-- item
-- ---------------------------------------------------------------------

select is(
  get_form('item', '{}')::jsonb - 'fields',
  '{"name": "item", "title": "Add item", "context": {},
    "submit": {"function": "create_item", "label": "Save"}}',
  'a new item: no context, submitted to create_item'
);

select is(
  tests.field_keys(get_form('item', '{}')::jsonb),
  'name,emoji,description,quantity,tags,type,visibility,vendor',
  'the item form''s fields'
);

select is(
  (select (f ->> 'required') || ' ' || (f ->> 'default') || ' ' || tests.option_labels(f)
   from (select tests.field(get_form('item', '{}')::jsonb, 'type') as f) s),
  'true personal Personal, Claimable',
  'type is required, starts on Personal, and takes its labels from option_label'
);

select is(
  (select f -> 'visible_if' || jsonb_build_object('default', f -> 'default', 'required', f -> 'required')
   from (select tests.field(get_form('item', '{}')::jsonb, 'visibility') as f) s),
  '{"field": "type", "equals": "personal", "default": "private", "required": true}',
  'visibility shows only for personal items and starts on Private'
);

select is(
  (select (f -> 'visible_if')::text || ' ' ||
          (select string_agg(n ->> 'key', ',') from jsonb_array_elements(f -> 'fields') n)
   from (select tests.field(get_form('item', '{}')::jsonb, 'vendor') as f) s),
  '{"field": "type", "equals": "claimable"} vendor_name,service,phone,address,expected_time,amount_egp,details',
  'vendor details are a group shown only for claimable items (BR-29)'
);

select is(
  (select n ->> 'hint' from jsonb_array_elements(tests.field(get_form('item', '{}')::jsonb, 'vendor') -> 'fields') n
   where n ->> 'key' = 'expected_time'),
  'Use 24-hour time, like 23:30.',
  'time fields ask for 24-hour time, with 23:30 as the example (ruling)'
);

select is(
  (select jsonb_build_object(
     'quantity', tests.field(f, 'quantity') -> 'default',
     'amount_egp', (select n -> 'default' from jsonb_array_elements(tests.field(f, 'vendor') -> 'fields') n
                    where n ->> 'key' = 'amount_egp'))
   from (select get_form('item', '{}')::jsonb as f) s),
  '{"quantity": 1, "amount_egp": 0}',
  'quantity starts at 1, the vendor amount at 0 (ruling)'
);

select is(
  tests.option_labels(tests.field(get_form('item', '{}')::jsonb, 'tags')),
  'hair, makeup',
  'tag suggestions are the tags already in use'
);

select is(
  (select (f - 'fields') || jsonb_build_object('values', (
     select jsonb_object_agg(x ->> 'key', x -> 'value') from jsonb_array_elements(f -> 'fields') x
     where x ->> 'key' in ('name', 'tags', 'type', 'visibility')))
   from (select get_form('item', jsonb_build_object('item_id', tests.item_id('Perfume', 'Sara')))::jsonb as f) s),
  jsonb_build_object(
    'name', 'item', 'title', 'Edit item',
    'context', jsonb_build_object('item_id', tests.item_id('Perfume', 'Sara')),
    'submit', jsonb_build_object('function', 'update_item', 'label', 'Save'),
    'values', '{"name": "Perfume", "tags": ["makeup"], "type": "personal", "visibility": "shared"}'::jsonb),
  'editing my item: its current values, submitted to update_item'
);

select tests.act_as('Mai');

select is(
  (select jsonb_object_agg(n ->> 'key', n -> 'value')
   from jsonb_array_elements(tests.field(get_form('item', jsonb_build_object('item_id', tests.item_id('Photographer')))::jsonb,
                                         'vendor') -> 'fields') n),
  '{"vendor_name": "Ahmed Hassan", "service": "Photographer", "phone": null, "address": null,
    "expected_time": "17:00", "amount_egp": 2000.00, "details": null}',
  'the vendor group carries the current vendor details, times as HH:MM'
);

select tests.act_as('Sara');

select tests.throws_error(
  format('select get_form(%L, %L)', 'item', jsonb_build_object('item_id', tests.item_id('Photographer'))),
  'NOT_ALLOWED', 'You can''t change this.',
  'only the owner can open an item''s edit form, vendor details included (ruling)'
);

select tests.throws_error(
  format('select get_form(%L, %L)', 'item', jsonb_build_object('item_id', tests.item_id('Blue bag'))),
  'NOT_ALLOWED', 'You can''t change this.',
  'a bag is edited with the bag form'
);

select tests.throws_error(
  format('select get_form(%L, %L)', 'item', jsonb_build_object('item_id', gen_random_uuid())),
  'NOT_FOUND', 'This item was deleted.',
  'editing a deleted item raises NOT_FOUND'
);

select tests.act_as('Nour');

select is(
  (select (f - 'fields') || jsonb_build_object('values', (
     select jsonb_object_agg(x ->> 'key', x -> 'value') from jsonb_array_elements(f -> 'fields') x
     where x ->> 'key' in ('name', 'emoji', 'tags', 'type', 'visibility')))
   from (select get_form('item', jsonb_build_object('copy_of', tests.item_id('Perfume', 'Sara')))::jsonb as f) s),
  jsonb_build_object(
    'name', 'item', 'title', 'Add to my list',
    'context', jsonb_build_object('copy_of', tests.item_id('Perfume', 'Sara')),
    'submit', jsonb_build_object('function', 'create_item', 'label', 'Save'),
    'values', '{"name": "Perfume", "emoji": "📿", "tags": ["makeup"], "type": "personal",
                "visibility": "shared"}'::jsonb),
  'Add to my list: the form is pre-filled from the shared item (BR-07)'
);

select tests.throws_error(
  format('select get_form(%L, %L)', 'item', jsonb_build_object('copy_of', tests.item_id('Photographer'))),
  'COPY_NOT_ALLOWED', 'This item can''t be copied.',
  'a claimable item can''t be copied'
);

select tests.act_as('Mai');

select tests.throws_error(
  format('select get_form(%L, %L)', 'item', jsonb_build_object('copy_of', tests.item_id('Perfume', 'Sara'))),
  'ALREADY_ON_YOUR_LIST', 'This is already on your list.',
  'a member who has it can''t copy it again'
);

-- ---------------------------------------------------------------------
-- container
-- ---------------------------------------------------------------------

select tests.act_as('Sara');

select is(
  (select (f - 'fields') || jsonb_build_object('keys', tests.field_keys(f))
   from (select get_form('container', '{}')::jsonb as f) s),
  '{"name": "container", "title": "Add bag or box", "context": {}, "keys": "name,emoji",
    "submit": {"function": "create_container", "label": "Save"}}',
  'a new bag: name and emoji, submitted to create_container (BR-10)'
);

select is(
  (select (f ->> 'title') || ' / ' || (f -> 'submit' ->> 'function') || ' / '
          || (tests.field(f, 'name') ->> 'value')
   from (select get_form('container', jsonb_build_object('item_id', tests.item_id('Blue bag')))::jsonb as f) s),
  'Edit bag or box / update_item / Blue bag',
  'editing my bag'
);

select tests.act_as('Mai');

select tests.throws_error(
  format('select get_form(%L, %L)', 'container', jsonb_build_object('item_id', tests.item_id('Blue bag'))),
  'NOT_ALLOWED', 'You can''t change this.',
  'only the owner can edit a bag'
);

-- ---------------------------------------------------------------------
-- move_to_container
-- ---------------------------------------------------------------------

select tests.act_as('Sara');

select is(
  (select (f ->> 'title') || ' / ' || (f -> 'submit' ->> 'label') || ' / '
          || tests.option_labels(tests.field(f, 'container_id'))
   from (select get_form('move_to_container', jsonb_build_object('item_id', tests.item_id('Perfume', 'Sara')))::jsonb as f) s),
  'Move to bag / Move / Blue bag, Tote',
  'moving an item: a choice of my bags'
);

select is(
  tests.field(get_form('move_to_container', jsonb_build_object('item_id', tests.item_id('Perfume', 'Sara')))::jsonb,
              'container_id') -> 'default',
  to_jsonb(tests.item_id('Blue bag')),
  'the bag choice starts on the first bag (ruling)'
);

select is(
  tests.option_labels(tests.field(
    get_form('move_to_container', jsonb_build_object('item_id', tests.item_id('Hair clip')))::jsonb,
    'container_id')),
  'Tote',
  'without the bag it''s already in'
);

select tests.act_as('Mai');

select tests.throws_error(
  format('select get_form(%L, %L)', 'move_to_container', jsonb_build_object('item_id', tests.item_id('Giveaways'))),
  'NOT_ALLOWED', 'You can''t change this.',
  'only the claimer moves a claimed item (ruling)'
);

-- ---------------------------------------------------------------------
-- car
-- ---------------------------------------------------------------------

select tests.act_as('Nour');

select is(
  (select (f - 'fields') || jsonb_build_object('keys', tests.field_keys(f))
   from (select get_form('car', '{"trip": "to_hotel"}')::jsonb as f) s),
  '{"name": "car", "title": "I''m coming with my car", "context": {"trip": "to_hotel"},
    "submit": {"function": "register_car", "label": "Save"},
    "keys": "seats,departure_earliest,departure_latest,home_area,home_area_other,minutes_to_bride,minutes_to_hotel,stops,trunk_percent,notes"}',
  'To the hotel: the questions of BR-14, submitted to register_car'
);

select is(
  (select f - 'key' - 'type' - 'options' - 'default' - 'value' - 'visible_if' - 'fields'
   from (select tests.field(get_form('car', '{"trip": "to_hotel"}')::jsonb, 'departure_earliest') as f) s),
  '{"label": "Earliest time to leave home", "required": true,
    "hint": "Only choose times you''re truly fine with. The bride may pick any time in this window. Use 24-hour time, like 23:30."}',
  'the departure window carries the contract''s note and the 24-hour hint (ruling)'
);

select is(
  (select jsonb_object_agg(x ->> 'key', x -> 'default')
   from jsonb_array_elements(get_form('car', '{"trip": "to_hotel"}')::jsonb -> 'fields') x
   where x ->> 'type' in ('number', 'select'))
  || jsonb_build_object('stop purpose',
       tests.field(get_form('car', '{"trip": "to_hotel"}')::jsonb, 'stops') -> 'fields' -> 1 -> 'default'),
  '{"seats": 0, "minutes_to_bride": 0, "minutes_to_hotel": 0, "home_area": "maadi",
    "trunk_percent": "0", "stop purpose": "myself"}',
  'numbers start at 0 and dropdowns on their first option, in a new stop too (ruling)'
);

select is(
  tests.field(get_form('car', '{"trip": "to_hotel"}')::jsonb, 'home_area_other') -> 'visible_if',
  '{"field": "home_area", "equals": "other"}',
  'Other opens a text field (BR-14)'
);

select is(
  tests.field(get_form('car', '{"trip": "to_hotel"}')::jsonb, 'minutes_to_bride') ->> 'hint',
  'Check Google Maps for the estimate.',
  'travel times carry the Google Maps hint'
);

select is(
  (select (select string_agg(n ->> 'key', ',') from jsonb_array_elements(f -> 'fields') n)
          || ' / ' || tests.option_labels(f -> 'fields' -> 1)
   from (select tests.field(get_form('car', '{"trip": "to_hotel"}')::jsonb, 'stops') as f) s),
  'description,purpose / For myself, For the bride',
  'stops are a list, each For myself or For the bride'
);

select is(
  (select (f ->> 'required') || ' ' || tests.option_labels(f)
   from (select tests.field(get_form('car', '{"trip": "to_hotel"}')::jsonb, 'trunk_percent') as f) s),
  'true 0% (full), 25%, 50%, 75%, 100% (empty)',
  'trunk space is required (ruling)'
);

select is(
  tests.field(get_form('car', '{"trip": "to_hotel"}')::jsonb, 'notes') ->> 'hint',
  'Everyone can read this.',
  'notes say who can read them (BR-16)'
);

select is(
  (select tests.field_keys(f) || ' / ' || (tests.field(f, 'departure_earliest') ->> 'label')
   from (select get_form('car', '{"trip": "hotel_to_venue"}')::jsonb as f) s),
  'seats,departure_earliest,departure_latest,trunk_percent,notes / Earliest time to leave the hotel',
  'Hotel to venue: only its own questions (BR-15)'
);

select is(
  (select tests.field_keys(f) || ' / ' || (tests.field(f, 'departure_latest') ->> 'label')
          || ' / ' || (tests.field(f, 'dropoff_areas') ->> 'label')
          || ' / ' || (tests.field(f, 'dropoff_area_other') -> 'visible_if')::text
   from (select get_form('car', '{"trip": "return_home"}')::jsonb as f) s),
  'seats,departure_earliest,departure_latest,dropoff_areas,dropoff_area_other,trunk_percent,notes'
  || ' / Latest time to leave the venue / Areas I can drop people off in'
  || ' / {"field": "dropoff_areas", "equals": "other"}',
  'Return home: drop-off areas, with Other opening a text field (BR-15)'
);

select ok(
  tests.field(get_form('car', '{"trip": "return_home"}')::jsonb, 'departure_earliest') ->> 'hint'
    like '%The window can cross midnight, like 23:30 to 00:30.',
  'Return home says its window can cross midnight (ruling)'
);

select tests.act_as('Sara');

select tests.throws_error(
  $$ select get_form('car', '{"trip": "to_hotel"}') $$,
  'ALREADY_HAS_CAR', 'You already have a car on this trip.',
  'no second car on a trip'
);

select is(
  (select (f - 'fields') || jsonb_build_object('values', (
     select jsonb_object_agg(x ->> 'key', x -> 'value') from jsonb_array_elements(f -> 'fields') x
     where x ->> 'key' in ('seats', 'departure_earliest', 'home_area', 'stops', 'trunk_percent', 'notes')))
   from (select get_form('car', jsonb_build_object('car_id', tests.car_id('Sara')))::jsonb as f) s),
  jsonb_build_object(
    'name', 'car', 'title', 'Edit my car',
    'context', jsonb_build_object('car_id', tests.car_id('Sara')),
    'submit', jsonb_build_object('function', 'update_car', 'label', 'Save'),
    'values', '{"seats": 2, "departure_earliest": "09:00", "home_area": "maadi",
                "stops": [{"description": "Pharmacy", "purpose": "bride"}],
                "trunk_percent": "50", "notes": "Leaving from Maadi"}'::jsonb),
  'editing my car: its current values, submitted to update_car'
);

select tests.act_as('Mai');

select tests.throws_error(
  format('select get_form(%L, %L)', 'car', jsonb_build_object('car_id', tests.car_id('Sara'))),
  'NOT_ALLOWED', 'You can''t change this.',
  'only the owner can edit a car'
);

-- ---------------------------------------------------------------------
-- passenger_offer
-- ---------------------------------------------------------------------

select tests.act_as('Sara');

select is(
  (select (f - 'fields') || jsonb_build_object('who', tests.option_labels(tests.field(f, 'passenger_id')))
   from (select get_form('passenger_offer', jsonb_build_object('car_id', tests.car_id('Sara')))::jsonb as f) s),
  jsonb_build_object(
    'name', 'passenger_offer', 'title', 'Offer a seat',
    'context', jsonb_build_object('car_id', tests.car_id('Sara'), 'kind', 'passenger', 'direction', 'offer'),
    'submit', jsonb_build_object('function', 'send_request', 'label', 'Send offer'),
    'who', 'Bride (Bride), Mai (Maid of Honor), Nour (Bridesmaid), Rana (Bridesmaid)'),
  'offering a seat: everyone else, submitted to send_request as a passenger Offer'
);

select is(
  tests.field(get_form('passenger_offer', jsonb_build_object('car_id', tests.car_id('Sara')))::jsonb,
              'passenger_id') -> 'default',
  to_jsonb(tests.member_id('Bride')),
  'the passenger choice starts on the first name (ruling)'
);

select tests.act_as('Nour');
select send_request(tests.car_id('Sara'), 'passenger', 'ask', passenger_id => tests.member_id('Nour'));
select tests.act_as('Rana');
select send_request(tests.car_id('Bride'), 'passenger', 'ask', passenger_id => tests.member_id('Rana'));
select tests.act_as('Bride');
select respond_to_request(tests.request_on(tests.car_id('Bride'), 'Rana'), true);
select tests.act_as('Sara');

select is(
  tests.option_labels(tests.field(
    get_form('passenger_offer', jsonb_build_object('car_id', tests.car_id('Sara')))::jsonb, 'passenger_id')),
  'Bride (Bride), Mai (Maid of Honor)',
  'but not members with a pending request with this car, or a ride on this trip'
);

select tests.act_as('Mai');

select tests.throws_error(
  format('select get_form(%L, %L)', 'passenger_offer', jsonb_build_object('car_id', tests.car_id('Sara'))),
  'NOT_ALLOWED', 'You can''t change this.',
  'only the car owner offers seats in it'
);

-- ---------------------------------------------------------------------
-- cargo_request and cargo_offer
-- ---------------------------------------------------------------------

select tests.act_as('Sara');

select is(
  (select (f - 'fields') || jsonb_build_object(
     'what', tests.option_labels(tests.field(f, 'item_id')),
     'pickup', tests.option_labels(tests.field(f, 'pickup_type')))
   from (select get_form('cargo_request', jsonb_build_object('car_id', tests.car_id('Bride')))::jsonb as f) s),
  jsonb_build_object(
    'name', 'cargo_request', 'title', 'Ask to carry an item',
    'context', jsonb_build_object('car_id', tests.car_id('Bride'), 'kind', 'cargo', 'direction', 'ask'),
    'submit', jsonb_build_object('function', 'send_request', 'label', 'Send request'),
    'what', 'Blue bag, Giveaways, Perfume, Tote',
    'pickup', 'Bride''s home, Other address'),
  'asking to carry: my items that can travel, not the one in a bag, and no vendor address to pick from'
);

select tests.throws_error(
  format('select get_form(%L, %L)', 'cargo_request', jsonb_build_object('car_id', tests.car_id('Sara'))),
  'OWN_CAR', 'That''s your own car.',
  'I don''t ask my own car'
);

select tests.act_as('Nour');
select claim_item(tests.item_id('Flowers'));

select is(
  (select tests.option_labels(tests.field(f, 'item_id')) || ' / '
          || tests.option_labels(tests.field(f, 'pickup_type')) || ' / '
          || (select (o -> 'visible_if')::text from jsonb_array_elements(tests.field(f, 'pickup_type') -> 'options') o
              where o ->> 'value' = 'vendor_address')
   from (select get_form('cargo_request', jsonb_build_object('car_id', tests.car_id('Bride')))::jsonb as f) s),
  'Flowers / Bride''s home, Vendor''s address, Other address / '
  || jsonb_build_object('field', 'item_id', 'equals', jsonb_build_array(tests.item_id('Flowers')))::text,
  'the vendor''s address is offered only for items whose vendor has one (BR-24)'
);

select is(
  (select jsonb_build_object('item_id', tests.field(f, 'item_id') -> 'default',
                             'pickup_type', tests.field(f, 'pickup_type') -> 'default')
   from (select get_form('cargo_request', jsonb_build_object('car_id', tests.car_id('Bride')))::jsonb as f) s),
  jsonb_build_object('item_id', tests.item_id('Flowers'), 'pickup_type', 'bride_home'),
  'the cargo choices start on the first item and the bride''s home (ruling)'
);

select is(
  (select (tests.field(f, 'pickup_address') - 'key' - 'type' - 'options' - 'default' - 'value' - 'fields' - 'hint')
          || jsonb_build_object('ready_at_hint', tests.field(f, 'ready_at') ->> 'hint')
   from (select get_form('cargo_request', jsonb_build_object('car_id', tests.car_id('Bride')))::jsonb as f) s),
  '{"label": "Pickup address", "required": true, "visible_if": {"field": "pickup_type", "equals": "custom"},
    "ready_at_hint": "Use 24-hour time, like 23:30."}',
  'a custom pickup needs an address; the ready time asks for 24-hour time'
);

select create_item(name => 'Diary');
select tests.act_as('Sara');

select is(
  (select (f ->> 'title') || ' / ' || (f -> 'context' ->> 'direction') || ' / '
          || (f -> 'submit' ->> 'label') || ' / ' || tests.option_labels(tests.field(f, 'item_id'))
   from (select get_form('cargo_offer', jsonb_build_object('car_id', tests.car_id('Sara')))::jsonb as f) s),
  'Offer to carry an item / offer / Send offer / Flowers (Nour), Perfume (Mai)',
  'offering to carry: other members'' items I can see, with their owners, but not private or unclaimed ones'
);

select tests.act_as('Nour');

select tests.throws_error(
  format('select get_form(%L, %L)', 'cargo_offer', jsonb_build_object('car_id', tests.car_id('Sara'))),
  'NOT_ALLOWED', 'You can''t change this.',
  'only the car owner offers to carry in it'
);

select * from finish();
rollback;
