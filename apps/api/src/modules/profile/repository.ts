import { eq, sql } from "drizzle-orm";
import { user } from "@/lib/auth/schemas";
import type { Db } from "@/lib/db";
import { profileTable } from "./schemas";
import type { UpdateProfileRecord } from "./types";

const profileFields = {
	userId: user.id,
	name: user.name,
	email: user.email,
	image: user.image,
	headline: sql<string>`coalesce(${profileTable.headline}, '')`,
	askMeAbout: sql<string>`coalesce(${profileTable.askMeAbout}, '[]')`,
	isDiscoverable: sql<boolean>`coalesce(${profileTable.isDiscoverable}, true)`,
};

export async function getProfileRow(db: Db, userId: string) {
	const rows = await db
		.select(profileFields)
		.from(user)
		.leftJoin(profileTable, eq(profileTable.userId, user.id))
		.where(eq(user.id, userId))
		.limit(1);

	return rows[0] ?? null;
}

export async function updateProfileRow(db: Db, userId: string, input: UpdateProfileRecord) {
	const now = new Date();
	const userInput = {
		...(input.name !== undefined ? { name: input.name } : {}),
		...(input.image !== undefined ? { image: input.image } : {}),
	};
	const profileInput = {
		...(input.headline !== undefined ? { headline: input.headline } : {}),
		...(input.askMeAbout !== undefined ? { askMeAbout: input.askMeAbout } : {}),
		...(input.isDiscoverable !== undefined ? { isDiscoverable: input.isDiscoverable } : {}),
	};

	await db.transaction(async (tx) => {
		if (Object.keys(userInput).length > 0) {
			await tx
				.update(user)
				.set({
					...userInput,
					updatedAt: now,
				})
				.where(eq(user.id, userId));
		}

		if (Object.keys(profileInput).length > 0) {
			await tx
				.insert(profileTable)
				.values({
					userId,
					...profileInput,
					updatedAt: now,
				})
				.onConflictDoUpdate({
					target: profileTable.userId,
					set: {
						...profileInput,
						updatedAt: now,
					},
				});
		}
	});
}
