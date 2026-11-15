import type { SQLWrapper } from "drizzle-orm";
import { sql } from "drizzle-orm";
import { event, eventAttendee, eventRegistration } from "@/modules/events/schemas";
import { profileTable } from "@/modules/profile/schemas";
import { userBlock } from "./schemas";

/**
 * The single event-access rule used by event and discovery queries. A host,
 * registrant, or checked-in attendee is an event member.
 */
export function eventAccessibleToUserCondition(userId: string) {
	return eventMemberCondition(event.id, userId);
}

/**
 * Attendee discovery is mutual. The target's discoverability setting and a
 * block in either direction are checked in SQL so no client can bypass the
 * rule by guessing an attendee ID or using a stale cache.
 */
export function attendeeVisibleToViewerCondition(viewerId: string, targetUserId: SQLWrapper) {
	return sql<boolean>`(
		${targetUserId} = ${viewerId}
		OR (
			COALESCE((
				SELECT ${profileTable.isDiscoverable}
				FROM ${profileTable}
				WHERE ${profileTable.userId} = ${targetUserId}
				LIMIT 1
			), true) = true
			AND NOT EXISTS (
				SELECT 1
				FROM ${userBlock}
				WHERE ${userBlock.blockerUserId} = ${viewerId}
					AND ${userBlock.blockedUserId} = ${targetUserId}
			)
			AND NOT EXISTS (
				SELECT 1
				FROM ${userBlock}
				WHERE ${userBlock.blockerUserId} = ${targetUserId}
					AND ${userBlock.blockedUserId} = ${viewerId}
			)
		)
	)`;
}

/** A user is associated with an event as its host, registrant, or attendee. */
export function eventMemberCondition(eventId: SQLWrapper, userId: string) {
	return sql`(
		${event.createdById} = ${userId}
		OR EXISTS (
			SELECT 1
			FROM ${eventRegistration}
			WHERE ${eventRegistration.eventId} = ${eventId}
				AND ${eventRegistration.userId} = ${userId}
		)
		OR EXISTS (
			SELECT 1
			FROM ${eventAttendee}
			WHERE ${eventAttendee.eventId} = ${eventId}
				AND ${eventAttendee.userId} = ${userId}
		)
	)`;
}
