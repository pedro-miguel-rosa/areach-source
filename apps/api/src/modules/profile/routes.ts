import { createRoute, z } from "@hono/zod-openapi";
import { MAX_ASK_ME_ABOUT_TOPIC_LENGTH, MAX_ASK_ME_ABOUT_TOPICS } from "./constants";

const errorResponseSchema = z.object({
	message: z.string().openapi({ example: "Unauthorized" }),
	code: z.string().openapi({ example: "UNAUTHORIZED" }),
});

export const profileResponseSchema = z.object({
	userId: z.string().openapi({ example: "user_01" }),
	name: z.string().openapi({ example: "Pedro Silva" }),
	email: z.email().openapi({ example: "participant@example.invalid" }),
	image: z.string().nullable().openapi({ example: "https://example.invalid/avatar.png" }),
	headline: z.string().openapi({ example: "Founder and product builder" }),
	askMeAbout: z.array(z.string()).openapi({ example: ["Web Development", "Startups", "Coffee & Great Spots"] }),
	isDiscoverable: z.boolean().openapi({ example: true }),
});

export const updateProfileBodySchema = z.object({
	name: z.string().trim().min(1).max(120).optional(),
	image: z.string().trim().max(2000).nullable().optional(),
	headline: z.string().trim().max(160).optional(),
	askMeAbout: z
		.array(z.string().trim().max(MAX_ASK_ME_ABOUT_TOPIC_LENGTH))
		.max(MAX_ASK_ME_ABOUT_TOPICS)
		.optional()
		.openapi({ example: ["Web Development", "Startups"] }),
	isDiscoverable: z.boolean().optional(),
});

export const getProfileRoute = createRoute({
	method: "get",
	path: "/",
	tags: ["Profile"],
	responses: {
		200: {
			description: "Current user profile.",
			content: {
				"application/json": {
					schema: profileResponseSchema,
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

export const updateProfileRoute = createRoute({
	method: "patch",
	path: "/",
	tags: ["Profile"],
	request: {
		body: {
			required: true,
			content: {
				"application/json": {
					schema: updateProfileBodySchema,
				},
			},
		},
	},
	responses: {
		200: {
			description: "Updated current user profile.",
			content: {
				"application/json": {
					schema: profileResponseSchema,
				},
			},
		},
		400: {
			description: "Invalid profile payload.",
			content: {
				"application/json": {
					schema: errorResponseSchema,
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
