import { and, asc, desc, eq, gt, inArray, or, sql } from "drizzle-orm";
import { getLocalBlockedUserIds } from "@/features/privacy/repository";
import { db } from "@/lib/db/client";
import { toLocalEventInsert } from "./mappers";
import { eventMutation, localEvent, localEventAttendee } from "./schema";
import type {
	CreateEventMutationPayload,
	CreateLocalEventInput,
	EventMutationStatus,
	EventSyncStatus,
	JoinEventInput,
	JoinEventMutationPayload,
	RemoteEvent,
	RemoteEventAttendee,
} from "./types";

export function getUpcomingEventsQuery(userId: string, now: Date) {
	return db
		.select()
		.from(localEvent)
		.where(and(eq(localEvent.viewerId, userId), gt(localEvent.endAt, now.toISOString())))
		.orderBy(asc(localEvent.startAt));
}

export function getEventsQuery(viewerId: string) {
	return db.select().from(localEvent).where(eq(localEvent.viewerId, viewerId)).orderBy(asc(localEvent.startAt));
}

export function getEventByIdQuery(viewerId: string, eventId: string) {
	return db
		.select()
		.from(localEvent)
		.where(and(eq(localEvent.viewerId, viewerId), eq(localEvent.id, eventId)))
		.limit(1);
}

export function getEventAttendeesQuery(viewerId: string, eventId: string) {
	return db
		.select()
		.from(localEventAttendee)
		.where(and(eq(localEventAttendee.viewerId, viewerId), eq(localEventAttendee.eventId, eventId)))
		.orderBy(desc(localEventAttendee.role), asc(localEventAttendee.name), asc(localEventAttendee.userId));
}

export function getEventAttendeeByIdQuery(viewerId: string, eventId: string, attendeeId: string) {
	return db
		.select()
		.from(localEventAttendee)
		.where(
			and(eq(localEventAttendee.viewerId, viewerId), eq(localEventAttendee.eventId, eventId), eq(localEventAttendee.userId, attendeeId)),
		)
		.limit(1);
}

export async function createLocalEvent(input: CreateLocalEventInput) {
	const now = new Date().toISOString();
	const localEventId = createId("local-event");
	const mutationId = createId("mutation");
	const payload: CreateEventMutationPayload = {
		title: input.title,
		description: input.description,
		venue: input.venue,
		capacity: input.capacity,
		startAt: input.startAt,
		endAt: input.endAt,
	};

	await db.insert(localEvent).values({
		id: localEventId,
		remoteId: null,
		viewerId: input.viewerId,
		title: input.title,
		description: input.description,
		venue: input.venue,
		hostLabel: "Hosted by you",
		registrationCount: 1,
		createdByUser: true,
		inviteCode: null,
		capacity: input.capacity,
		startAt: input.startAt,
		endAt: input.endAt,
		syncStatus: "pending_create",
		createdAt: now,
		updatedAt: now,
	});

	await db.insert(eventMutation).values({
		id: mutationId,
		viewerId: input.viewerId,
		type: "create_event",
		status: "pending",
		localEventId,
		payload: JSON.stringify(payload),
		errorMessage: null,
		createdAt: now,
		lastAttemptAt: null,
	});

	return localEventId;
}

export async function queueJoinEvent(input: JoinEventInput) {
	const payload: JoinEventMutationPayload = {
		inviteCode: input.inviteCode.trim().toUpperCase(),
	};

	await db.insert(eventMutation).values({
		id: createId("mutation"),
		viewerId: input.viewerId,
		type: "join_event",
		status: "pending",
		localEventId: null,
		payload: JSON.stringify(payload),
		errorMessage: null,
		createdAt: new Date().toISOString(),
		lastAttemptAt: null,
	});
}

export async function listQueuedEventMutations(viewerId: string) {
	return db
		.select()
		.from(eventMutation)
		.where(and(eq(eventMutation.viewerId, viewerId), inArray(eventMutation.status, ["pending", "failed"])))
		.orderBy(asc(eventMutation.createdAt));
}

export async function markEventMutationStatus(mutationId: string, status: EventMutationStatus, errorMessage: string | null = null) {
	await db
		.update(eventMutation)
		.set({
			status,
			errorMessage,
			lastAttemptAt: new Date().toISOString(),
		})
		.where(eq(eventMutation.id, mutationId));
}

export async function removeEventMutation(mutationId: string) {
	await db.delete(eventMutation).where(eq(eventMutation.id, mutationId));
}

export async function markLocalEventSyncStatus(eventId: string, syncStatus: EventSyncStatus) {
	await db
		.update(localEvent)
		.set({
			syncStatus,
			updatedAt: new Date().toISOString(),
		})
		.where(eq(localEvent.id, eventId));
}

export async function reconcileCreatedEvent(localEventId: string, viewerId: string, event: RemoteEvent) {
	await db
		.update(localEvent)
		.set({
			remoteId: event.id,
			title: event.title,
			description: event.description,
			venue: event.venue,
			hostLabel: event.hostLabel,
			registrationCount: event.registrationCount,
			createdByUser: event.createdByUser,
			inviteCode: event.inviteCode,
			capacity: event.capacity,
			startAt: event.startAt,
			endAt: event.endAt,
			syncStatus: "synced",
			updatedAt: new Date().toISOString(),
		})
		.where(and(eq(localEvent.id, localEventId), eq(localEvent.viewerId, viewerId)));
}

export async function upsertRemoteEvent(viewerId: string, event: RemoteEvent) {
	const existingEvent = await db
		.select({
			id: localEvent.id,
		})
		.from(localEvent)
		.where(and(eq(localEvent.viewerId, viewerId), or(eq(localEvent.remoteId, event.id), eq(localEvent.id, event.id))))
		.limit(1);

	const now = new Date().toISOString();

	if (existingEvent[0]) {
		await db
			.update(localEvent)
			.set({
				remoteId: event.id,
				title: event.title,
				description: event.description,
				venue: event.venue,
				hostLabel: event.hostLabel,
				registrationCount: event.registrationCount,
				createdByUser: event.createdByUser,
				inviteCode: event.inviteCode,
				capacity: event.capacity,
				startAt: event.startAt,
				endAt: event.endAt,
				syncStatus: "synced",
				updatedAt: now,
			})
			.where(eq(localEvent.id, existingEvent[0].id));
		return existingEvent[0].id;
	}

	await db.insert(localEvent).values(toLocalEventInsert(viewerId, event));
	return event.id;
}

export async function upsertRemoteEvents(viewerId: string, events: RemoteEvent[]) {
	for (const event of events) {
		await upsertRemoteEvent(viewerId, event);
	}
}

export async function replaceLocalEventAttendees(viewerId: string, eventId: string, attendees: RemoteEventAttendee[]) {
	const now = new Date().toISOString();
	const blockedUserIds = await getLocalBlockedUserIds(viewerId);
	const visibleAttendees = attendees.filter((attendee) => attendee.isCurrentUser || !blockedUserIds.has(attendee.userId));

	db.transaction((transaction) => {
		transaction
			.delete(localEventAttendee)
			.where(and(eq(localEventAttendee.viewerId, viewerId), eq(localEventAttendee.eventId, eventId)))
			.run();

		if (visibleAttendees.length === 0) {
			return;
		}

		transaction
			.insert(localEventAttendee)
			.values(
				visibleAttendees.map((attendee) => ({
					eventId,
					viewerId,
					userId: attendee.userId,
					name: attendee.name,
					image: attendee.image ?? null,
					headline: attendee.headline ?? "",
					askMeAbout: JSON.stringify(attendee.askMeAbout ?? []),
					role: attendee.role,
					isCurrentUser: attendee.isCurrentUser,
					lastSeenAt: attendee.lastSeenAt,
					updatedAt: now,
				})),
			)
			.run();
	});
}

export async function upsertLocalEventAttendees(viewerId: string, eventId: string, attendees: RemoteEventAttendee[]) {
	const blockedUserIds = await getLocalBlockedUserIds(viewerId);
	const visibleAttendees = attendees.filter((attendee) => attendee.isCurrentUser || !blockedUserIds.has(attendee.userId));

	if (visibleAttendees.length === 0) {
		return;
	}

	const now = new Date().toISOString();

	await db
		.insert(localEventAttendee)
		.values(
			visibleAttendees.map((attendee) => ({
				eventId,
				viewerId,
				userId: attendee.userId,
				name: attendee.name,
				image: attendee.image ?? null,
				headline: attendee.headline ?? "",
				askMeAbout: JSON.stringify(attendee.askMeAbout ?? []),
				role: attendee.role,
				isCurrentUser: attendee.isCurrentUser,
				lastSeenAt: attendee.lastSeenAt,
				updatedAt: now,
			})),
		)
		.onConflictDoUpdate({
			target: [localEventAttendee.eventId, localEventAttendee.userId],
			set: {
				viewerId,
				name: sql`excluded.name`,
				image: sql`excluded.image`,
				headline: sql`excluded.headline`,
				askMeAbout: sql`excluded.ask_me_about`,
				role: sql`excluded.role`,
				isCurrentUser: sql`excluded.is_current_user`,
				lastSeenAt: sql`excluded.last_seen_at`,
				updatedAt: now,
			},
		})
		.run();
}

export async function removeLocalEventAttendees(viewerId: string, userId: string) {
	await db.delete(localEventAttendee).where(and(eq(localEventAttendee.viewerId, viewerId), eq(localEventAttendee.userId, userId)));
}

function createId(prefix: string) {
	const timestamp = Date.now().toString(36);
	const random = Math.random().toString(36).slice(2, 10);

	return `${prefix}:${timestamp}:${random}`;
}
