// Runs against a real Postgres (PG* environment variables, a throwaway database: the
// test drops and recreates the clears table). See README.md, "Testing".

import { after, before, test } from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import postgres from "postgres"
import { buildApp } from "../src/app.ts"
import { loadConfig } from "../src/config.ts"

const sql = postgres({ max: 2, onnotice: () => {} })
const config = loadConfig({ SKATELIKE_CHALLENGES: "sketchy_1, other_1" })
const app = await buildApp(config, sql)

before(async () => {
	await sql`drop table if exists clears`
	await sql`do $$ begin create role skatelike_api; exception when duplicate_object then null; end $$`
	await sql.file(new URL("../db/migrations/0001_clears.sql", import.meta.url).pathname)
})

after(async () => {
	await app.close()
	await sql.end()
})

function clear(challenge: string, skater: string) {
	return app.inject({ method: "POST", url: `/scoreboards/${challenge}/clears`, payload: { skater } })
}

test("health", async () => {
	const res = await app.inject("/health")
	assert.equal(res.statusCode, 200)
})

test("first clear is 201 with position, a repeat is 200 and keeps the position", async () => {
	const first = await clear("sketchy_1", "AAA01")
	assert.equal(first.statusCode, 201)
	assert.equal(first.json().position, 1)
	assert.equal(first.json().clears, 1)

	const second = await clear("sketchy_1", "BBB02")
	assert.equal(second.json().position, 2)

	const again = await clear("sketchy_1", "AAA01")
	assert.equal(again.statusCode, 200)
	assert.equal(again.json().clears, 2)
	assert.equal(again.json().position, 1)
})

test("board lists skaters in first-clear order, per challenge", async () => {
	await clear("other_1", "CCC03")
	const res = await app.inject("/scoreboards/sketchy_1")
	assert.equal(res.statusCode, 200)
	const board = res.json()
	assert.equal(board.total, 2)
	assert.deepEqual(board.clears.map((c: { skater: string }) => c.skater), ["AAA01", "BBB02"])
	assert.equal(board.clears[0].clears, 2)
})

test("rejects unknown challenges, bad names and extra fields", async () => {
	assert.equal((await app.inject("/scoreboards/nope")).statusCode, 404)
	assert.equal((await clear("nope", "AAA01")).statusCode, 404)
	assert.equal((await clear("sketchy_1", "aaa01")).statusCode, 400)
	assert.equal((await clear("sketchy_1", "AAAA1")).statusCode, 400)
	const extra = await app.inject({
		method: "POST",
		url: "/scoreboards/sketchy_1/clears",
		payload: { skater: "DDD04", clears: 99 },
	})
	assert.equal(extra.statusCode, 400)
})

test("rate limits clears per IP", async () => {
	const codes = []
	for (let i = 0; i < 12; i++) {
		const res = await app.inject({
			method: "POST",
			url: "/scoreboards/sketchy_1/clears",
			payload: { skater: "EEE05" },
			remoteAddress: "203.0.113.9",
		})
		codes.push(res.statusCode)
	}
	assert.ok(codes.includes(429), `expected a 429 in ${codes}`)
})
