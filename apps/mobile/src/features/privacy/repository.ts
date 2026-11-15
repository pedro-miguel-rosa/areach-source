import { and, asc, eq, inArray } from "drizzle-orm";
import { localEventAttendee } from "@/features/events/schema";
import { db } from "@/lib/db/client";
import { localBlock } from "./schema";
import type { BlockedUser } from "./types";

export function getLocalBlockedUsersQuery(viewerId: string) {
	return db.select().from(localBlock).where(eq(localBlock.viewerId, viewerId)).orderBy(asc(localBlock.name), asc(localBlock.blockedUserId));
}

export async function getLocalBlockedUserIds(viewerId: string) {
	const rows = await db.select({ blockedUserId: localBlock.blockedUserId }).from(localBlock).where(eq(localBlock.viewerId, viewerId));

	return new Set(rows.map((row) => row.blockedUserId));
}

export async function replaceLocalBlocks(viewerId: string, blockedUsers: BlockedUser[]) {
	const now = new Date().toISOString();

	db.transaction((transaction) => {
		transaction.delete(localBlock).where(eq(localBlock.viewerId, viewerId)).run();

		if (blockedUsers.length > 0) {
			transaction
				.insert(localBlock)
				.values(
					blockedUsers.map((blockedUser) => ({
						viewerId,
						blockedUserId: blockedUser.userId,
						name: blockedUser.name,
						image: blockedUser.image,
						createdAt: now,
					})),
				)
				.run();
		}

		const blockedUserIds = blockedUsers.map((blockedUser) => blockedUser.userId);
		if (blockedUserIds.length > 0) {
			transaction
				.delete(localEventAttendee)
				.where(and(eq(localEventAttendee.viewerId, viewerId), inArray(localEventAttendee.userId, blockedUserIds)))
				.run();
		}
	});
}

export async function addLocalBlock(viewerId: string, blockedUser: BlockedUser) {
	await db
		.insert(localBlock)
		.values({
			viewerId,
			blockedUserId: blockedUser.userId,
			name: blockedUser.name,
			image: blockedUser.image,
			createdAt: new Date().toISOString(),
		})
		.onConflictDoUpdate({
			target: [localBlock.viewerId, localBlock.blockedUserId],
			set: {
				name: blockedUser.name,
				image: blockedUser.image,
			},
		});
}

export async function removeLocalBlock(viewerId: string, blockedUserId: string) {
	await db.delete(localBlock).where(and(eq(localBlock.viewerId, viewerId), eq(localBlock.blockedUserId, blockedUserId)));
}
