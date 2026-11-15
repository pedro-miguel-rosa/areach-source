import { HTTPException } from "hono/http-exception";
import type { Db } from "@/lib/db";
import { toEventAttendeeResponse, toEventRegistrationResponse, toEventResponse } from "./mappers";
import { readNearbyCredential } from "./nearby-credentials";
import {
	clearEventAttendance,
	createEventRecord,
	createEventRegistration,
	eventInviteCodeExists,
	findEventByInviteCode,
	getEventAttendeeRowForUser,
	getEventRegistrationCount,
	getEventRowForUser,
	hasEventRegistration,
	isUserCheckedIntoEvent,
	listEventAttendeeRowsForUser,
	listEventRegistrationRowsForUser,
	listEventRowsForUser,
	markEventAttendance,
} from "./repository";
import type { CreateEventInput } from "./types";

const INVITE_CODE_GENERATION_ATTEMPTS = 10;

export async function listEventsForUser(db: Db, currentUserId: string) {
	const rows = await listEventRowsForUser(db, currentUserId);

	return rows.map((row) => toEventResponse(row, currentUserId));
}

export async function getEventForUser(db: Db, eventId: string, currentUserId: string) {
	const row = await getEventRowForUser(db, eventId, currentUserId);

	return row ? toEventResponse(row, currentUserId) : null;
}

export async function listEventAttendeesForUser(db: Db, eventId: string, currentUserId: string) {
	const rows = await listEventAttendeeRowsForUser(db, eventId, currentUserId);

	return rows ? rows.map((row) => toEventAttendeeResponse(row, currentUserId)) : null;
}

export async function getEventAttendeeForUser(db: Db, eventId: string, attendeeId: string, currentUserId: string) {
	const row = await getEventAttendeeRowForUser(db, eventId, currentUserId, attendeeId);

	return row ? toEventAttendeeResponse(row, currentUserId) : null;
}

export async function listEventRegistrationsForUser(db: Db, eventId: string, currentUserId: string) {
	const rows = await listEventRegistrationRowsForUser(db, eventId, currentUserId);

	return rows ? rows.map((row) => toEventRegistrationResponse(row, currentUserId)) : null;
}

export async function joinEventForUser(db: Db, eventId: string, currentUserId: string) {
	const row = await getEventRowForUser(db, eventId, currentUserId);

	if (!row) {
		return null;
	}

	const now = new Date();

	if (now < row.startAt) {
		throw new HTTPException(409, { message: "This event is not live yet" });
	}

	if (now >= row.endAt) {
		throw new HTTPException(409, { message: "This event has ended" });
	}

	const attendance = await markEventAttendance(db, eventId, currentUserId);

	return {
		eventId: attendance.eventId,
		eventEndsAt: row.endAt,
		userId: attendance.userId,
		lastSeenAt: attendance.lastSeenAt.toISOString(),
	};
}

export async function resolveNearbyCredentialsForUser(
	db: Db,
	secret: string,
	eventId: string,
	currentUserId: string,
	credentials: string[],
) {
	const eventRow = await getEventRowForUser(db, eventId, currentUserId);
	const now = new Date();

	if (!eventRow || now < eventRow.startAt || now >= eventRow.endAt || !(await isUserCheckedIntoEvent(db, eventId, currentUserId))) {
		return null;
	}

	const uniqueCredentials = [...new Set(credentials)];
	const decodedCredentials = await Promise.all(
		uniqueCredentials.map(async (credential) => ({
			credential,
			payload: await readNearbyCredential(secret, credential),
		})),
	);
	const eventCredentials = decodedCredentials.filter(
		(entry): entry is typeof entry & { payload: NonNullable<typeof entry.payload> } => entry.payload?.eventId === eventId,
	);
	const attendeeRows = await listEventAttendeeRowsForUser(db, eventId, currentUserId);
	const attendeesByUserId = new Map((attendeeRows ?? []).map((row) => [row.userId, toEventAttendeeResponse(row, currentUserId)]));

	return eventCredentials.flatMap(({ credential, payload }) => {
		const attendee = attendeesByUserId.get(payload.userId);

		return attendee
			? [
					{
						attendee,
						credential,
						peerId: payload.peerId,
						publicKey: payload.publicKey,
					},
				]
			: [];
	});
}

export async function leaveEventForUser(db: Db, eventId: string, currentUserId: string) {
	const eventRow = await getEventRowForUser(db, eventId, currentUserId);

	if (!eventRow) {
		return null;
	}

	await clearEventAttendance(db, eventId, currentUserId);

	return { eventId, userId: currentUserId };
}

export async function createEventForUser(db: Db, currentUserId: string, input: CreateEventInput) {
	const startAt = new Date(input.startAt);
	const endAt = new Date(input.endAt);

	if (Number.isNaN(startAt.getTime()) || Number.isNaN(endAt.getTime())) {
		throw new HTTPException(400, { message: "Event date and time are invalid" });
	}

	if (endAt <= startAt) {
		throw new HTTPException(400, { message: "Event end time must be after the start time" });
	}

	const id = crypto.randomUUID();
	const inviteCode = await generateInviteCode(db);

	await createEventRecord(db, {
		id,
		title: input.title.trim(),
		description: input.description.trim(),
		venue: input.venue.trim(),
		inviteCode,
		capacity: input.capacity ?? null,
		startAt,
		endAt,
		createdById: currentUserId,
	});

	const createdEvent = await getEventForUser(db, id, currentUserId);

	if (!createdEvent) {
		throw new HTTPException(500, { message: "Failed to create event" });
	}

	return createdEvent;
}

export async function joinEventByInviteCode(db: Db, currentUserId: string, inviteCode: string) {
	const normalizedInviteCode = inviteCode.trim().toUpperCase();
	const targetEvent = await findEventByInviteCode(db, normalizedInviteCode);

	if (!targetEvent) {
		throw new HTTPException(404, { message: "Invite code not found" });
	}

	if (targetEvent.endAt <= new Date()) {
		throw new HTTPException(409, { message: "This event has already ended" });
	}

	if (targetEvent.createdById !== currentUserId) {
		const existingRegistration = await hasEventRegistration(db, targetEvent.id, currentUserId);

		if (!existingRegistration) {
			const registrationCount = await getEventRegistrationCount(db, targetEvent.id);

			if (targetEvent.capacity !== null && registrationCount >= targetEvent.capacity) {
				throw new HTTPException(409, { message: "This event is at capacity" });
			}

			await createEventRegistration(db, targetEvent.id, currentUserId);
		}
	}

	const userEvent = await getEventForUser(db, targetEvent.id, currentUserId);

	if (!userEvent) {
		throw new HTTPException(500, { message: "Failed to load registered event" });
	}

	return userEvent;
}

async function generateInviteCode(db: Db) {
	for (let attempt = 0; attempt < INVITE_CODE_GENERATION_ATTEMPTS; attempt += 1) {
		const inviteCode = randomCode(6);
		const exists = await eventInviteCodeExists(db, inviteCode);

		if (!exists) {
			return inviteCode;
		}
	}

	throw new HTTPException(500, { message: "Failed to generate invite code" });
}

function randomCode(length: number) {
	const alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
	const bytes = crypto.getRandomValues(new Uint8Array(length));

	return Array.from(bytes, (byte) => alphabet[byte % alphabet.length]).join("");
}
