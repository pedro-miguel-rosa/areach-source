import { sql } from "drizzle-orm";
import { check, index, pgTable, primaryKey, text, timestamp, uniqueIndex } from "drizzle-orm/pg-core";
import { user } from "@/lib/auth/schemas";
import { event } from "@/modules/events/schemas";
import type { AttendeeReportReason, ReportStatus } from "./constants";

export const userBlock = pgTable(
	"user_block",
	{
		blockerUserId: text("blocker_user_id")
			.notNull()
			.references(() => user.id, { onDelete: "cascade" }),
		blockedUserId: text("blocked_user_id")
			.notNull()
			.references(() => user.id, { onDelete: "cascade" }),
		createdAt: timestamp("created_at").defaultNow().notNull(),
	},
	(table) => [
		primaryKey({ columns: [table.blockerUserId, table.blockedUserId] }),
		check("user_block_distinct_users_check", sql`${table.blockerUserId} <> ${table.blockedUserId}`),
		index("user_block_blocker_user_id_idx").on(table.blockerUserId),
		index("user_block_blocked_user_id_idx").on(table.blockedUserId),
	],
);

export const attendeeReport = pgTable(
	"attendee_report",
	{
		id: text("id").primaryKey(),
		reporterUserId: text("reporter_user_id")
			.notNull()
			.references(() => user.id, { onDelete: "cascade" }),
		reportedUserId: text("reported_user_id")
			.notNull()
			.references(() => user.id, { onDelete: "cascade" }),
		eventId: text("event_id")
			.notNull()
			.references(() => event.id, { onDelete: "cascade" }),
		reason: text("reason").$type<AttendeeReportReason>().notNull(),
		status: text("status").$type<ReportStatus>().notNull().default("pending"),
		createdAt: timestamp("created_at").defaultNow().notNull(),
		updatedAt: timestamp("updated_at")
			.defaultNow()
			.$onUpdate(() => new Date())
			.notNull(),
	},
	(table) => [
		uniqueIndex("attendee_report_reporter_target_event_idx").on(table.reporterUserId, table.reportedUserId, table.eventId),
		index("attendee_report_reported_user_id_idx").on(table.reportedUserId),
		index("attendee_report_event_id_idx").on(table.eventId),
		index("attendee_report_status_idx").on(table.status),
	],
);
