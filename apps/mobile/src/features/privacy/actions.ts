import { removeLocalEventAttendees } from "@/features/events/repository";
import { blockRemoteEventAttendee, reportRemoteEventAttendee, unblockRemoteUser } from "./api";
import { addLocalBlock, removeLocalBlock } from "./repository";
import type { AttendeeReportReason, BlockedUser } from "./types";

export async function blockEventAttendee(input: { attendee: BlockedUser; eventId: string; viewerId: string }) {
	await blockRemoteEventAttendee(input.eventId, input.attendee.userId);
	await addLocalBlock(input.viewerId, input.attendee);
	await removeLocalEventAttendees(input.viewerId, input.attendee.userId);
}

export async function unblockUser(viewerId: string, blockedUserId: string) {
	await unblockRemoteUser(blockedUserId);
	await removeLocalBlock(viewerId, blockedUserId);
}

export async function reportEventAttendee(eventId: string, attendeeId: string, reason: AttendeeReportReason) {
	return reportRemoteEventAttendee(eventId, attendeeId, reason);
}
