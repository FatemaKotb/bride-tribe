-- =====================================================================
-- Sign-in and status functions (contract Sections 2 and 4, BR-03,
-- BR-26, BR-27, BR-34)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Internal helper (not callable through the API)
-- ---------------------------------------------------------------------

-- The signed-in member, or NOT_SIGNED_IN. Every contract function except
-- list_members_for_login and sign_in starts with this.
create function require_member() returns uuid
language plpgsql stable set search_path = public as $$
declare
  me uuid := current_member_id();
begin
  if me is null then
    raise exception using
      message = 'Please pick your name to continue.',
      hint    = 'NOT_SIGNED_IN';
  end if;
  return me;
end;
$$;

revoke all on function require_member() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. Sign-in (BR-03, BR-03a)
-- ---------------------------------------------------------------------

-- The only read that works before a member is chosen. Names and roles
-- only, ordered like the status board: by role, then name.
create function list_members_for_login() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'members', coalesce(json_agg(
      json_build_object('id', m.id, 'name', m.name, 'role_label', r.label)
      order by r.sort_order, m.name
    ), '[]'::json)
  )
  from member m
  left join option_label r on r.option_set = 'role' and r.value = m.role::text;
$$;

-- Links the caller's Supabase session (started with signInAnonymously)
-- to the chosen member. Signing in again on the same phone re-links it.
create function sign_in(member_id uuid) returns json
language plpgsql security definer set search_path = public as $$
declare
  chosen member%rowtype;
begin
  if auth.uid() is null then
    raise exception using
      message = 'Please pick your name to continue.',
      hint    = 'NOT_SIGNED_IN';
  end if;

  select * into chosen from member where id = sign_in.member_id;
  if not found then
    raise exception using
      message = 'We couldn''t find that name.',
      hint    = 'UNKNOWN_MEMBER';
  end if;

  insert into member_session (auth_user_id, member_id)
  values (auth.uid(), chosen.id)
  on conflict (auth_user_id) do update
    set member_id = excluded.member_id, created_at = now();

  return json_build_object('me', json_build_object(
    'id', chosen.id,
    'name', chosen.name,
    'role_label', (select label from option_label
                   where option_set = 'role' and value = chosen.role::text)
  ));
end;
$$;

-- Unlinks this session only. The member's other phones stay signed in.
create function sign_out() returns void
language plpgsql security definer set search_path = public as $$
begin
  perform require_member();
  delete from member_session where auth_user_id = auth.uid();
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Status (BR-26, BR-27, BR-34)
-- ---------------------------------------------------------------------

-- Takes text, not member_status, so an unknown value reaches the body
-- and fails with INVALID_STATUS instead of a cast error.
create function set_status(status text) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := require_member();
begin
  if set_status.status is null
     or not (set_status.status = any (enum_range(null::member_status)::text[])) then
    raise exception using
      message = 'Please choose a status from the list.',
      hint    = 'INVALID_STATUS';
  end if;

  update member
  set status = set_status.status::member_status,
      status_updated_at = now()
  where id = me;
end;
$$;

-- "Got it" on the home screen: hides cancellations seen so far. Pending
-- requests stay until answered.
create function clear_attention() returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := require_member();
begin
  update member set attention_cleared_at = now() where id = me;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Access: anonymous sessions use the authenticated role
-- ---------------------------------------------------------------------

revoke all on function
  list_members_for_login(), sign_in(uuid), sign_out(), set_status(text), clear_attention()
  from public, anon;

grant execute on function
  list_members_for_login(), sign_in(uuid), sign_out(), set_status(text), clear_attention()
  to authenticated;

-- The one exception: the name list also works with the bare anon key, so
-- the keep-alive workflow can call it without creating a session. It
-- returns only names and roles, which anyone with the app link sees anyway.
grant execute on function list_members_for_login() to anon;
