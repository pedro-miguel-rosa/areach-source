import { HTTPException } from "hono/http-exception";
import type { Db } from "@/lib/db";
import { ATTENDEE_REPORT_REASONS, type AttendeeReportReason } from "./constants";
import {
	createAttendeeReport,
	createUserBlock,
	deleteUserBlock,
	getUserBlockState,
	isVisibleEventAttendee,
	listUserBlocks,
} from "./repository";

export async function reportAttendeeForUser(
	db: Db,
	input: {
		eventId: string;
		reporterUserId: string;
		reportedUserId: string;
		reason: AttendeeReportReason;
	},
) {
	assertReportReason(input.reason);
	assertDifferentUsers(input.reporterUserId, input.reportedUserId);
	await assertVisibleEventAttendee(db, input.eventId, input.reporterUserId, input.reportedUserId);

	const report = await createAttendeeReport(db, input);

	if (!report) {
		throw new HTTPException(500, { message: "Unable to save attendee report" });
	}

	return report;
}

export async function blockAttendeeForUser(db: Db, eventId: string, blockerUserId: string, blockedUserId: string) {
	assertDifferentUsers(blockerUserId, blockedUserId);
	await assertVisibleEventAttendee(db, eventId, blockerUserId, blockedUserId);

	await createUserBlock(db, blockerUserId, blockedUserId);

	return { blocked: true as const };
}

export async function unblockUserForUser(db: Db, blockerUserId: string, blockedUserId: string) {
	assertDifferentUsers(blockerUserId, blockedUserId);
	await deleteUserBlock(db, blockerUserId, blockedUserId);

	return { blocked: false as const };
}

export async function getBlockStateForUser(db: Db, blockerUserId: string, blockedUserId: string) {
	assertDifferentUsers(blockerUserId, blockedUserId);

	return { blocked: await getUserBlockState(db, blockerUserId, blockedUserId) };
}

export async function listBlockedUsersForUser(db: Db, blockerUserId: string) {
	return listUserBlocks(db, blockerUserId);
}

async function assertVisibleEventAttendee(db: Db, eventId: string, viewerUserId: string, targetUserId: string) {
	if (!(await isVisibleEventAttendee(db, eventId, viewerUserId, targetUserId))) {
		throw new HTTPException(404, { message: "Attendee not found" });
	}
}

function assertDifferentUsers(reporterUserId: string, reportedUserId: string) {
	if (reporterUserId === reportedUserId) {
		throw new HTTPException(400, { message: "You cannot apply this action to yourself" });
	}
}

function assertReportReason(reason: string): asserts reason is AttendeeReportReason {
	if (!(ATTENDEE_REPORT_REASONS as readonly string[]).includes(reason)) {
		throw new HTTPException(400, { message: "Report reason is invalid" });
	}
}
