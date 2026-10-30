// Entry point: `node src/server.ts` (Node 22.18+ runs TypeScript by stripping types).

import postgres from "postgres"
import { buildApp } from "./app.ts"
import { loadConfig } from "./config.ts"

const config = loadConfig()
const sql = postgres({ max: 5 })
const app = await buildApp(config, sql)

// systemd sends SIGTERM on stop and restart: finish the requests in flight, then exit.
for (const signal of ["SIGTERM", "SIGINT"] as const) {
	process.once(signal, async () => {
		app.log.info({ signal }, "shutting down")
		await app.close()
		await sql.end({ timeout: 5 })
		process.exit(0)
	})
}

await app.listen({ host: config.host, port: config.port })
