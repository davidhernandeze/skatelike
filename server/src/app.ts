// The scoreboard API. Each challenge has one board: the skaters who cleared it, in the
// order they first did. Clearing again only bumps the count.
//
// Raw on purpose: names are the game's 3 letters + 2 digits with no account behind them,
// and a clear is whatever the client reports. The only protection is validation and a
// per-IP rate limit.

import Fastify from "fastify"
import rateLimit from "@fastify/rate-limit"
import type { Sql } from "postgres"
import type { Config } from "./config.ts"

const SKATER = "^[A-Z]{3}[0-9]{2}$"
const BOARD_LIMIT = 100

type ChallengeParams = { challenge: string }
type ClearBody = { skater: string }

export type Clear = {
	skater: string
	clears: number
	first_cleared_at: Date
}

export async function buildApp(config: Config, sql: Sql) {
	const app = Fastify({
		logger: true,
		trustProxy: config.trustProxy,
		bodyLimit: 1024,
		// Reject unknown body fields instead of silently dropping them (Fastify's default).
		ajv: { customOptions: { removeAdditional: false } },
	})

	await app.register(rateLimit, {
		max: 60,
		timeWindow: "1 minute",
	})

	app.get("/health", async () => {
		await sql`select 1`
		return { ok: true }
	})

	const challengeParams = {
		type: "object",
		required: ["challenge"],
		properties: { challenge: { type: "string", maxLength: 64 } },
	} as const

	app.get<{ Params: ChallengeParams }>(
		"/scoreboards/:challenge",
		{ schema: { params: challengeParams } },
		async (request, reply) => {
			const { challenge } = request.params
			if (!config.challenges.has(challenge)) {
				return reply.code(404).send({ error: "unknown challenge" })
			}
			const rows = await sql<Clear[]>`
				select skater, clears, first_cleared_at
				from clears
				where challenge = ${challenge}
				order by first_cleared_at, skater
				limit ${BOARD_LIMIT}`
			const [{ total }] = await sql<{ total: number }[]>`
				select count(*)::int as total from clears where challenge = ${challenge}`
			return { challenge, total, clears: rows }
		},
	)

	app.post<{ Params: ChallengeParams; Body: ClearBody }>(
		"/scoreboards/:challenge/clears",
		{
			schema: {
				params: challengeParams,
				body: {
					type: "object",
					required: ["skater"],
					additionalProperties: false,
					properties: { skater: { type: "string", pattern: SKATER } },
				},
			},
			config: { rateLimit: { max: 10, timeWindow: "1 minute" } },
		},
		async (request, reply) => {
			const { challenge } = request.params
			if (!config.challenges.has(challenge)) {
				return reply.code(404).send({ error: "unknown challenge" })
			}
			const { skater } = request.body
			const [row] = await sql<(Clear & { position: number })[]>`
				with upsert as (
					insert into clears (challenge, skater)
					values (${challenge}, ${skater})
					on conflict (challenge, skater) do update
						set clears = clears.clears + 1, last_cleared_at = now()
					returning skater, clears, first_cleared_at
				)
				select u.skater, u.clears, u.first_cleared_at,
					(select count(*)::int from clears c
						where c.challenge = ${challenge}
						and (c.first_cleared_at, c.skater) < (u.first_cleared_at, u.skater)) + 1 as position
				from upsert u`
			request.log.info({ challenge, skater, clears: row.clears }, "clear recorded")
			return reply.code(row.clears === 1 ? 201 : 200).send({ challenge, ...row })
		},
	)

	return app
}
