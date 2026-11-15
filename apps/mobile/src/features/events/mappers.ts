import type { LocalEventAttendeeRow, LocalEventRow } from "./schema";
import type { Event, EventAttendee, RemoteEvent } from "./types";

export function toEvent(row: LocalEventRow): Event {
	return {
		id: row.id,
		remoteId: row.remoteId,
		title: row.title,
		description: row.description,
		venue: row.venue,
		hostLabel: row.hostLabel,
		registrationCount: row.registrationCount,
		createdByUser: row.createdByUser,
		inviteCode: row.inviteCode,
		capacity: row.capacity,
		startAt: new Date(row.startAt),
		endAt: new Date(row.endAt),
		syncStatus: row.syncStatus,
	};
}

export function toEventAttendee(row: LocalEventAttendeeRow): EventAttendee {
	return {
		userId: row.userId,
		name: row.name,
		image: row.image,
		headline: row.headline,
		askMeAbout: parseAskMeAbout(row.askMeAbout),
		role: row.role,
		isCurrentUser: row.isCurrentUser,
		lastSeenAt: row.lastSeenAt,
	};
}

function parseAskMeAbout(value: string) {
	try {
		const parsed: unknown = JSON.parse(value);

		if (!Array.isArray(parsed)) {
			return [];
		}

		return parsed.filter((topic): topic is string => typeof topic === "string");
	} catch {
		return [];
	}
}

export function toLocalEventInsert(viewerId: string, event: RemoteEvent) {
	const now = new Date().toISOString();

	return {
		id: event.id,
		remoteId: event.id,
		viewerId,
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
		createdAt: now,
		updatedAt: now,
	} as const;
}
