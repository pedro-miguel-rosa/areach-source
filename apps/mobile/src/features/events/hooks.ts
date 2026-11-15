import { useLiveQuery } from "drizzle-orm/expo-sqlite";
import { useEffect, useMemo, useState } from "react";
import { showToast } from "@/lib/ui/toast";
import { createEvent, joinEvent as joinEventAction } from "./actions";
import { fetchRemoteEventAttendee } from "./api";
import { toEvent, toEventAttendee } from "./mappers";
import { getEventAttendeesQuery, getEventByIdQuery, getEventsQuery, getUpcomingEventsQuery } from "./repository";
import type { CreateLocalEventInput, JoinEventInput } from "./types";

type LocalQueryResult<TData> = {
	data: TData;
	error: Error | undefined;
	isPending: boolean;
};

export function useUpcomingEvents(userId: string, now: Date) {
	const queryState = useLiveQuery(getUpcomingEventsQuery(userId, now), [userId, now.toISOString()]);

	return {
		data: queryState.data.map(toEvent),
		error: queryState.error,
		isPending: !queryState.updatedAt && !queryState.error,
	} satisfies LocalQueryResult<ReturnType<typeof toEvent>[]>;
}

export function useEvents(viewerId: string) {
	const queryState = useLiveQuery(getEventsQuery(viewerId), [viewerId]);

	return {
		data: queryState.data.map(toEvent),
		error: queryState.error,
		isPending: !queryState.updatedAt && !queryState.error,
	} satisfies LocalQueryResult<ReturnType<typeof toEvent>[]>;
}

export function useEventById(viewerId: string, eventId: string) {
	const queryState = useLiveQuery(getEventByIdQuery(viewerId, eventId), [viewerId, eventId]);

	return {
		data: queryState.data[0] ? toEvent(queryState.data[0]) : undefined,
		error: queryState.error,
		isPending: !queryState.updatedAt && !queryState.error,
	} satisfies LocalQueryResult<ReturnType<typeof toEvent> | undefined>;
}

export function useEventAttendees(viewerId: string, eventId: string) {
	const queryState = useLiveQuery(getEventAttendeesQuery(viewerId, eventId), [viewerId, eventId]);
	const attendees = useMemo(() => queryState.data.map(toEventAttendee), [queryState.data]);

	return {
		data: attendees,
		error: queryState.error,
		isPending: !queryState.updatedAt && !queryState.error,
	} satisfies LocalQueryResult<ReturnType<typeof toEventAttendee>[]>;
}

export function useEventAttendeeById(viewerId: string, eventId: string, attendeeId: string) {
	const [remoteState, setRemoteState] = useState<{
		data?: ReturnType<typeof toEventAttendee>;
		error?: Error;
		isPending: boolean;
	}>({ isPending: true });

	useEffect(() => {
		let isMounted = true;
		setRemoteState({ isPending: true });

		if (!viewerId || !eventId || !attendeeId) {
			setRemoteState({ isPending: false });
			return () => {
				isMounted = false;
			};
		}

		void fetchRemoteEventAttendee(eventId, attendeeId)
			.then((attendee) => {
				if (isMounted) {
					setRemoteState({ data: attendee, isPending: false });
				}
			})
			.catch((error) => {
				if (isMounted) {
					setRemoteState({ error: error instanceof Error ? error : new Error("Attendee not found"), isPending: false });
				}
			});

		return () => {
			isMounted = false;
		};
	}, [attendeeId, eventId, viewerId]);

	return {
		data: remoteState.data,
		error: remoteState.error,
		isPending: remoteState.isPending,
	} satisfies LocalQueryResult<ReturnType<typeof toEventAttendee> | undefined>;
}

export function useCreateEvent() {
	const [isSubmitting, setIsSubmitting] = useState(false);

	async function submitCreateEvent(input: CreateLocalEventInput) {
		setIsSubmitting(true);

		try {
			return await createEvent(input);
		} catch (error) {
			const message = error instanceof Error && error.message ? error.message : "We couldn't save your event. Please try again.";

			showToast({ error, message, tone: "error", durationMs: 5000 });
			return null;
		} finally {
			setIsSubmitting(false);
		}
	}

	return { isSubmitting, submitCreateEvent };
}

export function useJoinEvent() {
	const [isSubmitting, setIsSubmitting] = useState(false);

	async function joinEvent(input: JoinEventInput) {
		setIsSubmitting(true);

		try {
			return await joinEventAction(input);
		} catch (error) {
			const message = error instanceof Error && error.message ? error.message : "We couldn't join that invite right now. Please try again.";

			showToast({ error, message, tone: "error", durationMs: 5000 });
			return false;
		} finally {
			setIsSubmitting(false);
		}
	}

	return { isSubmitting, joinEvent };
}
