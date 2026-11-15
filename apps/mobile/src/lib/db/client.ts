import { drizzle } from "drizzle-orm/expo-sqlite";
import { openDatabaseSync } from "expo-sqlite";

const database = openDatabaseSync("areach.db", {
	enableChangeListener: true,
});

export const db = drizzle(database);
