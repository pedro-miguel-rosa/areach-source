import { index, integer, pgTable, primaryKey, text, timestamp } from "drizzle-orm/pg-core";
import { user } from "@/lib/auth/schemas";

export const event = pgTable(
	"event",
	{
		id: text("id").primaryKey(),
		title: text("title").notNull(),
		description: text("description").notNull().default(""),
		venue: text("venue").notNull(),
		inviteCode: text("invite_code").notNull().unique(),
		capacity: integer("capacity"),
		startAt: timestamp("start_at").notNull(),
		endAt: timestamp("end_at").notNull(),
		createdById: text("created_by_id")
			.notNull()
			.references(() => user.id, { onDelete: "cascade" }),
		createdAt: timestamp("created_at").defaultNow().notNull(),
		updatedAt: timestamp("updated_at")
			.defaultNow()
			.$onUpdate(() => new Date())
			.notNull(),
	},
	(table) => [
		index("event_created_by_id_idx").on(table.createdById),
		index("event_start_at_idx").on(table.startAt),
		index("event_end_at_idx").on(table.endAt),
	],
);

export const eventRegistration = pgTable(
	"event_registration",
	{
		eventId: text("event_id")
			.notNull()
			.references(() => event.id, { onDelete: "cascade" }),
		userId: text("user_id")
			.notNull()
			.references(() => user.id, { onDelete: "cascade" }),
		createdAt: timestamp("created_at").defaultNow().notNull(),
	},
	(table) => [
		primaryKey({ columns: [table.eventId, table.userId] }),
		index("event_registration_event_id_idx").on(table.eventId),
		index("event_registration_user_id_idx").on(table.userId),
	],
);

export const eventAttendee = pgTable(
	"event_attendee",
	{
		eventId: text("event_id")
			.notNull()
			.references(() => event.id, { onDelete: "cascade" }),
		userId: text("user_id")
			.notNull()
			.references(() => user.id, { onDelete: "cascade" }),
		joinedAt: timestamp("joined_at").defaultNow().notNull(),
		lastSeenAt: timestamp("last_seen_at").defaultNow().notNull(),
		nearbyPeerId: text("nearby_peer_id"),
		nearbyPublicKey: text("nearby_public_key"),
		nearbyCredential: text("nearby_credential"),
		nearbyCredentialExpiresAt: timestamp("nearby_credential_expires_at"),
	},
	(table) => [
		primaryKey({ columns: [table.eventId, table.userId] }),
		index("event_attendee_event_id_idx").on(table.eventId),
		index("event_attendee_user_id_idx").on(table.userId),
		index("event_attendee_last_seen_at_idx").on(table.lastSeenAt),
	],
);
