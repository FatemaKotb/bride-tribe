-- list_members_for_login, sign_in, sign_out (contract Section 2, BR-03).
begin;
\ir _helpers.psql

select plan(24);

select tests.reset_members();

-- ---------------------------------------------------------------------
-- list_members_for_login
-- ---------------------------------------------------------------------

select has_function('public', 'list_members_for_login', array[]::name[]);

select tests.no_session();

select is(
  list_members_for_login()::jsonb,
  jsonb_build_object('members', jsonb_build_array(
    jsonb_build_object('id', tests.member_id('Bride'), 'name', 'Bride', 'role_label', 'Bride'),
    jsonb_build_object('id', tests.member_id('Mai'),   'name', 'Mai',   'role_label', 'Maid of Honor'),
    jsonb_build_object('id', tests.member_id('Nour'),  'name', 'Nour',  'role_label', 'Bridesmaid'),
    jsonb_build_object('id', tests.member_id('Sara'),  'name', 'Sara',  'role_label', 'Bridesmaid')
  )),
  'list_members_for_login works with no session and lists names and roles, by role then name'
);

select tests.new_session('signed-out phone');

select is(
  jsonb_array_length(list_members_for_login()::jsonb -> 'members'),
  4,
  'list_members_for_login works for a session not linked to a member'
);

update option_label set label = 'Bridesmaid ✿' where option_set = 'role' and value = 'bridesmaid';

select is(
  list_members_for_login()::jsonb #>> '{members,3,role_label}',
  'Bridesmaid ✿',
  'role labels come from option_label'
);

update option_label set label = 'Bridesmaid' where option_set = 'role' and value = 'bridesmaid';

-- ---------------------------------------------------------------------
-- sign_in
-- ---------------------------------------------------------------------

select has_function('public', 'sign_in', array['uuid']);

select tests.new_session('phone A');

select is(
  sign_in(tests.member_id('Sara'))::jsonb,
  jsonb_build_object('me', jsonb_build_object(
    'id', tests.member_id('Sara'), 'name', 'Sara', 'role_label', 'Bridesmaid')),
  'sign_in returns me with id, name, and role label'
);

select is(current_member_id(), tests.member_id('Sara'), 'sign_in links the session to the member');

select sign_in(tests.member_id('Nour'));

select is(current_member_id(), tests.member_id('Nour'), 'signing in again on the same phone re-links it');

select is(
  (select count(*)::int from member_session
   where auth_user_id = (select auth_user_id from tests.session where label = 'phone A')),
  1,
  'a phone has one link at a time'
);

select tests.new_session('phone B');
select sign_in(tests.member_id('Nour'));

select is(
  (select count(*)::int from member_session where member_id = tests.member_id('Nour')),
  2,
  'a member can be signed in on several phones'
);

select tests.throws_error(
  format('select sign_in(%L)', gen_random_uuid()),
  'UNKNOWN_MEMBER', 'We couldn''t find that name.',
  'sign_in rejects an unknown member'
);

select tests.throws_error(
  'select sign_in(null)',
  'UNKNOWN_MEMBER', 'We couldn''t find that name.',
  'sign_in rejects a missing member id'
);

select is(current_member_id(), tests.member_id('Nour'), 'a failed sign_in keeps the existing link');

select tests.no_session();

select tests.throws_error(
  format('select sign_in(%L)', tests.member_id('Sara')),
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'sign_in needs a Supabase session to link'
);

-- ---------------------------------------------------------------------
-- sign_out
-- ---------------------------------------------------------------------

select has_function('public', 'sign_out', array[]::name[]);

select tests.throws_error(
  'select sign_out()',
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'sign_out without a session raises NOT_SIGNED_IN'
);

select tests.use_session('signed-out phone');

select tests.throws_error(
  'select sign_out()',
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'sign_out on a session not linked to a member raises NOT_SIGNED_IN'
);

select tests.use_session('phone A');
select sign_out();

select is(current_member_id(), null, 'sign_out unlinks the session');

select is(
  (select count(*)::int from member_session
   where auth_user_id = (select auth_user_id from tests.session where label = 'phone A')),
  0,
  'sign_out deletes the session''s link'
);

select tests.throws_error(
  'select sign_out()',
  'NOT_SIGNED_IN', 'Please pick your name to continue.',
  'signing out twice raises NOT_SIGNED_IN'
);

select tests.use_session('phone B');

select is(current_member_id(), tests.member_id('Nour'), 'sign_out leaves the member''s other phones signed in');

select tests.use_session('phone A');

select is(
  sign_in(tests.member_id('Sara'))::jsonb #>> '{me,name}',
  'Sara',
  'a phone can sign in again after signing out (Not Sara? Switch)'
);

-- ---------------------------------------------------------------------
-- list_members_for_login with no members
-- ---------------------------------------------------------------------

delete from member;

select is(list_members_for_login()::jsonb, '{"members": []}'::jsonb, 'with no members, the list is empty');

select is(current_member_id(), null, 'deleting a member removes their sessions');

select * from finish();
rollback;
