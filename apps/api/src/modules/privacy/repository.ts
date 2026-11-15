import { and, asc, eq } from "drizzle-orm";
import { user } from "@/lib/auth/schemas";
import type { Db } from "@/lib/db";
import { event, eventAttendee } from "@/modules/events/schemas";
import type { AttendeeReportReason } from "./constants";
import { attendeeVisibleToViewerCondition, eventAccessibleToUserCondition } from "./policy";
import { attendeeReport, userBlock } from "./schemas";

export async function isVisibleEventAttendee(db: Db, eventId: string, viewerUserId: string, targetUserId: string) {
	const rows = await db
		.select({ userId: eventAttendee.userId })
		.from(eventAttendee)
		.innerJoin(event, eq(event.id, eventAttendee.eventId))
		.where(
			and(
				eq(eventAttendee.eventId, eventId),
				eq(eventAttendee.userId, targetUserId),
				eventAccessibleToUserCondition(viewerUserId),
				attendeeVisibleToViewerCondition(viewerUserId, eventAttendee.userId),
			),
		)
		.limit(1);

	return rows.length > 0;
}

export async function createUserBlock(db: Db, blockerUserId: string, blockedUserId: string) {
	await db
		.insert(userBlock)
		.values({ blockerUserId, blockedUserId })
		.onConflictDoNothing({ target: [userBlock.blockerUserId, userBlock.blockedUserId] });
}

export async function deleteUserBlock(db: Db, blockerUserId: string, blockedUserId: string) {
	await db.delete(userBlock).where(and(eq(userBlock.blockerUserId, blockerUserId), eq(userBlock.blockedUserId, blockedUserId)));
}

export async function listUserBlocks(db: Db, blockerUserId: string) {
	return db
		.select({
			userId: user.id,
			name: user.name,
			image: user.image,
			createdAt: userBlock.createdAt,
		})
		.from(userBlock)
		.innerJoin(user, eq(user.id, userBlock.blockedUserId))
		.where(eq(userBlock.blockerUserId, blockerUserId))
		.orderBy(asc(user.name), asc(user.id));
}

export async function getUserBlockState(db: Db, blockerUserId: string, blockedUserId: string) {
	const rows = await db
		.select({ blockedUserId: userBlock.blockedUserId })
		.from(userBlock)
		.where(and(eq(userBlock.blockerUserId, blockerUserId), eq(userBlock.blockedUserId, blockedUserId)))
		.limit(1);

	return rows.length > 0;
}

export async function createAttendeeReport(
	db: Db,
	input: {
		eventId: string;
		reporterUserId: string;
		reportedUserId: string;
		reason: AttendeeReportReason;
	},
) {
	const inserted = await db
		.insert(attendeeReport)
		.values({
			id: crypto.randomUUID(),
			eventId: input.eventId,
			reporterUserId: input.reporterUserId,
			reportedUserId: input.reportedUserId,
			reason: input.reason,
		})
		.onConflictDoNothing({
			target: [attendeeReport.reporterUserId, attendeeReport.reportedUserId, attendeeReport.eventId],
		})
		.returning({ id: attendeeReport.id, status: attendeeReport.status });

	if (inserted[0]) {
		return { ...inserted[0], created: true };
	}

	const existingRows = await db
		.select({ id: attendeeReport.id, status: attendeeReport.status })
		.from(attendeeReport)
		.where(
			and(
				eq(attendeeReport.reporterUserId, input.reporterUserId),
				eq(attendeeReport.reportedUserId, input.reportedUserId),
				eq(attendeeReport.eventId, input.eventId),
			),
		)
		.limit(1);

	return existingRows[0] ? { ...existingRows[0], created: false } : null;
}
