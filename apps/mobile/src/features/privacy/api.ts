import { apiClient } from "@/lib/api/client";
import type { AttendeeReportReason, BlockedUser, ReportResult } from "./types";

export async function fetchRemoteBlockedUsers() {
	const { data, error } = await apiClient.GET("/privacy/blocks");

	if (error) {
		throw new Error(error.message);
	}

	return (data ?? []) as BlockedUser[];
}

export async function blockRemoteEventAttendee(eventId: string, attendeeId: string) {
	const { data, error } = await apiClient.POST("/events/{id}/attendees/{attendeeId}/block", {
		params: { path: { id: eventId, attendeeId } },
	});

	if (error || !data) {
		throw new Error(error?.message ?? "Unable to block this attendee");
	}

	return data;
}

export async function unblockRemoteUser(userId: string) {
	const { data, error } = await apiClient.DELETE("/privacy/blocks/{userId}", {
		params: { path: { userId } },
	});

	if (error || !data) {
		throw new Error(error?.message ?? "Unable to unblock this user");
	}

	return data;
}

export async function reportRemoteEventAttendee(eventId: string, attendeeId: string, reason: AttendeeReportReason) {
	const { data, error } = await apiClient.POST("/events/{id}/attendees/{attendeeId}/report", {
		params: { path: { id: eventId, attendeeId } },
		body: { reason },
	});

	if (error || !data) {
		throw new Error(error?.message ?? "Unable to submit this report");
	}

	return data as ReportResult;
}
