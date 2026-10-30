-- One row per skater per challenge: when they first cleared it, and how often since.
-- Applied as the schema owner (see server/README.md, "Database").

create table clears (
	challenge text not null check (challenge ~ '^[a-z0-9_]{1,64}$'),
	skater text not null check (skater ~ '^[A-Z]{3}[0-9]{2}$'),
	clears integer not null default 1,
	first_cleared_at timestamptz not null default now(),
	last_cleared_at timestamptz not null default now(),
	primary key (challenge, skater)
);

-- The board order: first clear first.
create index clears_board on clears (challenge, first_cleared_at, skater);

-- The API's login role reads and records clears, nothing else.
grant select, insert, update on clears to skatelike_api;
