// Drizzle Kit generates the concrete migration SQL in this folder.
// This wrapper gives the app a stable TS import path.
import generatedMigrations from "./migrations.js";

export const migrations = generatedMigrations;
