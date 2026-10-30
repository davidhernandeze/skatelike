# Online ghosts: server handoff

(The scoreboards are a separate HTTP API in `server/`, called by `scripts/scoreboard.gd`.
This page is only about the ghost rooms.)

Notes for whoever deploys and runs the online server. The game side is done. Hosting,
TLS, process supervision and DNS are up to you.

## What it does

On the Challenges page, players can turn on **Online ghosts**. While they ride a challenge,
everyone else riding the same challenge shows up as a faded board with a name tag. It's
purely visual: no scores, no collisions, nothing simulated on the server. The server keeps
one room per challenge. Each rider sends their board pose (5 floats) 10 times a second, and
10 times a second the server sends each rider **one** message with the poses that came in
from the others in their room since the last one.

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
  Each rider sends 10 poses a second and gets 10 batched messages a second, whatever the
  room size. With two ghosts, a rider's download measured 631 B/s of WebSocket payload,
  down from 936 B/s with one message per pose at 15 a second. The saving grows with the
  room, and the wire saves more again (TCP/IP/TLS headers per message).

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
subprotocol `Online.PROTOCOL` (now `skatelike-2`). A mismatched client fails the
handshake and keeps retrying (the menu shows it can't reach the server), and the server
drops any rider whose protocol isn't its own. Bump `PROTOCOL` whenever the RPCs change,
and **deploy the server and the web build together**. `server_relay` is off, so clients
can only talk to the server. If a proxy sits in front, it must pass the
`Sec-WebSocket-Protocol` header through (Caddy does by default).

| RPC | Direction | Payload | Server checks |
|---|---|---|---|
| `_join` | client → server | room (challenge level id, e.g. `sketchy_1`), skater name | room is a level with `challenge = true`; name is 3 letters + 2 digits; room has fewer than 32 riders |
| `_leave` | client → server | none | none |
| `_pose` | client → server | `PackedFloat32Array` of 5: level x, level y, angle, scale x, scale y | exactly 5 floats; rider is in a room; at most one per 70 ms (extra ones are dropped). Kept until the next broadcast |
| `_ghost_joined` | server → client | id, skater name | sent for each rider already in the room, and to them for the newcomer |
| `_ghost_left` | server → client | id | on leave, rejoin or disconnect |
| `_ghost_poses` | server → client | `PackedInt32Array` ids, `PackedFloat32Array` poses (5 per id, same order) | 10 times a second, to each rider: the fresh poses of the others in their room. Nothing is sent when nothing is new |

Poses are in level coordinates (see `Runner.to_level`), so riders on different screen
sizes line up.

## Testing it locally

```sh
godot --headless --path . -- --server --port=8911 &
SKATELIKE_ONLINE_URL=ws://127.0.0.1:8911 godot --path .   # turn on Online ghosts, ride Sketchy #1
SKATELIKE_ONLINE_URL=ws://127.0.0.1:8911 godot --path .   # a second window
```
