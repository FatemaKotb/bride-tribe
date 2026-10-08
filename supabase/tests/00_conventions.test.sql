-- Conventions that hold for every function, whatever phase added it
-- (implementation guide Section 4).
begin;
\ir _helpers.psql

select plan(5);

-- Every function in the contract (Sections 2 to 4). Functions from later
-- phases are checked once they exist.
create temp table contract_function (name text primary key);
insert into contract_function (name) values
  ('list_members_for_login'), ('sign_in'), ('sign_out'),
  ('get_home'), ('list_items'), ('list_bags'), ('get_item'), ('list_cars'), ('get_car'),
  ('list_requests'), ('get_form'),
  ('set_status'), ('clear_attention'),
  ('create_item'), ('update_item'), ('create_container'), ('delete_item'),
  ('claim_item'), ('release_claim'), ('set_packed'), ('move_to_container'),
  ('register_car'), ('update_car'), ('withdraw_car'),
  ('send_request'), ('respond_to_request'), ('cancel_request'), ('leave_car');

create temp view public_function as
  select p.oid, p.proname::text as name,
         p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as signature,
         p.prosecdef, p.proconfig
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public';

select is_empty(
  $$ select signature from public_function
     where has_function_privilege('anon', oid, 'execute')
       and name <> 'list_members_for_login' $$,
  'anon (and so PUBLIC) can execute no function except list_members_for_login'
);

select is_empty(
  $$ select signature from public_function
     where has_function_privilege('authenticated', oid, 'execute')
       and name not in (select name from contract_function) $$,
  'authenticated can execute only contract functions, never internal helpers'
);

select is_empty(
  $$ select signature from public_function
     where name in (select name from contract_function)
       and not has_function_privilege('authenticated', oid, 'execute') $$,
  'authenticated can execute every contract function'
);

select is_empty(
  $$ select signature from public_function
     where name in (select name from contract_function)
       and not (prosecdef and proconfig @> array['search_path=public']) $$,
  'every contract function is security definer with search_path = public'
);

-- The UI builds every badge and dropdown from option_label, so every
-- value of a labelled enum needs a label.
select is_empty(
  $$ select s.option_set || '.' || e.value
     from (values
       ('role', 'member_role'), ('status', 'member_status'),
       ('item_kind', 'item_kind'), ('item_visibility', 'item_visibility'),
       ('item_type', 'item_type'), ('trip', 'trip'), ('area', 'area'),
       ('stop_purpose', 'stop_purpose'), ('request_state', 'request_state'),
       ('pickup_type', 'pickup_type'), ('request_kind', 'request_kind'),
       ('cancel_reason', 'cancel_reason')
     ) as s (option_set, enum_type)
     cross join lateral (
       select enumlabel::text as value from pg_enum
       where enumtypid = s.enum_type::regtype
     ) e
     where not exists (
       select 1 from option_label l
       where l.option_set = s.option_set and l.value = e.value
     ) $$,
  'every value of a labelled enum has an option_label'
);

select * from finish();
rollback;
