import { defineConfig } from "drizzle-kit";

export default defineConfig({
	out: "./src/lib/db/migrations",
	schema: ["./src/features/**/schema.ts", "./src/lib/db/legacy-study-schema.ts"],
	dialect: "sqlite",
	driver: "expo",
});
