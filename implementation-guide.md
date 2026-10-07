# Implementation Guide

This file tells you, the coding agent, how to build this project. Read it fully before doing anything, then follow the phases in order.

## 0. Ground Rules

- **The design documents are the source of truth.** They are in `docs/`:
  - `wedding-app-requirements.md`: what the app does (BR-01 to BR-34).
  - `wedding-app-erd.md`: the data model, constraints, and triggers.
  - `wedding-app-backend-contract.md`: every endpoint, function, form, and error code.
- **Don't change the design documents.** If something in them is ambiguous, contradictory, or impossible to build, stop and ask. Don't guess, and don't silently work around it.
- **Stop at every checkpoint** (marked ⏸) and wait for approval before starting the next phase.
- **Commit at the end of each phase** with a clear message. Don't push unless asked.
- **Never use paid services or anything that needs a credit card.** The budget is $0.
- **Never touch the hosted Supabase project** (link, push, or seed) unless explicitly asked. All work happens against the local Supabase instance.
- **Never commit secrets.** The Supabase anon key may appear in frontend config. The service role key must never appear anywhere in the repository.

## 1. Architecture

- **All business logic lives in Postgres functions (PL/pgSQL).** The UI contains no business rules.
- **The browser never touches tables.** Row-level security is enabled with no policies, and table privileges are revoked. Every read and write goes through a function from the contract.
- **Functions are called through Supabase's automatic API** (PostgREST RPC): `supabase.rpc('function_name', args)`.
- **The UI is thin.** It renders exactly what the backend returns: Rows, Actions, Filters, and Form schemas, as defined in contract Section 1. It never decides which buttons to show, which options are valid, or what a label says.
- **Sign-in uses Supabase anonymous sessions.** The UI calls `supabase.auth.signInAnonymously()`, then `sign_in(member_id)` links the session to a member in `member_session`. `current_member_id()` identifies "me" in every function.
- **No real-time subscriptions.** The home screen polls `get_home` every 30 seconds and refreshes whenever the app returns to the foreground. Every screen reloads after any successful action.

## 2. Stack

| Layer | Choice |
|---|---|
| Database and logic | Postgres on Supabase (free plan), PL/pgSQL functions |
| Backend tests | pgTAP, run with `npx supabase test db` |
| Local backend | Supabase CLI (`npx supabase`) with Docker |
| Frontend | React, TypeScript, Vite, in the `web/` folder |
| UI components | Mantine (no custom CSS beyond trivial layout) |
| Backend client | `@supabase/supabase-js` |
| Installable app | `vite-plugin-pwa` |
| Routing | `HashRouter` (required for GitHub Pages) |
| Hosting | GitHub Pages, deployed by GitHub Actions |

Don't add other libraries without asking.

## 3. Repository Layout

```
docs/                     design documents (read-only)
supabase/
  config.toml
  migrations/             schema and function migrations
  seed.sql                local test members only
  tests/                  pgTAP tests
web/                      React frontend
.github/workflows/        deploy and keep-alive workflows
implementation-guide.md   this file
```

## 4. Backend Conventions

### Functions
- Every contract function is created in the `public` schema with:
  - `language plpgsql` (or `sql` for simple reads),
  - `security definer`,
  - `set search_path = public`.
- Grant `execute` only to `authenticated`. Revoke from `anon` and `public`. (Anonymous sessions use the `authenticated` role.)
- Every function except `list_members_for_login` and `sign_in` first checks `current_member_id()` and raises `NOT_SIGNED_IN` if it is null.
- Every write function runs its checks and changes in a single transaction (a single function call already is one).
- Read functions return `json` in the exact shapes from the contract (List response, Detail response, Form schema).
- Write functions return the updated object as `json`, or nothing if the contract doesn't specify a return.

### Errors
- Raise every error in this form, with the user-facing message as `message` and the contract's error code as `hint`:

  ```sql
  raise exception using
    message = format('%s''s car has no free seats.', owner_name),
    hint    = 'CAR_FULL';
  ```

- Use the messages from contract Section 6, with real names filled in where relevant.
- Update the two integrity triggers in the existing schema migration (`check_item_integrity` and `check_vendor_details_integrity`) to use this same form.
- The frontend converts PostgREST errors into the contract's envelope: `{ code: error.hint, message: error.message }`. If `hint` is missing, use code `UNEXPECTED` and the message "Something went wrong. Please try again."

### Display text
- All labels come from the `option_label` table. Don't hard-code labels in functions or the UI.
- Format times as "9:00 am" and relative times as "12 min ago." Use the `Africa/Cairo` time zone.
- Amounts are shown as "2,000 EGP."

### Tests
- Write pgTAP tests in `supabase/tests/` for every function and every rule, including every error code it can raise.
- Tests must cover the automatic effects, for example:
  - confirming a request cancels the subject's other pending requests on the same trip,
  - filling the last seat cancels the car's remaining pending passenger requests,
  - withdrawing a car cancels its requests,
  - releasing a claim removes the item from its container and cancels its cargo requests, and
  - moving an item into a container cancels its own cargo requests.
- To act as a member in a test, insert a row in `auth.users` and `member_session`, then set the JWT claim:
  `select set_config('request.jwt.claims', json_build_object('sub', '<auth uuid>', 'role', 'authenticated')::text, true);`
- All tests must pass before every checkpoint.

## 5. Frontend Conventions

- **Generic components only:**
  - `ListScreen`: renders a List response (filters as chips, rows, screen actions, empty message).
  - `DetailScreen`: renders a Detail response.
  - `FormScreen`: renders a Form schema, including `visible_if`, `group`, and `list` fields, and submits to `submit.function`.
  - `ActionButton`: renders an Action. It handles `confirm`, `call`, and `form`, then reloads the current screen.
  - `RowCard`: renders a Row.
- **Screens:** sign-in (name list and confirmation), Home, Items, Cars, Requests. Every screen except sign-in shows the header "Sara · Doing makeup" with a status picker and a "Not Sara? Switch" link.
- **Navigation:** a bottom tab bar with Home, Items, Cars, and Requests.
- **Types:** define the contract's shapes (Row, Action, Filter, List response, Detail response, Field, Form schema) as TypeScript types in one file.
- **Mobile-first:** design for a 375 px wide phone screen first. Use Mantine's default theme.
- **Config:** read `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` from environment variables. Provide a `web/.env.example`.
- **PWA:** the app is installable, with a name, icon, and theme color. Cache the app shell so it opens with a weak signal.

## 6. Phases

### Phase 1: Environment checks
Run these and report the results:

```bash
node --version
npm --version
docker --version
docker info
npx supabase --version
git status
```

If anything is missing or Docker isn't running, stop and say exactly what needs to be installed or started.

### Phase 2: Supabase setup
1. Run `npx supabase init` if `supabase/` doesn't exist yet.
2. Create a migration with `npx supabase migration new schema`, and copy the contents of `schema.sql` (provided alongside this guide) into it. Leave out the commented-out member seed block at the end.
3. In `supabase/config.toml`, under `[auth]`, set `enable_anonymous_sign_ins = true`.
4. Create `supabase/seed.sql` with test members:

   ```sql
   insert into member (name, role) values
     ('Test Bride', 'bride'),
     ('Test MoH', 'maid_of_honor'),
     ('Test Sara', 'bridesmaid'),
     ('Test Mai', 'bridesmaid');
   ```

5. Run `npx supabase start`, then `npx supabase db reset`. Both must succeed.
6. Confirm the tables exist, for example:
   `npx supabase db execute "select name, role from member"` (or use `psql` with the local connection string).
7. Update the two integrity triggers to the error convention in Section 4.

⏸ **Checkpoint:** report the results and commit.

### Phase 3: Sign-in and status functions
Implement `list_members_for_login`, `sign_in`, `sign_out`, `set_status`, and `clear_attention`, with tests.

⏸ **Checkpoint.**

### Phase 4: Item and container functions
Implement `create_item`, `update_item`, `create_container`, `delete_item`, `claim_item`, `release_claim`, `set_packed`, and `move_to_container`, with tests.

⏸ **Checkpoint.**

### Phase 5: Car functions
Implement `register_car`, `update_car`, and `withdraw_car`, including stops and drop-off areas, with tests.

⏸ **Checkpoint.**

### Phase 6: Request functions
Implement `send_request`, `respond_to_request`, `cancel_request`, and `leave_car`, with tests for every automatic cancellation.

⏸ **Checkpoint.**

### Phase 7: Read endpoints and forms
Implement `get_home`, `list_items`, `get_item`, `list_cars`, `get_car`, `list_requests`, and `get_form` for every form in contract Section 5. Test that each returns the correct shape, and that each row's `actions` match the "when shown" rules in the contract.

⏸ **Checkpoint.**

### Phase 8: Frontend
1. Scaffold `web/` with Vite (React and TypeScript), then add Mantine, `supabase-js`, and `vite-plugin-pwa`.
2. Add the contract types, the generic components, the screens, and navigation.
3. Run it against the local Supabase and check every screen with the test members, at phone width.

⏸ **Checkpoint:** describe how to run it locally so the work can be tried on a phone.

### Phase 9: Deployment setup
1. Add a GitHub Actions workflow that builds `web/` and deploys it to GitHub Pages on every push to `main`. Read the Supabase URL and anon key from repository secrets.
2. Add a scheduled GitHub Actions workflow that calls `list_members_for_login` every 3 days, so the free Supabase project never pauses for inactivity.
3. Write `docs/deployment.md` with the manual steps for the project owner:
   - create the hosted Supabase project and enable anonymous sign-ins,
   - link it and push the migrations,
   - add the real bridal party members,
   - add the repository secrets, and
   - enable GitHub Pages.

⏸ **Checkpoint:** don't run any of the hosted steps yourself.
