import { errorHandler, notFoundHandler } from "@/lib/errors";
import { createOpenAPIApp, withOpenApiDoc } from "@/lib/openapi";
import { auth } from "@/modules/auth";
import { events } from "@/modules/events";
import { privacy } from "@/modules/privacy";
import { profile } from "@/modules/profile";

export function createApp() {
	const app = withOpenApiDoc(createOpenAPIApp());

	app.route("/auth", auth);
	app.route("/events", events);
	app.route("/profile", profile);
	app.route("/privacy", privacy);

	app.onError(errorHandler);
	app.notFound(notFoundHandler);

	return app;
}
