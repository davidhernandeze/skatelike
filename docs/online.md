# Online ghosts: server handoff

(The scoreboards are a separate HTTP API in `server/`, called by `scripts/scoreboard.gd`.
This page is only about the ghost rooms.)

Notes for whoever deploys and runs the online server. The game side is done. Hosting,
TLS, process supervision and DNS are up to you.

## What it does

On the Challenges page, players can turn on **Online ghosts**. While they ride a challenge,
everyone else riding the same challenge shows up as a faded board with a name tag. It's
purely visual: no scores, no collisions, nothing simulated on the server. The server keeps
one room per challenge and relays what each rider sends to the others in it.

Riders don't send where they are but what they do. The game's physics runs in fixed steps
(120 a second) and replays exactly from the same actions, so each rider sends:

- their **actions** (`Runner.act`: pops, pushes, catches, board tricks, balance moves), each
  stamped with the step it applied before, in a batch 10 times a second. Each batch also
  says up to which step everything has been sent.
- a **snapshot** of their state (`Runner.get_state`) every second: where they are, their
  speeds, angle, trick state and so on, about 470 bytes.

Each client runs every ghost as a hidden copy of the game (a `Runner`), started from a
snapshot and fed the actions about 0.25 s behind. At each later snapshot's step it checks
its state against the snapshot and restarts from it if it drifted. The server keeps each
rider's latest snapshot and the actions since it, so someone joining mid-run starts their
ghost from there.

## The server

It's the same Godot project, started in server mode by `scripts/online.gd` (autoloaded as
`Online`). Nothing else loads: the menu scene is unloaded at startup.

- **Run from the project (Godot 4.7.2 binary):**
  ```sh
  godot --headless --path /path/to/skatelike -- --server --port=8910
  ```
- **Or export a standalone binary** with the "Linux Server" preset (dedicated server, so
  visuals are stripped and the PCK is embedded). It needs the Godot 4.7.2 Linux export
  templates (`linux_release.x86_64`), which aren't installed on the dev Mac yet:
  ```sh
  godot --headless --path . --export-release "Linux Server" build/server/skatelike-server.x86_64
  ./build/server/skatelike-server.x86_64 --headless -- --port=8910
  ```
  Exports with the `dedicated_server` feature start in server mode without `--server`.
- **Port:** `--port=N`, default **8910**. It listens for **plain WebSocket** (no TLS) on all
  interfaces.
- **Logs** go to stdout: listening, connects, joins (with room counts), disconnects.
  `printerr` and exit code 1 if the port can't be bound.
- **State** lives in memory only. A restart just drops everyone, and clients reconnect
  every 3 s.
- **Main loop:** capped at `SERVER_FPS` (60) network polls a second. Uncapped, the
  headless Linux build spun at about 10% of a core with nobody connected.
- **Production:** the `skatelike-game` service in CT 113 on the homelab, behind
  `wss://skatelike.com/online` (see `server/README.md`, "The production machines").
- **Resources:** one process, idle CPU, a few KB per rider. A full room is 32 riders.
  Each rider sends 10 small action batches and one snapshot (about 470 bytes) a second, and
  gets the same from each other rider in the room, relayed as they come.

## TLS and the URL clients use

The web build is served over https, so browsers can only open `wss://`. Terminate TLS in
front of the server, for example a reverse proxy that upgrades WebSocket.

The client picks the server URL in this order:

1. `--online-url=wss://…` on the command line (native builds, testing)
2. the `SKATELIKE_ONLINE_URL` environment variable
3. the project setting `skatelike/online/url` (empty by default)
4. **web builds:** `wss://<the page's own host>/online` (or `ws://` on plain http)
5. otherwise `wss://skatelike.com/online`

So the simplest setup is to proxy **`https://skatelike.com/online`** (WebSocket upgrade) to
`127.0.0.1:8910`. That needs no change to the game. For example, in Caddy:

```
handle /online {
	reverse_proxy 127.0.0.1:8910
}
```

To use another host or path, set `skatelike/online/url` in `project.godot` before exporting
the web and Android builds.

## Protocol

Godot high-level multiplayer (`WebSocketMultiplayerPeer` + RPCs on `/root/Online`). The
client and server must come from the **same protocol version**: Godot numbers RPCs by
their order, so a mismatch would misroute calls. Both sides announce the WebSocket
subprotocol `Online.PROTOCOL` (now `skatelike-3`). A mismatched client fails the
handshake and keeps retrying (the menu shows it can't reach the server), and the server
drops any rider whose protocol isn't its own. Bump `PROTOCOL` whenever the RPCs change,
and **deploy the server and the web build together**. `server_relay` is off, so clients
can only talk to the server. If a proxy sits in front, it must pass the
`Sec-WebSocket-Protocol` header through (Caddy does by default).

| RPC | Direction | Payload | Server checks |
|---|---|---|---|
| `_join` | client → server | room (challenge level id, e.g. `sketchy_1`), skater name | room is a level with `challenge = true`; name is 3 letters + 2 digits; room has fewer than 32 riders |
| `_leave` | client → server | none | none |
| `_snapshot` | client → server | `PackedByteArray`: `var_to_bytes` of `Runner.get_state()` | at most 4096 bytes; rider is in a room; at most one per 400 ms. Kept (replacing the last, and the actions held with it) and relayed to the room |
| `_actions` | client → server | `through` (int, steps), `PackedFloat64Array` of [tick, action, a, b] per action | a multiple of 4 floats, at most 64 actions; rider is in a room; at most one batch per 40 ms; `through` never goes back. Held (up to 512 actions since the snapshot) and relayed to the room |
| `_ghost_joined` | server → client | id, skater name | sent for each rider already in the room, and to them for the newcomer |
| `_ghost_left` | server → client | id | on leave, rejoin or disconnect |
| `_ghost_snapshot` | server → client | id, the snapshot bytes | as they come, and to a newcomer the latest of each rider in the room |
| `_ghost_actions` | server → client | id, `through`, the actions | as they come, and to a newcomer each rider's actions since their latest snapshot |

The server never decodes snapshots. Clients decode them with `bytes_to_var` (objects are
never allowed) and check their shape before using them. A snapshot includes the sender's
play area: the layout depends on it, so a ghost runs with the sender's, and is drawn
through level coordinates (`Runner.to_level`) so riders on different screen sizes line up.

## Testing it locally

```sh
godot --headless --path . -- --server --port=8911 &
SKATELIKE_ONLINE_URL=ws://127.0.0.1:8911 godot --path .   # turn on Online ghosts, ride Sketchy #1
SKATELIKE_ONLINE_URL=ws://127.0.0.1:8911 godot --path .   # a second window
```
