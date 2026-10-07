# Deployment

The backend runs on a free Supabase project, and the app on GitHub Pages.
Both are free and need no credit card. Two GitHub Actions workflows are in
this repository:

- **Deploy** (`.github/workflows/deploy.yml`) builds `web/` and publishes it
  to GitHub Pages on every push to `main`.
- **Keep Supabase awake** (`.github/workflows/keep-alive.yml`) calls the
  backend every 3 days, so the free project is never paused.

You do the steps below by hand, once. Run the commands from the repository
root.

## 1. Create the Supabase project

1. Sign in at [supabase.com](https://supabase.com) and create a new project
   on the free plan.
   - Pick the region closest to Cairo, such as Central EU (Frankfurt).
   - Generate a strong database password and keep it in a password manager.
     It never goes in the repository.
2. Turn on anonymous sign-ins: **Authentication → Sign In / Providers →
   Allow anonymous sign-ins**, then save. Without this, the name list loads
   but "Yes, that's me" fails with "Something went wrong."
3. Note two values for step 4:
   - the **Project URL**, `https://<project-ref>.supabase.co`
     (Project Settings → Data API), and
   - the **publishable key**, `sb_publishable_…` (Project Settings → API
     Keys). The legacy `anon` key works too.

   Never use the secret key or the `service_role` key anywhere in this
   project.

## 2. Push the database

```bash
npx supabase login
npx supabase link --project-ref <project-ref>
npx supabase db push --dry-run        # lists the 6 migrations it will apply
npx supabase db push --include-seed
```

`link` asks for the database password. `--include-seed` also loads
`supabase/seed.sql`, the bridal party.

To check, open **Table Editor → member** in the dashboard. It should list
16 members: Wana (Bride), Ghooda (Maid of Honor), and 14 bridesmaids.

## 3. Change the bridal party later

- **Add someone:** add a line to `supabase/seed.sql`, then run
  `npx supabase db push --include-seed` again. Names already in the
  database are skipped. Roles are `bride`, `maid_of_honor`, or `bridesmaid`,
  and every name must be different.
- **Rename someone,** in the dashboard's SQL Editor:

  ```sql
  update member set name = 'New name' where name = 'Old name';
  ```

  Update `supabase/seed.sql` to match, so a later push doesn't add the old
  name back.
- **Remove someone** only before she uses the app:

  ```sql
  delete from member where name = 'Name';
  ```

  Once she has items, a car, or requests, the database refuses the delete.

## 4. Set up GitHub

1. **Make the repository public:** Settings → General → Danger Zone →
   Change visibility. GitHub Pages is free only for public repositories.
   This publishes everything in the repository, including the names in
   `supabase/seed.sql` and the git history. Anyone with the app's link can
   see the names anyway, on the sign-in screen.
2. **Add the secrets:** Settings → Secrets and variables → Actions → New
   repository secret.

   | Name | Value |
   |---|---|
   | `SUPABASE_URL` | the Project URL from step 1 |
   | `SUPABASE_ANON_KEY` | the publishable key from step 1 |

   The key isn't really secret: it ships inside the app, and every read and
   write goes through the backend's functions.
3. **Turn on Pages:** Settings → Pages → Build and deployment → Source:
   **GitHub Actions**.

## 5. Deploy

Push `main`:

```bash
git push origin main
```

The **Deploy** workflow builds the app and publishes it. Follow it in the
repository's Actions tab, or start it by hand with **Actions → Deploy → Run
workflow**. The app is then at <https://fatemakotb.github.io/bride-tribe/>.

To check it, open the link on a phone, pick a name, and confirm it. To
install the app:

- **Android (Chrome):** menu → Add to Home screen (or Install app).
- **iPhone (Safari):** Share → Add to Home Screen.

## 6. Keep the project awake

Supabase pauses a free project after a week without activity. The **Keep
Supabase awake** workflow calls `list_members_for_login` every 3 days.

- Run it once now: **Actions → Keep Supabase awake → Run workflow**. Its log
  should end with "Supabase answered with 16 members."
- GitHub turns off scheduled workflows in a public repository after 60 days
  without a commit, and emails a warning first. To turn it back on, open it
  in the Actions tab and choose **Enable workflow**.
- If the project is paused anyway, restore it from the Supabase dashboard.

## Later changes

- **The app:** push to `main`. The Deploy workflow republishes it, and
  phones pick up the new version the next time the app is opened.
- **The database:** add a migration, then run `npx supabase db push`.

## If something goes wrong

| What you see | What to check |
|---|---|
| Deploy fails with "Add the SUPABASE_URL and SUPABASE_ANON_KEY repository secrets" | Step 4.2 |
| The name list says "Something went wrong" | The two secrets: the Project URL and the key. Fix them and run Deploy again. |
| "Yes, that's me" says "Something went wrong" | Anonymous sign-ins (step 1.2) |
| The app's link shows a 404 | Pages' source is GitHub Actions (step 4.3), and Deploy finished |
| Keep Supabase awake fails | The two secrets, and whether the project is paused |

Supabase allows 30 anonymous sign-ins per hour from one IP address by
default (Authentication → Rate Limits). Each phone signs in once, so the
whole party fits even on one Wi-Fi network.
