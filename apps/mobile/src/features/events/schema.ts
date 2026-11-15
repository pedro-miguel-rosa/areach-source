import { index, integer, primaryKey, sqliteTable, text, uniqueIndex } from "drizzle-orm/sqlite-core";
import type { EventAttendeeRole, EventSyncStatus } from "./types";

export const localEvent = sqliteTable(
	"local_event",
	{
		id: text("id").primaryKey(),
		remoteId: text("remote_id"),
		viewerId: text("viewer_id").notNull(),
		title: text("title").notNull(),
		description: text("description").notNull().default(""),
		venue: text("venue").notNull(),
		hostLabel: text("host_label").notNull(),
		registrationCount: integer("registration_count").notNull().default(0),
		createdByUser: integer("created_by_user", { mode: "boolean" }).notNull(),
		inviteCode: text("invite_code"),
		capacity: integer("capacity"),
		startAt: text("start_at").notNull(),
		endAt: text("end_at").notNull(),
		syncStatus: text("sync_status", {
			enum: ["failed", "pending_create", "synced"],
		})
			.$type<EventSyncStatus>()
			.notNull()
			.default("synced"),
		createdAt: text("created_at").notNull(),
		updatedAt: text("updated_at").notNull(),
	},
	(table) => [
		uniqueIndex("local_event_remote_id_idx").on(table.remoteId),
		index("local_event_viewer_id_idx").on(table.viewerId),
		index("local_event_start_at_idx").on(table.startAt),
		index("local_event_end_at_idx").on(table.endAt),
	],
);

export type LocalEventRow = typeof localEvent.$inferSelect;

export const localEventAttendee = sqliteTable(
	"local_event_attendee",
	{
		eventId: text("event_id").notNull(),
		viewerId: text("viewer_id").notNull(),
		userId: text("user_id").notNull(),
		name: text("name").notNull(),
		image: text("image"),
		headline: text("headline").notNull().default(""),
		askMeAbout: text("ask_me_about").notNull().default("[]"),
		role: text("role", {
			enum: ["host", "attendee"],
		})
			.$type<EventAttendeeRole>()
			.notNull(),
		isCurrentUser: integer("is_current_user", { mode: "boolean" }).notNull().default(false),
		lastSeenAt: text("last_seen_at").notNull(),
		updatedAt: text("updated_at").notNull(),
	},
	(table) => [
		primaryKey({ columns: [table.eventId, table.userId] }),
		index("local_event_attendee_event_id_idx").on(table.eventId),
		index("local_event_attendee_viewer_id_idx").on(table.viewerId),
		index("local_event_attendee_user_id_idx").on(table.userId),
	],
);

export type LocalEventAttendeeRow = typeof localEventAttendee.$inferSelect;

export const eventMutation = sqliteTable(
	"event_mutation",
	{
		id: text("id").primaryKey(),
		viewerId: text("viewer_id").notNull(),
		type: text("type").notNull(),
		status: text("status").notNull().default("pending"),
		localEventId: text("local_event_id"),
		payload: text("payload").notNull(),
		errorMessage: text("error_message"),
		createdAt: text("created_at").notNull(),
		lastAttemptAt: text("last_attempt_at"),
	},
	(table) => [
		index("event_mutation_viewer_id_idx").on(table.viewerId),
		index("event_mutation_status_idx").on(table.status),
		index("event_mutation_created_at_idx").on(table.createdAt),
	],
);
