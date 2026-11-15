import { OpenAPIHono } from "@hono/zod-openapi";
import { createAuth } from "@/lib/auth";
import { mergeDocuments } from "./document";
import { validationErrorHook } from "./validation";

const OPEN_API_CONFIG = {
	openapi: "3.0.4",
	info: { title: "AReach API", version: "1.0.0" },
	servers: [{ url: "http://127.0.0.1:8787", description: "Local development" }],
};

export function createOpenAPIApp() {
	return new OpenAPIHono<{ Bindings: CloudflareBindings }>({
		defaultHook: validationErrorHook,
	});
}

export type App = ReturnType<typeof createOpenAPIApp>;

export function withOpenApiDoc(app: App) {
	app.get("/openapi.json", async (c) => {
		const apiDoc = app.getOpenAPIDocument(OPEN_API_CONFIG);
		const authDoc = await createAuth(c.env).api.generateOpenAPISchema();

		return c.json(mergeDocuments(apiDoc, authDoc));
	});

	return app;
}
