import { index, integer, sqliteTable, text } from "drizzle-orm/sqlite-core";
import type { ProfileMutationStatus, ProfileSyncStatus } from "./types";

export const localProfile = sqliteTable(
	"local_profile",
	{
		id: text("id").primaryKey(),
		name: text("name").notNull(),
		email: text("email").notNull(),
		image: text("image"),
		headline: text("headline").notNull().default(""),
		askMeAbout: text("ask_me_about").notNull().default("[]"),
		isDiscoverable: integer("is_discoverable", { mode: "boolean" }).notNull().default(true),
		syncStatus: text("sync_status", {
			enum: ["failed", "pending_update", "synced"],
		})
			.$type<ProfileSyncStatus>()
			.notNull()
			.default("synced"),
		createdAt: text("created_at").notNull(),
		updatedAt: text("updated_at").notNull(),
	},
	(table) => [index("local_profile_sync_status_idx").on(table.syncStatus)],
);

export type LocalProfileRow = typeof localProfile.$inferSelect;

export const profileMutation = sqliteTable(
	"profile_mutation",
	{
		id: text("id").primaryKey(),
		viewerId: text("viewer_id").notNull(),
		status: text("status").$type<ProfileMutationStatus>().notNull().default("pending"),
		payload: text("payload").notNull(),
		errorMessage: text("error_message"),
		createdAt: text("created_at").notNull(),
		lastAttemptAt: text("last_attempt_at"),
	},
	(table) => [
		index("profile_mutation_viewer_id_idx").on(table.viewerId),
		index("profile_mutation_status_idx").on(table.status),
		index("profile_mutation_created_at_idx").on(table.createdAt),
	],
);

export type ProfileMutationRow = typeof profileMutation.$inferSelect;
