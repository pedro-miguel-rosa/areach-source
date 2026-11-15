import { getDb } from "@/lib/db";
import { createOpenAPIApp } from "@/lib/openapi";
import { requireSession } from "@/modules/auth/session";
import { getBlockStateRoute, listBlockedUsersRoute, unblockUserRoute } from "./routes";
import { getBlockStateForUser, listBlockedUsersForUser, unblockUserForUser } from "./service";

export const privacy = createOpenAPIApp();

privacy.openapi(listBlockedUsersRoute, async (c) => {
	const session = await requireSession(c.env, c.req.raw.headers);
	const db = getDb(c.env);

	const blockedUsers = await listBlockedUsersForUser(db, session.user.id);

	return c.json(
		blockedUsers.map(({ userId, name, image }) => ({ userId, name, image })),
		200,
	);
});

privacy.openapi(getBlockStateRoute, async (c) => {
	const session = await requireSession(c.env, c.req.raw.headers);
	const db = getDb(c.env);
	const { userId } = c.req.valid("param");

	return c.json(await getBlockStateForUser(db, session.user.id, userId), 200);
});

privacy.openapi(unblockUserRoute, async (c) => {
	const session = await requireSession(c.env, c.req.raw.headers);
	const db = getDb(c.env);
	const { userId } = c.req.valid("param");

	return c.json(await unblockUserForUser(db, session.user.id, userId), 200);
});
