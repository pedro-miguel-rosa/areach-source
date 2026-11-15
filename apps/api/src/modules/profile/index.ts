import { HTTPException } from "hono/http-exception";
import { getDb } from "@/lib/db";
import { createOpenAPIApp } from "@/lib/openapi";
import { requireSession } from "@/modules/auth/session";
import { getProfileRoute, updateProfileRoute } from "./routes";
import { getCurrentUserProfile, updateCurrentUserProfile } from "./service";

export const profile = createOpenAPIApp();

profile.openapi(getProfileRoute, async (c) => {
	const session = await requireSession(c.env, c.req.raw.headers);
	const db = getDb(c.env);

	const userProfile = await getCurrentUserProfile(db, session.user.id);

	if (!userProfile) {
		throw new HTTPException(404, { message: "Profile not found" });
	}

	return c.json(userProfile, 200);
});

profile.openapi(updateProfileRoute, async (c) => {
	const session = await requireSession(c.env, c.req.raw.headers);
	const db = getDb(c.env);

	const userProfile = await updateCurrentUserProfile(db, session.user.id, c.req.valid("json"));

	if (!userProfile) {
		throw new HTTPException(404, { message: "Profile not found" });
	}

	return c.json(userProfile, 200);
});
