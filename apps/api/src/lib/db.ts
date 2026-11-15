import { drizzle } from "drizzle-orm/node-postgres";

export function getDb(env: CloudflareBindings) {
	return drizzle({ connection: env.HYPERDRIVE.connectionString });
}

export type Db = ReturnType<typeof getDb>;
