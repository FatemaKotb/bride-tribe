-- set_status and clear_attention (contract Section 4, BR-26, BR-27, BR-34).
begin;
\ir _helpers.psql

select plan(17);

select tests.reset_members();

-- Push every timestamp into the past so "set to now()" is observable.
update member set status_updated_at    = now() - interval '1 hour',
                  attention_cleared_at = now() - interval '1 hour';

-- ---------------------------------------------------------------------
-- set_status
-- ---------------------------------------------------------------------

select has_function('public', 'set_status', array['text']);

select tests.no_session();

select tests.throws_error(
  'select set_status(''doing_makeup'')',
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'set_status without a session raises NOT_SIGNED_IN'
);

select tests.new_session('signed-out phone');

select tests.throws_error(
  'select set_status(''doing_makeup'')',
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'set_status on a session not linked to a member raises NOT_SIGNED_IN'
);

select is(
  (select status::text from member where name = 'Sara'), 'at_home',
  'a member starts At home'
);

select tests.act_as('Sara');
select set_status('doing_makeup');

select is(
  (select status::text from member where name = 'Sara'), 'doing_makeup',
  'set_status sets my status'
);

select is(
  (select status_updated_at from member where name = 'Sara'), now(),
  'set_status records when my status changed'
);

select is(
  (select status::text || ' ' || (status_updated_at < now())::text from member where name = 'Mai'),
  'at_home true',
  'set_status leaves other members alone'
);

select tests.throws_error(
  'select set_status(''sleeping'')',
  'INVALID_STATUS', 'Please choose a status from the list.',
  'set_status rejects a status that isn''t in the list'
);

select tests.throws_error(
  'select set_status('''')',
  'INVALID_STATUS', 'Please choose a status from the list.',
  'set_status rejects an empty status'
);

select tests.throws_error(
  'select set_status(null)',
  'INVALID_STATUS', 'Please choose a status from the list.',
  'set_status rejects a missing status'
);

select tests.throws_error(
  'select set_status(''Doing makeup'')',
  'INVALID_STATUS', 'Please choose a status from the list.',
  'set_status takes the value, not the label'
);

select is(
  (select status::text from member where name = 'Sara'), 'doing_makeup',
  'a rejected status leaves my status unchanged'
);

select lives_ok(
  $$ select set_status(s::text) from unnest(enum_range(null::member_status)) s $$,
  'set_status accepts every status in the list'
);

-- ---------------------------------------------------------------------
-- clear_attention
-- ---------------------------------------------------------------------

select has_function('public', 'clear_attention', array[]::name[]);

select tests.no_session();

select tests.throws_error(
  'select clear_attention()',
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'clear_attention without a session raises NOT_SIGNED_IN'
);

select tests.act_as('Sara');
select clear_attention();

select is(
  (select attention_cleared_at from member where name = 'Sara'), now(),
  'clear_attention sets my attention_cleared_at to now'
);

select is(
  (select attention_cleared_at < now() from member where name = 'Mai'), true,
  'clear_attention leaves other members alone'
);

select * from finish();
rollback;
