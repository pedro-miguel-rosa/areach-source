import { and, asc, eq, sql } from "drizzle-orm";
import { user } from "@/lib/auth/schemas";
import type { Db } from "@/lib/db";
import { attendeeVisibleToViewerCondition, eventAccessibleToUserCondition } from "@/modules/privacy/policy";
import { profileTable } from "@/modules/profile/schemas";
import type { EventAttendeeRow, EventRegistrationRow } from "./mappers";
import { event, eventAttendee, eventRegistration } from "./schemas";
import type { CreateEventRecordInput } from "./types";

export async function listEventRowsForUser(db: Db, currentUserId: string) {
	return db
		.select(selectEventRowFields(currentUserId))
		.from(event)
		.innerJoin(user, eq(user.id, event.createdById))
		.where(eventAccessibleToUserCondition(currentUserId))
		.orderBy(asc(event.startAt));
}

export async function getEventRowForUser(db: Db, eventId: string, currentUserId: string) {
	const rows = await db
		.select(selectEventRowFields(currentUserId))
		.from(event)
		.innerJoin(user, eq(user.id, event.createdById))
		.where(and(eq(event.id, eventId), eventAccessibleToUserCondition(currentUserId)))
		.limit(1);

	return rows[0] ?? null;
}

export async function listEventRegistrationRowsForUser(
	db: Db,
	eventId: string,
	currentUserId: string,
): Promise<EventRegistrationRow[] | null> {
	const hostRows = await db
		.select({
			userId: event.createdById,
			name: user.name,
			isAttending: attendanceSql(event.createdById, eventId),
			hostVisible: attendeeVisibleToViewerCondition(currentUserId, event.createdById),
		})
		.from(event)
		.innerJoin(user, eq(user.id, event.createdById))
		.where(and(eq(event.id, eventId), eventAccessibleToUserCondition(currentUserId)))
		.limit(1);

	const host = hostRows[0];

	if (!host) {
		return null;
	}

	const attendeeRows = await db
		.select({
			userId: user.id,
			name: user.name,
			isAttending: attendanceSql(user.id, eventId),
		})
		.from(eventRegistration)
		.innerJoin(user, eq(user.id, eventRegistration.userId))
		.where(and(eq(eventRegistration.eventId, eventId), attendeeVisibleToViewerCondition(currentUserId, eventRegistration.userId)))
		.orderBy(asc(user.name), asc(user.id));

	const { hostVisible, ...hostRow } = host;

	return [
		...(hostVisible ? [{ ...hostRow, isHost: true }] : []),
		...attendeeRows.map((row) => ({
			...row,
			isHost: false,
		})),
	];
}

export async function listEventAttendeeRowsForUser(db: Db, eventId: string, currentUserId: string): Promise<EventAttendeeRow[] | null> {
	const rows = await db
		.select(selectEventAttendeeFields())
		.from(eventAttendee)
		.innerJoin(user, eq(user.id, eventAttendee.userId))
		.leftJoin(profileTable, eq(profileTable.userId, user.id))
		.innerJoin(event, eq(event.id, eventAttendee.eventId))
		.where(
			and(
				eq(eventAttendee.eventId, eventId),
				eventAccessibleToUserCondition(currentUserId),
				attendeeVisibleToViewerCondition(currentUserId, eventAttendee.userId),
			),
		)
		.orderBy(asc(user.name), asc(user.id));

	if (rows.length === 0) {
		const eventRows = await db
			.select({ id: event.id })
			.from(event)
			.where(and(eq(event.id, eventId), eventAccessibleToUserCondition(currentUserId)))
			.limit(1);

		return eventRows[0] ? [] : null;
	}

	return rows;
}

export async function getEventAttendeeRowForUser(db: Db, eventId: string, currentUserId: string, attendeeId: string) {
	const rows = await db
		.select(selectEventAttendeeFields())
		.from(eventAttendee)
		.innerJoin(user, eq(user.id, eventAttendee.userId))
		.leftJoin(profileTable, eq(profileTable.userId, user.id))
		.innerJoin(event, eq(event.id, eventAttendee.eventId))
		.where(
			and(
				eq(eventAttendee.eventId, eventId),
				eq(eventAttendee.userId, attendeeId),
				eventAccessibleToUserCondition(currentUserId),
				attendeeVisibleToViewerCondition(currentUserId, eventAttendee.userId),
			),
		)
		.limit(1);

	return rows[0] ?? null;
}

export async function markEventAttendance(db: Db, eventId: string, userId: string) {
	const now = new Date();

	await db
		.insert(eventAttendee)
		.values({
			eventId,
			userId,
			joinedAt: now,
			lastSeenAt: now,
		})
		.onConflictDoUpdate({
			target: [eventAttendee.eventId, eventAttendee.userId],
			set: {
				lastSeenAt: now,
			},
		});

	return {
		eventId,
		userId,
		lastSeenAt: now,
	};
}

export async function getEventAttendanceNearbyIdentity(db: Db, eventId: string, userId: string) {
	const rows = await db
		.select({
			nearbyPeerId: eventAttendee.nearbyPeerId,
			nearbyPublicKey: eventAttendee.nearbyPublicKey,
			nearbyCredential: eventAttendee.nearbyCredential,
			nearbyCredentialExpiresAt: eventAttendee.nearbyCredentialExpiresAt,
		})
		.from(eventAttendee)
		.where(and(eq(eventAttendee.eventId, eventId), eq(eventAttendee.userId, userId)))
		.limit(1);

	return rows[0] ?? null;
}

export async function saveEventAttendanceNearbyIdentity(
	db: Db,
	eventId: string,
	userId: string,
	identity: {
		nearbyCredential: string;
		nearbyCredentialExpiresAt: Date;
		nearbyPeerId: string;
		nearbyPublicKey: string;
	},
) {
	await db
		.update(eventAttendee)
		.set(identity)
		.where(and(eq(eventAttendee.eventId, eventId), eq(eventAttendee.userId, userId)));
}

export async function isUserCheckedIntoEvent(db: Db, eventId: string, userId: string) {
	const rows = await db
		.select({ userId: eventAttendee.userId })
		.from(eventAttendee)
		.where(and(eq(eventAttendee.eventId, eventId), eq(eventAttendee.userId, userId)))
		.limit(1);

	return rows.length > 0;
}

export async function clearEventAttendance(db: Db, eventId: string, userId: string) {
	await db.delete(eventAttendee).where(and(eq(eventAttendee.eventId, eventId), eq(eventAttendee.userId, userId)));
}

export async function createEventRecord(db: Db, input: CreateEventRecordInput) {
	await db.insert(event).values(input);
}

export async function findEventByInviteCode(db: Db, inviteCode: string) {
	const rows = await db
		.select({
			id: event.id,
			createdById: event.createdById,
			capacity: event.capacity,
			endAt: event.endAt,
		})
		.from(event)
		.where(eq(event.inviteCode, inviteCode))
		.limit(1);

	return rows[0] ?? null;
}

export async function hasEventRegistration(db: Db, eventId: string, userId: string) {
	const rows = await db
		.select({ eventId: eventRegistration.eventId })
		.from(eventRegistration)
		.where(and(eq(eventRegistration.eventId, eventId), eq(eventRegistration.userId, userId)))
		.limit(1);

	return rows.length > 0;
}

export async function createEventRegistration(db: Db, eventId: string, userId: string) {
	await db.insert(eventRegistration).values({
		eventId,
		userId,
	});
}

export async function getEventRegistrationCount(db: Db, eventId: string) {
	const result = await db
		.select({ registrationCount: registrationCountSql(eventId) })
		.from(event)
		.where(eq(event.id, eventId))
		.limit(1);

	return result[0]?.registrationCount ?? 0;
}

export async function eventInviteCodeExists(db: Db, inviteCode: string) {
	const rows = await db.select({ id: event.id }).from(event).where(eq(event.inviteCode, inviteCode)).limit(1);
	return rows.length > 0;
}

function selectEventRowFields(currentUserId: string) {
	return {
		id: event.id,
		title: event.title,
		description: event.description,
		venue: event.venue,
		inviteCode: event.inviteCode,
		capacity: event.capacity,
		startAt: event.startAt,
		endAt: event.endAt,
		createdById: event.createdById,
		hostName: user.name,
		hostVisible: attendeeVisibleToViewerCondition(currentUserId, event.createdById),
		registrationCount: registrationCountSql(event.id),
	};
}

function selectEventAttendeeFields() {
	return {
		userId: user.id,
		name: user.name,
		image: user.image,
		headline: sql<string>`coalesce(${profileTable.headline}, '')`,
		askMeAbout: sql<string>`coalesce(${profileTable.askMeAbout}, '[]')`,
		lastSeenAt: eventAttendee.lastSeenAt,
		isHost: sql<boolean>`${eventAttendee.userId} = ${event.createdById}`,
	};
}

function registrationCountSql(eventId: typeof event.id | string) {
	return sql<number>`(
		select count(*)::int + 1
		from ${eventRegistration}
		where ${eventRegistration.eventId} = ${eventId}
	)`;
}

function attendanceSql(userId: typeof user.id | typeof event.createdById, eventId: string) {
	return sql<boolean>`exists (
		select 1
		from ${eventAttendee}
		where ${eventAttendee.eventId} = ${eventId}
			and ${eventAttendee.userId} = ${userId}
	)`;
}
