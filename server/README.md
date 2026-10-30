# skatelike server: scoreboard API

Each challenge has a global scoreboard: the skaters who cleared it, in the order they
first did. Clearing it again only bumps your count. Live at `https://skatelike.com/api/`.

Fastify + TypeScript + postgres.js. Node 22.18+ runs the `.ts` files directly by stripping
the types, so there's no build step (only erasable TypeScript syntax: no enums, no
parameter properties). `tsc` only checks the types.

It's raw on purpose. Names are the game's 3 letters + 2 digits with no account behind
them, and a clear is whatever the client reports. The only protection is validation and
a per-IP rate limit.

## API

Paths as the game sees them (servi2's edge strips `/api` before proxying):

| Request | Response |
|---|---|
| `GET /api/scoreboards/<challenge>` | `200 {challenge, total, clears: [{skater, clears, first_cleared_at}]}`, first 100 by first clear. `404` for an unknown challenge |
| `POST /api/scoreboards/<challenge>/clears` with `{"skater": "DHZ07"}` | `201` on a first clear, `200` on a repeat: `{challenge, skater, clears, first_cleared_at, position}` (1 = first to clear it). `400` for a bad name or any extra field, `404` for an unknown challenge |
| `GET /api/health` | `200 {ok: true}` once the database answers |

- **Challenges** with a board are listed in `SKATELIKE_CHALLENGES` (comma separated level ids,
  the ones with `challenge = true` in `scripts/levels.gd`). Add one there when you add a challenge.
- **Rate limits** per client IP: 60 requests a minute in all, of which at most 10 clears.
  Over that you get `429`, with `x-ratelimit-*` and `retry-after` headers.
- **Browsers** from another site get `403` from the edge (an Origin check). The web build
  is same-origin, and the Android app sends no Origin.
- Bodies are limited to 1 KB, and the content type must be `application/json`.

## Layout

```
src/server.ts            entry point: listen, graceful shutdown on SIGTERM
src/app.ts               routes, validation, rate limits (buildApp, used by the tests)
src/config.ts            settings from the environment
db/migrations/           SQL, applied in order by hand as the schema owner
test/api.test.ts         node:test + app.inject() against a real Postgres
```

## Settings

| Variable | Meaning | Default |
|---|---|---|
| `HOST`, `PORT` | listen address | `127.0.0.1`, `3000` |
| `TRUST_PROXY` | proxy address whose `X-Forwarded-For` is believed | none |
| `SKATELIKE_CHALLENGES` | challenge ids with a board | required |
| `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD` | Postgres, read by postgres.js | libpq defaults |

## Development

```sh
npm install
npm run check                       # types
podman run -d --rm --name skl-pg -e POSTGRES_PASSWORD=test -p 55432:5432 docker.io/library/postgres:17
PGHOST=127.0.0.1 PGPORT=55432 PGUSER=postgres PGPASSWORD=test PGDATABASE=postgres npm test
podman stop skl-pg
```

The tests recreate the `clears` table, so never point them at a real database. On Node
older than 22.18, add `--experimental-strip-types` to the `node` commands.

## Deploying

Production runs in a container on the homelab, behind servi2's edge. The infrastructure
(containers, firewalls, WireGuard, the database, backups, the systemd unit) is documented
in the infra knowledge base (`~/code/pmx`, the skatelike section of `pmx/specs.md`). From
this repo:

```sh
# code
COPYFILE_DISABLE=1 tar -czf - -C server --exclude node_modules . | ssh root@192.168.0.111 'bash /root/skatelike/deploy-api.sh'
# a new migration, before the code that needs it
ssh root@192.168.0.111 'pct exec 115 -- su postgres -c "psql -q -v ON_ERROR_STOP=1 -1 -d skatelike -c \"set role skatelike\" -f -"' \
  < server/db/migrations/<file>.sql
```

The ghost-room server is not here: it's `scripts/online.gd`, the game itself run headless
(see `docs/online.md`).

This folder has a `.gdignore`, so Godot never imports it.
