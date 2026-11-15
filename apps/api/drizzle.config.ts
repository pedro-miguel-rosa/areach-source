import { defineConfig } from "drizzle-kit";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl) {
	throw new Error("Missing environment variable: DATABASE_URL");
}

export default defineConfig({
	out: "./migrations",
	schema: "./src/**/schemas.ts",
	dialect: "postgresql",
	dbCredentials: {
		url: databaseUrl,
	},
});
