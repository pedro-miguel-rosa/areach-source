import { HTTPException } from "hono/http-exception";
import { sendAttendeeReportNotification } from "@/lib/auth/email";
import { getDb } from "@/lib/db";
import { createOpenAPIApp } from "@/lib/openapi";
import { requireSession } from "@/modules/auth/session";
import { blockAttendeeForUser, reportAttendeeForUser } from "@/modules/privacy/service";
import { getOrIssueNearbyCredential } from "./nearby-credentials";
import {
	blockAttendeeRoute,
	createEventRoute,
	getEventAttendeeRoute,
	getEventRoute,
	joinEventByInviteCodeRoute,
	joinEventRoute,
	leaveEventRoute,
	listEventAttendeesRoute,
	listEventRegistrationsRoute,
	listEventsRoute,
	reportAttendeeRoute,
	resolveNearbyCredentialsRoute,
} from "./routes";
import {
	createEventForUser,
	getEventAttendeeForUser,
	getEventForUser,
	joinEventByInviteCode,
	joinEventForUser,
	leaveEventForUser,
	listEventAttendeesForUser,
	listEventRegistrationsForUser,
	listEventsForUser,
	resolveNearbyCredentialsForUser,
} from "./service";

export const events = createOpenAPIApp();

events.openapi(listEventsRoute, async (c) => {
	const session = await requireSession(c.env, c.req.raw.headers);
	const db = getDb(c.env);

	const userEvents = await listEventsForUser(db, session.user.id);

	return c.json(userEvents, 200);
});

events.openapi(getEventRoute, async (c) => {
	const session = await requireSession(c.env, c.req.raw.headers);
	const db = getDb(c.env);

	const { id } = c.req.valid("param");

	const userEvent = await getEventForUser(db, id, session.user.id);

	if (!userEvent) {
		throw new HTTPException(404, { message: "Event not found" });
	}

	return c.json(userEvent, 200);
});

events.openapi(listEventAttendeesRoute, async (c) => {
	const session = await requireSession(c.env, c.req.raw.headers);
	const db = getDb(c.env);

	const { id } = c.req.valid("param");

	const attendees = await listEventAttendeesForUser(db, id, session.user.id);

	if (!attendees) {
		throw new HTTPException(404, { message: "Event not found" });
	}

	return c.json(attendees, 200);
});

events.openapi(getEventAttendeeRoute, async (c) => {
	const session = await requireSession(c.env, c.req.raw.headers);
	const db = getDb(c.env);
	const { id, attendeeId } = c.req.valid("param");

	const attendee = await getEventAttendeeForUser(db, id, attendeeId, session.user.id);

	if (!attendee) {
		throw new HTTPException(404, { message: "Attendee not found" });
	}

	return c.json(attendee, 200);
});

events.openapi(reportAttendeeRoute, async (c) => {
	const session = await requireSession(c.env, c.req.raw.headers);
	const db = getDb(c.env);
	const { id, attendeeId } = c.req.valid("param");
	const { reason } = c.req.valid("json");

	const report = await reportAttendeeForUser(db, {
		eventId: id,
		reporterUserId: session.user.id,
		reportedUserId: attendeeId,
		reason,
	});

	if (report.created) {
		await sendAttendeeReportNotification(c.env.EMAIL, c.env.MODERATION_EMAIL, {
			eventId: id,
			reason,
			reportId: report.id,
		}).catch((error) => {
			console.error("Unable to send attendee report notification", error);
		});
	}

	return c.json(report, 200);
});

events.openapi(blockAttendeeRoute, async (c) => {
	const session = await requireSession(c.env, c.req.raw.headers);
	const db = getDb(c.env);
	const { id, attendeeId } = c.req.valid("param");

	const result = await blockAttendeeForUser(db, id, session.user.id, attendeeId);

	return c.json(result, 200);
});

events.openapi(listEventRegistrationsRoute, async (c) => {
	const session = await requireSession(c.env, c.req.raw.headers);
	const db = getDb(c.env);

	const { id } = c.req.valid("param");

	const registrations = await listEventRegistrationsForUser(db, id, session.user.id);

	if (!registrations) {
		throw new HTTPException(404, { message: "Event not found" });
	}

	return c.json(registrations, 200);
});

events.openapi(joinEventRoute, async (c) => {
	const session = await requireSession(c.env, c.req.raw.headers);
	const db = getDb(c.env);

	const { id } = c.req.valid("param");
	const { nearbyPeerId, nearbyPublicKey } = c.req.valid("json");

	const attendance = await joinEventForUser(db, id, session.user.id);

	if (!attendance) {
		throw new HTTPException(404, { message: "Event not found" });
	}

	const { eventEndsAt, ...attendanceResponse } = attendance;
	const nearbyIdentity = await getOrIssueNearbyCredential(
		db,
		c.env.BETTER_AUTH_SECRET,
		attendance.eventId,
		attendance.userId,
		nearbyPeerId,
		nearbyPublicKey,
		eventEndsAt,
	);

	return c.json({ ...attendanceResponse, ...nearbyIdentity }, 200);
});

events.openapi(resolveNearbyCredentialsRoute, async (c) => {
	const session = await requireSession(c.env, c.req.raw.headers);
	const db = getDb(c.env);
	const { id } = c.req.valid("param");
	const { credentials } = c.req.valid("json");
	const nearbyIdentities = await resolveNearbyCredentialsForUser(db, c.env.BETTER_AUTH_SECRET, id, session.user.id, credentials);

	if (!nearbyIdentities) {
		throw new HTTPException(404, { message: "Live attendance not found" });
	}

	return c.json(nearbyIdentities, 200);
});

events.openapi(leaveEventRoute, async (c) => {
	const session = await requireSession(c.env, c.req.raw.headers);
	const db = getDb(c.env);
	const { id } = c.req.valid("param");
	const departure = await leaveEventForUser(db, id, session.user.id);

	if (!departure) {
		throw new HTTPException(404, { message: "Event not found" });
	}

	return c.json(departure, 200);
});

events.openapi(createEventRoute, async (c) => {
	const session = await requireSession(c.env, c.req.raw.headers);
	const db = getDb(c.env);

	const userEvent = await createEventForUser(db, session.user.id, c.req.valid("json"));

	return c.json(userEvent, 201);
});

events.openapi(joinEventByInviteCodeRoute, async (c) => {
	const session = await requireSession(c.env, c.req.raw.headers);
	const db = getDb(c.env);

	const { inviteCode } = c.req.valid("json");

	const userEvent = await joinEventByInviteCode(db, session.user.id, inviteCode);

	return c.json(userEvent, 200);
});
