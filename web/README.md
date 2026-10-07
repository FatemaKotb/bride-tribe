# Bride Tribe web app

The phone app for the bridal party. It is a thin client: every screen renders
what the Postgres functions return (see `docs/wedding-app-backend-contract.md`),
and every button calls the function the backend names.

## Run it locally

1. Start the local backend from the repository root:

   ```bash
   npx supabase start
   npx supabase db reset   # optional: back to the four test members
   ```

2. Create `web/.env.local` from `web/.env.example`. The values come from
   `npx supabase status -o env` (`API_URL` and `ANON_KEY`).

3. Install and start the app:

   ```bash
   cd web
   npm install
   npm run dev
   ```

   Open <http://localhost:5173> and pick a test member.

## Try it on a phone

The phone must be on the same Wi-Fi as this computer.

1. Find this computer's address (on Windows, `ipconfig`, the Wi-Fi adapter's
   IPv4 address, for example `192.168.1.224`).
2. In `web/.env.local`, set `VITE_SUPABASE_URL=http://<that address>:54321`.
   The phone can't reach `127.0.0.1`, which on the phone means the phone.
3. Start the app so other devices can reach it: `npm run dev -- --host`.
4. On the phone, open `http://<that address>:5173`.

If the phone can't connect, allow Node.js and Docker through the Windows
firewall for private networks (Windows usually asks the first time).

Installing the app on the home screen needs HTTPS, so it works once the app is
deployed, not over the local address.

## Other commands

- `npm run build`: type-check and build to `dist/`.
- `npm run lint`: lint with Oxlint.
- `node scripts/make-icons.mjs`: redraw the app icons in `public/`.
