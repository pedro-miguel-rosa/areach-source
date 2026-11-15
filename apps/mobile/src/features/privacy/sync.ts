import { fetchRemoteBlockedUsers } from "./api";
import { replaceLocalBlocks } from "./repository";

export async function syncPrivacy(viewerId: string) {
	const blockedUsers = await fetchRemoteBlockedUsers();

	await replaceLocalBlocks(viewerId, blockedUsers);

	return blockedUsers;
}
