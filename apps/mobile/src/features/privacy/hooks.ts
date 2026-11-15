import { useLiveQuery } from "drizzle-orm/expo-sqlite";
import { useMemo } from "react";
import { getLocalBlockedUsersQuery } from "./repository";
import type { BlockedUser } from "./types";

export function useBlockedUsers(viewerId: string) {
	const query = useMemo(() => getLocalBlockedUsersQuery(viewerId), [viewerId]);
	const queryState = useLiveQuery(query, [viewerId]);

	return {
		data: queryState.data.map(
			(row): BlockedUser => ({
				image: row.image,
				name: row.name,
				userId: row.blockedUserId,
			}),
		),
		error: queryState.error,
		isPending: !queryState.updatedAt && !queryState.error,
	};
}
