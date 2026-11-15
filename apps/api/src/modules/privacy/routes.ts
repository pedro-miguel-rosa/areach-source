import { createRoute, z } from "@hono/zod-openapi";
import { ATTENDEE_REPORT_REASONS, REPORT_STATUSES } from "./constants";

const errorResponseSchema = z.object({
	message: z.string().openapi({ example: "Unauthorized" }),
	code: z.string().openapi({ example: "UNAUTHORIZED" }),
});

const blockedUserResponseSchema = z.object({
	userId: z.string().openapi({ example: "user_01" }),
	name: z.string().openapi({ example: "Pedro Silva" }),
	image: z.string().nullable().openapi({ example: "https://example.invalid/avatar.png" }),
});

export const attendeeReportReasonSchema = z.enum(ATTENDEE_REPORT_REASONS);
export const reportStatusSchema = z.enum(REPORT_STATUSES);

export const listBlockedUsersRoute = createRoute({
	method: "get",
	path: "/blocks",
	tags: ["Privacy"],
	responses: {
		200: {
			description: "Users blocked by the authenticated user.",
			content: {
				"application/json": {
					schema: z.array(blockedUserResponseSchema),
				},
			},
		},
		401: {
			description: "Unauthorized.",
			content: { "application/json": { schema: errorResponseSchema } },
		},
	},
});

export const getBlockStateRoute = createRoute({
	method: "get",
	path: "/blocks/{userId}",
	tags: ["Privacy"],
	request: {
		params: z.object({ userId: z.string().trim().min(1).max(200) }),
	},
	responses: {
		200: {
			description: "Block state for a target user.",
			content: { "application/json": { schema: z.object({ blocked: z.boolean() }) } },
		},
		400: {
			description: "Invalid target.",
			content: { "application/json": { schema: errorResponseSchema } },
		},
		401: {
			description: "Unauthorized.",
			content: { "application/json": { schema: errorResponseSchema } },
		},
	},
});

export const unblockUserRoute = createRoute({
	method: "delete",
	path: "/blocks/{userId}",
	tags: ["Privacy"],
	request: {
		params: z.object({ userId: z.string().trim().min(1).max(200) }),
	},
	responses: {
		200: {
			description: "User unblocked.",
			content: { "application/json": { schema: z.object({ blocked: z.literal(false) }) } },
		},
		400: {
			description: "Invalid target.",
			content: { "application/json": { schema: errorResponseSchema } },
		},
		401: {
			description: "Unauthorized.",
			content: { "application/json": { schema: errorResponseSchema } },
		},
	},
});
