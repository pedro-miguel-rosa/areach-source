import { fetchUserProfile, updateUserProfile } from "./api";
import {
	listQueuedProfileMutations,
	markLocalProfileSyncStatus,
	markProfileMutationStatus,
	reconcileRemoteProfile,
	removeProfileMutation,
	upsertRemoteProfile,
} from "./repository";
import type { UpdateUserProfileInput } from "./types";

const activeSyncs = new Map<string, Promise<void>>();

export async function syncProfile(viewerId: string) {
	const previousSync = activeSyncs.get(viewerId) ?? Promise.resolve();
	const currentSync = previousSync
		.catch(() => undefined)
		.then(async () => {
			await pushPendingProfileMutations(viewerId);
			await pullRemoteProfile(viewerId);
		});

	activeSyncs.set(viewerId, currentSync);

	return currentSync.finally(() => {
		if (activeSyncs.get(viewerId) === currentSync) {
			activeSyncs.delete(viewerId);
		}
	});
}

export async function waitForProfileSyncs() {
	await Promise.all([...activeSyncs.values()].map((sync) => sync.catch(() => undefined)));
}

export async function pullRemoteProfile(viewerId: string) {
	const profile = await fetchUserProfile();

	await upsertRemoteProfile(viewerId, profile);

	return profile;
}

export async function pushPendingProfileMutations(viewerId: string) {
	const mutations = await listQueuedProfileMutations(viewerId);

	for (const mutation of mutations) {
		await markProfileMutationStatus(mutation.id, "processing");

		try {
			const body = JSON.parse(mutation.payload) as UpdateUserProfileInput;
			const profile = await updateUserProfile(body);

			await removeProfileMutation(mutation.id);
			await reconcileRemoteProfile(viewerId, profile);
		} catch (error) {
			const message = error instanceof Error && error.message ? error.message : "Some profile updates may take longer to sync.";

			await markLocalProfileSyncStatus(viewerId, "failed");
			await markProfileMutationStatus(mutation.id, "failed", message);
		}
	}
}
