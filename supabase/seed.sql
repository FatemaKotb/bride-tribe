-- The bridal party (BR-01, BR-03). `npx supabase db reset` loads it into
-- the local database, and `npx supabase db push --include-seed` into the
-- hosted one (docs/deployment.md). Names already there are skipped, so
-- it can run again after a name is added.
insert into member (name, role) values
  ('Wana', 'bride'),
  ('Ghooda', 'maid_of_honor'),
  ('Sara', 'bridesmaid'),
  ('Malooka', 'bridesmaid'),
  ('Ruba', 'bridesmaid'),
  ('Logy', 'bridesmaid'),
  ('Pery', 'bridesmaid'),
  ('Hidhid', 'bridesmaid'),
  ('Fatema', 'bridesmaid'),
  ('Esraa', 'bridesmaid'),
  ('Habhooba', 'bridesmaid'),
  ('Moina', 'bridesmaid'),
  ('Rooka', 'bridesmaid'),
  ('Shymaa', 'bridesmaid'),
  ('Habiba', 'bridesmaid'),
  ('Fagr', 'bridesmaid')
on conflict (name) do nothing;
