import { HTTPException } from "hono/http-exception";
import { createAuth } from "@/lib/auth";

export async function requireSession(env: CloudflareBindings, headers: Headers) {
	const auth = createAuth(env);

	const session = await auth.api.getSession({ headers });

	if (!session) {
		console.log("Unauthorized");
		throw new HTTPException(401, { message: "Unauthorized" });
	}

	return session;
}
