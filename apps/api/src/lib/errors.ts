import type { Context } from "hono";
import { HTTPException } from "hono/http-exception";
import type { ContentfulStatusCode } from "hono/utils/http-status";

export function errorHandler(error: Error, c: Context) {
	if (!(error instanceof HTTPException)) {
		console.error(error);

		return c.json({ message: "Internal server error", code: "INTERNAL_SERVER_ERROR" }, 500);
	}

	const status = error.status as ContentfulStatusCode;
	const headers = error.res ? new Headers(error.res.headers) : new Headers();

	if (status >= 500) {
		console.error(error);
	}

	let message = error.message || "Request failed";
	let code = "UNKNOWN_ERROR";

	switch (status) {
		case 400:
			code = "BAD_REQUEST";
			break;
		case 401:
			code = "UNAUTHORIZED";
			break;
		case 403:
			code = "FORBIDDEN";
			break;
		case 404:
			code = "NOT_FOUND";
			break;
		case 409:
			code = "CONFLICT";
			break;
		default:
			if (status >= 500) {
				message = "Internal server error";
				code = "INTERNAL_SERVER_ERROR";
			}
	}

	return c.json({ message, code }, { status, headers });
}

export function notFoundHandler(c: Context) {
	return c.json({ message: "Not found", code: "NOT_FOUND" }, 404);
}
