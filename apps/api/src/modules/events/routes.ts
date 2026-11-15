import { createRoute, z } from "@hono/zod-openapi";
import { ATTENDEE_REPORT_REASONS, REPORT_STATUSES } from "@/modules/privacy/constants";

export const errorResponseSchema = z.object({
	message: z.string().openapi({ example: "Unauthorized" }),
	code: z.string().openapi({ example: "UNAUTHORIZED" }),
});

export const eventResponseSchema = z.object({
	id: z.string().openapi({ example: "event_01" }),
	title: z.string().openapi({ example: "Founder Breakfast" }),
	description: z.string().openapi({ example: "A small breakfast for local founders and operators." }),
	venue: z.string().openapi({ example: "Comoba, Lisbon" }),
	inviteCode: z.string().nullable().openapi({ example: "7G4KQ2" }),
	capacity: z.number().int().nullable().openapi({ example: 20 }),
	registrationCount: z.number().int().nonnegative().openapi({ example: 8 }),
	createdByUser: z.boolean().openapi({ example: true }),
	hostLabel: z.string().openapi({ example: "Hosted by you" }),
	startAt: z.iso.datetime({ offset: true }).openapi({ example: "2026-04-22T18:00:00.000Z" }),
	endAt: z.iso.datetime({ offset: true }).openapi({ example: "2026-04-22T20:00:00.000Z" }),
});

export const eventAttendeeResponseSchema = z.object({
	userId: z.string().openapi({ example: "user_01" }),
	name: z.string().openapi({ example: "Pedro Silva" }),
	image: z.string().nullable().openapi({ example: "https://example.invalid/avatar.png" }),
	headline: z.string().openapi({ example: "Founder and product builder" }),
	askMeAbout: z.array(z.string()).openapi({ example: ["Web Development", "Startups", "Coffee & Great Spots"] }),
	role: z.enum(["host", "attendee"]).openapi({ example: "attendee" }),
	isCurrentUser: z.boolean().openapi({ example: false }),
	lastSeenAt: z.iso.datetime({ offset: true }).openapi({ example: "2026-04-22T18:20:00.000Z" }),
});

const attendeeReportBodySchema = z.object({
	reason: z.enum(ATTENDEE_REPORT_REASONS),
});

const attendeeReportResponseSchema = z.object({
	id: z.string().openapi({ example: "report_01" }),
	status: z.enum(REPORT_STATUSES).openapi({ example: "pending" }),
	created: z.boolean().openapi({ example: true }),
});

export const eventRegistrationResponseSchema = z.object({
	userId: z.string().openapi({ example: "user_01" }),
	name: z.string().openapi({ example: "Pedro Silva" }),
	role: z.enum(["host", "registrant"]).openapi({ example: "registrant" }),
	isCurrentUser: z.boolean().openapi({ example: false }),
	isAttending: z.boolean().openapi({ example: true }),
});

export const eventAttendanceResponseSchema = z.object({
	eventId: z.string().openapi({ example: "event_01" }),
	userId: z.string().openapi({ example: "user_01" }),
	lastSeenAt: z.iso.datetime({ offset: true }).openapi({ example: "2026-04-22T18:20:00.000Z" }),
	nearbyCredential: z.string().openapi({ example: "v2.opaque-initialization-vector.opaque-credential" }),
	nearbyCredentialExpiresAt: z.iso.datetime({ offset: true }).openapi({ example: "2026-04-22T18:25:00.000Z" }),
	nearbyEventScope: z.string().openapi({ example: "1C8krD9mPDqPdo7uHccvOaC0" }),
	nearbyTransportKey: z.string().openapi({ example: "opaque-event-transport-key" }),
});

const nearbyIdentityBodySchema = z.object({
	nearbyPeerId: z
		.string()
		.trim()
		.regex(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i),
	nearbyPublicKey: z
		.string()
		.trim()
		.length(88)
		.regex(/^[A-Za-z0-9+/]+={0,2}$/),
});

const nearbyIdentityResponseSchema = z.object({
	attendee: eventAttendeeResponseSchema,
	credential: z.string(),
	peerId: z.string(),
	publicKey: z.string(),
});

const resolveNearbyCredentialsBodySchema = z.object({
	credentials: z.array(z.string().trim().min(1).max(2048)).min(1).max(100),
});

const eventDepartureResponseSchema = z.object({
	eventId: z.string().openapi({ example: "event_01" }),
	userId: z.string().openapi({ example: "user_01" }),
});

export const createEventBodySchema = z.object({
	title: z.string().trim().min(1).max(120).openapi({ example: "Founder Breakfast" }),
	description: z.string().trim().max(2000).default("").openapi({ example: "A small breakfast for local founders and operators." }),
	venue: z.string().trim().min(1).max(160).openapi({ example: "Comoba, Lisbon" }),
	capacity: z.number().int().positive().max(5000).nullable().optional().openapi({ example: 20 }),
	startAt: z.iso.datetime({ offset: true }).openapi({ example: "2026-04-22T18:00:00.000Z" }),
	endAt: z.iso.datetime({ offset: true }).openapi({ example: "2026-04-22T20:00:00.000Z" }),
});

export const joinEventByInviteCodeBodySchema = z.object({
	inviteCode: z.string().trim().min(1).max(6).openapi({ example: "7G4KQ2" }),
});

export const eventIdParamsSchema = z.object({
	id: z.string().trim().min(1).max(200),
});

export const eventAttendeeParamsSchema = eventIdParamsSchema.extend({
	attendeeId: z.string().trim().min(1).max(200),
});

export const listEventsRoute = createRoute({
	method: "get",
	path: "/",
	tags: ["Events"],
	responses: {
		200: {
			description: "Events for the authenticated user.",
			content: {
				"application/json": {
					schema: z.array(eventResponseSchema),
				},
			},
		},
		401: {
			description: "Unauthorized.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
				},
			},
		},
	},
});

export const getEventRoute = createRoute({
	method: "get",
	path: "/{id}",
	tags: ["Events"],
	request: {
		params: eventIdParamsSchema,
	},
	responses: {
		200: {
			description: "An event the authenticated user created or registered for.",
			content: {
				"application/json": {
					schema: eventResponseSchema,
				},
			},
		},
		401: {
			description: "Unauthorized.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
				},
			},
		},
		404: {
			description: "Event not found.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
					example: {
						message: "Event not found",
						code: "NOT_FOUND",
					},
				},
			},
		},
	},
});

export const listEventAttendeesRoute = createRoute({
	method: "get",
	path: "/{id}/attendees",
	tags: ["Events"],
	request: {
		params: eventIdParamsSchema,
	},
	responses: {
		200: {
			description: "Users checked into the live event.",
			content: {
				"application/json": {
					schema: z.array(eventAttendeeResponseSchema),
				},
			},
		},
		401: {
			description: "Unauthorized.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
				},
			},
		},
		404: {
			description: "Event not found.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
					example: {
						message: "Event not found",
						code: "NOT_FOUND",
					},
				},
			},
		},
	},
});

export const getEventAttendeeRoute = createRoute({
	method: "get",
	path: "/{id}/attendees/{attendeeId}",
	tags: ["Events"],
	request: {
		params: eventAttendeeParamsSchema,
	},
	responses: {
		200: {
			description: "A visible attendee in the live event.",
			content: { "application/json": { schema: eventAttendeeResponseSchema } },
		},
		401: {
			description: "Unauthorized.",
			content: { "application/json": { schema: errorResponseSchema } },
		},
		404: {
			description: "Attendee not found or not visible to the authenticated user.",
			content: { "application/json": { schema: errorResponseSchema } },
		},
	},
});

export const reportAttendeeRoute = createRoute({
	method: "post",
	path: "/{id}/attendees/{attendeeId}/report",
	tags: ["Events"],
	request: {
		params: eventAttendeeParamsSchema,
		body: {
			required: true,
			content: { "application/json": { schema: attendeeReportBodySchema } },
		},
	},
	responses: {
		200: {
			description: "The attendee report was saved or had already been submitted.",
			content: { "application/json": { schema: attendeeReportResponseSchema } },
		},
		400: {
			description: "Invalid report request.",
			content: { "application/json": { schema: errorResponseSchema } },
		},
		401: {
			description: "Unauthorized.",
			content: { "application/json": { schema: errorResponseSchema } },
		},
		404: {
			description: "Attendee not found or not visible to the authenticated user.",
			content: { "application/json": { schema: errorResponseSchema } },
		},
	},
});

export const blockAttendeeRoute = createRoute({
	method: "post",
	path: "/{id}/attendees/{attendeeId}/block",
	tags: ["Events"],
	request: {
		params: eventAttendeeParamsSchema,
	},
	responses: {
		200: {
			description: "The attendee was blocked for the authenticated user.",
			content: { "application/json": { schema: z.object({ blocked: z.literal(true) }) } },
		},
		400: {
			description: "Invalid block request.",
			content: { "application/json": { schema: errorResponseSchema } },
		},
		401: {
			description: "Unauthorized.",
			content: { "application/json": { schema: errorResponseSchema } },
		},
		404: {
			description: "Attendee not found.",
			content: { "application/json": { schema: errorResponseSchema } },
		},
	},
});

export const listEventRegistrationsRoute = createRoute({
	method: "get",
	path: "/{id}/registrations",
	tags: ["Events"],
	request: {
		params: eventIdParamsSchema,
	},
	responses: {
		200: {
			description: "Registrations for an event the authenticated user created or registered for.",
			content: {
				"application/json": {
					schema: z.array(eventRegistrationResponseSchema),
				},
			},
		},
		401: {
			description: "Unauthorized.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
				},
			},
		},
		404: {
			description: "Event not found.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
					example: {
						message: "Event not found",
						code: "NOT_FOUND",
					},
				},
			},
		},
	},
});

export const joinEventRoute = createRoute({
	method: "post",
	path: "/{id}/join",
	tags: ["Events"],
	request: {
		params: eventIdParamsSchema,
		body: {
			required: true,
			content: {
				"application/json": {
					schema: nearbyIdentityBodySchema,
				},
			},
		},
	},
	responses: {
		200: {
			description: "Marked the authenticated user as currently attending the live event.",
			content: {
				"application/json": {
					schema: eventAttendanceResponseSchema,
				},
			},
		},
		401: {
			description: "Unauthorized.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
				},
			},
		},
		404: {
			description: "Event not found.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
					example: {
						message: "Event not found",
						code: "NOT_FOUND",
					},
				},
			},
		},
		409: {
			description: "The event is not currently live.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
					example: {
						message: "This event is not live yet",
						code: "CONFLICT",
					},
				},
			},
		},
	},
});

export const resolveNearbyCredentialsRoute = createRoute({
	method: "post",
	path: "/{id}/nearby-identities",
	tags: ["Events"],
	request: {
		params: eventIdParamsSchema,
		body: {
			required: true,
			content: {
				"application/json": {
					schema: resolveNearbyCredentialsBodySchema,
				},
			},
		},
	},
	responses: {
		200: {
			description: "Resolved authenticated nearby attendee credentials.",
			content: {
				"application/json": {
					schema: z.array(nearbyIdentityResponseSchema),
				},
			},
		},
		401: {
			description: "Unauthorized.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
				},
			},
		},
		404: {
			description: "The requester is not checked into this live event.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
				},
			},
		},
	},
});

export const leaveEventRoute = createRoute({
	method: "post",
	path: "/{id}/leave",
	tags: ["Events"],
	request: {
		params: eventIdParamsSchema,
	},
	responses: {
		200: {
			description: "Marked the authenticated user as no longer attending the live event.",
			content: {
				"application/json": {
					schema: eventDepartureResponseSchema,
				},
			},
		},
		401: {
			description: "Unauthorized.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
				},
			},
		},
		404: {
			description: "Event not found.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
				},
			},
		},
	},
});

export const createEventRoute = createRoute({
	method: "post",
	path: "/",
	tags: ["Events"],
	request: {
		body: {
			required: true,
			content: {
				"application/json": {
					schema: createEventBodySchema,
				},
			},
		},
	},
	responses: {
		201: {
			description: "Created event.",
			content: {
				"application/json": {
					schema: eventResponseSchema,
				},
			},
		},
		400: {
			description: "Invalid event payload.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
					example: {
						message: "Event end time must be after the start time",
						code: "BAD_REQUEST",
					},
				},
			},
		},
		401: {
			description: "Unauthorized.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
				},
			},
		},
	},
});

export const joinEventByInviteCodeRoute = createRoute({
	method: "post",
	path: "/join",
	tags: ["Events"],
	request: {
		body: {
			required: true,
			content: {
				"application/json": {
					schema: joinEventByInviteCodeBodySchema,
				},
			},
		},
	},
	responses: {
		200: {
			description: "Joined event.",
			content: {
				"application/json": {
					schema: eventResponseSchema,
				},
			},
		},
		401: {
			description: "Unauthorized.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
				},
			},
		},
		404: {
			description: "Invite code not found.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
					example: {
						message: "Invite code not found",
						code: "NOT_FOUND",
					},
				},
			},
		},
		409: {
			description: "The event cannot be joined.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
					example: {
						message: "This event is at capacity",
						code: "CONFLICT",
					},
				},
			},
		},
	},
});
