import { apiClient } from "@/lib/api/client";
import type {
	CreateEventMutationPayload,
	JoinEventMutationPayload,
	LiveEventAttendance,
	NearbyIdentity,
	RemoteEvent,
	RemoteEventAttendee,
	ResolvedNearbyIdentity,
} from "./types";

export async function fetchRemoteEvents() {
	const { data, error } = await apiClient.GET("/events");

	if (error) {
		throw new Error(error.message);
	}

	return (data ?? []) as RemoteEvent[];
}

export async function createRemoteEvent(body: CreateEventMutationPayload) {
	const { data, error } = await apiClient.POST("/events", { body });

	if (error || !data) {
		throw new Error(error.message ?? "Failed to create event");
	}

	return data as RemoteEvent;
}

export async function joinRemoteEvent(body: JoinEventMutationPayload) {
	const { data, error } = await apiClient.POST("/events/join", { body });

	if (error || !data) {
		throw new Error(error?.message ?? "Failed to join event");
	}

	return data as RemoteEvent;
}

export async function fetchRemoteEventAttendees(eventId: string) {
	const { data, error } = await apiClient.GET("/events/{id}/attendees", {
		params: {
			path: {
				id: eventId,
			},
		},
	});

	if (error) {
		throw new Error(error.message);
	}

	return (data ?? []) as RemoteEventAttendee[];
}

export async function fetchRemoteEventAttendee(eventId: string, attendeeId: string) {
	const { data, error } = await apiClient.GET("/events/{id}/attendees/{attendeeId}", {
		params: {
			path: {
				id: eventId,
				attendeeId,
			},
		},
	});

	if (error || !data) {
		throw new Error(error?.message ?? "Attendee not found");
	}

	return data as RemoteEventAttendee;
}

export async function refreshRemoteLiveAttendance(eventId: string, identity: NearbyIdentity) {
	const { data, error } = await apiClient.POST("/events/{id}/join", {
		params: {
			path: {
				id: eventId,
			},
		},
		body: {
			nearbyPeerId: identity.peerId,
			nearbyPublicKey: identity.publicKey,
		},
	});

	if (error || !data) {
		throw new Error(error?.message ?? "Failed to refresh live attendance");
	}

	return data as LiveEventAttendance;
}

export async function resolveRemoteNearbyCredentials(eventId: string, credentials: string[]) {
	const { data, error } = await apiClient.POST("/events/{id}/nearby-identities", {
		params: {
			path: {
				id: eventId,
			},
		},
		body: { credentials },
	});

	if (error || !data) {
		throw new Error(error?.message ?? "Failed to resolve nearby attendee");
	}

	return data as ResolvedNearbyIdentity[];
}

export async function leaveRemoteLiveEvent(eventId: string) {
	const { error } = await apiClient.POST("/events/{id}/leave", {
		params: {
			path: {
				id: eventId,
			},
		},
	});

	if (error) {
		throw new Error(error.message ?? "Failed to leave live event");
	}
}
