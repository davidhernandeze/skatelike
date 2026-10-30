# skatelike server: scoreboard API

Each challenge has a global scoreboard: the skaters who cleared it, in the order they
first did. Clearing it again only bumps your count. Live at `https://skatelike.com/api/`.

Fastify + TypeScript + postgres.js. Node 22.18+ runs the `.ts` files directly by stripping
the types, so there's no build step (only erasable TypeScript syntax: no enums, no
parameter properties). `tsc` only checks the types.

It's raw on purpose. Names are the game's 3 letters + 2 digits with no account behind
them, and a clear is whatever the client reports. The only protection is validation and
a per-IP rate limit.

## Connecting

### Production endpoints

| Service | URL | Protocol |
|---|---|---|
| Scoreboards (this API) | `https://skatelike.com/api` | JSON over HTTPS, see [API](#api) |
| Ghost rooms | `wss://skatelike.com/online` | Godot high-level multiplayer over WebSocket (`scripts/online.gd`, protocol in `docs/online.md`). Not a plain WebSocket API |

Neither needs a login. Browsers on other sites get `403` (an Origin check at the edge).
Requests without an Origin header (the Android app, `curl`, a native build) get through.

### From the game

Both services are only used while the **Online** switch on the Challenges page is on
(`Profile.online`). The game finds them on its own:

| Build | Scoreboards (`scripts/scoreboard.gd`) | Ghost rooms (`scripts/online.gd`) |
|---|---|---|
| Web | `/api` on the page's own origin | `wss://` (or `ws://` on plain http) + the page's host + `/online` |
| Android, desktop | `https://skatelike.com/api` | `wss://skatelike.com/online` |

To point a build somewhere else, the first match wins:

1. a command-line argument after `--`: `--api-url=…` / `--online-url=…`
2. an environment variable: `SKATELIKE_API_URL` / `SKATELIKE_ONLINE_URL`
3. a project setting in `project.godot`: `skatelike/api/url` / `skatelike/online/url`
   (set it before exporting a build meant for another server)
4. the defaults above

The ghost-room server only accepts clients built from **the same commit** as itself:
Godot refuses RPCs whose configuration differs. The scoreboards have no such restriction.

### Against a local backend

The API's routes have no `/api` prefix (the edge strips it in production), so a local API
URL has none either. Start Postgres and the API ([Development](#development) has the
Postgres container), the ghost-room server, then the game:

```sh
# from server/: the API on 127.0.0.1:3000
SKATELIKE_CHALLENGES=sketchy_1 PGHOST=127.0.0.1 PGPORT=55432 PGUSER=postgres PGPASSWORD=test \
  PGDATABASE=postgres npm start
# The database needs the schema first. Running the tests once creates it, or by hand:
#   podman exec -i skl-pg psql -U postgres -c 'create role skatelike_api'
#   podman exec -i skl-pg psql -U postgres < db/migrations/0001_clears.sql

# from the repo root: the ghost-room server on :8911, then two game windows
godot --headless --path . -- --server --port=8911
SKATELIKE_API_URL=http://127.0.0.1:3000 SKATELIKE_ONLINE_URL=ws://127.0.0.1:8911 godot --path .
SKATELIKE_API_URL=http://127.0.0.1:3000 SKATELIKE_ONLINE_URL=ws://127.0.0.1:8911 godot --path .
```

Turn on Online in each window and ride Sketchy #1: each window shows the other as a ghost,
and clearing it adds your name to the local board.

### By hand

```sh
curl -s https://skatelike.com/api/health
curl -s https://skatelike.com/api/scoreboards/sketchy_1
# Records a real clear on the live board. Use a local API to experiment.
curl -s -X POST -H 'Content-Type: application/json' -d '{"skater":"DHZ07"}' \
  https://skatelike.com/api/scoreboards/sketchy_1/clears
```

### The production machines

Everything runs in containers on the homelab Proxmox host (`root@192.168.0.111`, or
`pmx.tail391c2a.ts.net` over Tailscale). The containers have no sshd: go through the host.
If ssh prints locale warnings from the Mac, add `-o SetEnv=LC_ALL=C`.

| What | CT | Logs | Shell |
|---|---|---|---|
| Ghost rooms | 113 | `ssh root@192.168.0.111 'pct exec 113 -- journalctl -u skatelike-game -f'` | `ssh -t root@192.168.0.111 pct enter 113` |
| This API | 114 | `ssh root@192.168.0.111 'pct exec 114 -- journalctl -u skatelike-api -f'` | `ssh -t root@192.168.0.111 pct enter 114` |
| Postgres | 115 | `ssh root@192.168.0.111 'pct exec 115 -- tail -f /var/log/postgresql/postgresql-17-main.log'` | `ssh -t root@192.168.0.111 "pct exec 115 -- su postgres -c 'psql -d skatelike'"` |

From a database shell, `select * from clears order by challenge, first_cleared_at;`
shows every board.

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
