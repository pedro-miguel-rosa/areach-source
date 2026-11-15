import { boolean, pgTable, text, timestamp } from "drizzle-orm/pg-core";
import { user } from "@/lib/auth/schemas";

export const profileTable = pgTable("profile", {
	userId: text("user_id")
		.primaryKey()
		.references(() => user.id, { onDelete: "cascade" }),
	headline: text("headline").default("").notNull(),
	askMeAbout: text("ask_me_about").default("[]").notNull(),
	isDiscoverable: boolean("is_discoverable").default(true).notNull(),
	createdAt: timestamp("created_at").defaultNow().notNull(),
	updatedAt: timestamp("updated_at")
		.defaultNow()
		.$onUpdate(() => new Date())
		.notNull(),
});
