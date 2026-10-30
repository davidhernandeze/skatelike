// Settings from the environment. In production they come from /etc/skatelike-api/env
// (EnvironmentFile of the systemd unit). The Postgres connection uses the standard
// PGHOST, PGPORT, PGDATABASE, PGUSER and PGPASSWORD variables, read by postgres.js.

export type Config = {
	host: string
	port: number
	// The reverse proxy whose X-Forwarded-For we believe (servi2's end of the tunnel).
	trustProxy: string | false
	// Challenge level ids (`challenge = true` in the game's levels.gd) that have a board.
	challenges: Set<string>
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
	const challenges = (env.SKATELIKE_CHALLENGES ?? "")
		.split(",")
		.map((id) => id.trim())
		.filter((id) => id !== "")
	if (challenges.length === 0) {
		throw new Error("SKATELIKE_CHALLENGES is empty: list the challenge level ids, comma separated")
	}
	return {
		host: env.HOST ?? "127.0.0.1",
		port: Number(env.PORT ?? 3000),
		trustProxy: env.TRUST_PROXY || false,
		challenges: new Set(challenges),
	}
}
