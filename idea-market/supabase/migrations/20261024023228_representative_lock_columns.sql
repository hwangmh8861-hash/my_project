-- Representative ownership, admin-only identity and projector controls. Existing investments are preserved.
alter table idea_private.teams add column if not exists representative_name text check(representative_name is null or (length(btrim(representative_name)) between 1 and 30));
alter table idea_private.teams add column if not exists joined_at timestamptz;
alter table idea_private.room add column if not exists presentation jsonb not null default '{"page":0,"auto":true,"at":null,"version":0}'::jsonb;
