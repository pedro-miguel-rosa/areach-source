import { syncPrivacy } from "@/features/privacy/sync";
import { syncProfile } from "@/features/profile/sync";
import { showToast } from "@/lib/ui/toast";
import { createRemoteEvent, fetchRemoteEventAttendees, fetchRemoteEvents, joinRemoteEvent } from "./api";
import {
	listQueuedEventMutations,
	markEventMutationStatus,
	markLocalEventSyncStatus,
	reconcileCreatedEvent,
	removeEventMutation,
	replaceLocalEventAttendees,
	upsertRemoteEvent,
} from "./repository";
import type { CreateEventMutationPayload, JoinEventMutationPayload } from "./types";

const activeSyncs = new Map<string, Promise<void>>();

export function syncEvents(viewerId: string) {
	const previousSync = activeSyncs.get(viewerId) ?? Promise.resolve();
	const currentSync = previousSync.catch(() => undefined).then(() => runSync(viewerId));

	activeSyncs.set(viewerId, currentSync);

	return currentSync.finally(() => {
		if (activeSyncs.get(viewerId) === currentSync) {
			activeSyncs.delete(viewerId);
		}
	});
}

export async function waitForEventSyncs() {
	await Promise.all([...activeSyncs.values()].map((sync) => sync.catch(() => undefined)));
}

async function runSync(viewerId: string) {
	await syncProfile(viewerId).catch((error) => {
		const message = error instanceof Error && error.message ? error.message : "Some profile updates may take a little longer to appear.";

		showToast({ error, message, tone: "error", durationMs: 5000 });
	});
	await syncPrivacy(viewerId).catch((error) => {
		const message = error instanceof Error && error.message ? error.message : "Some privacy settings may take a little longer to appear.";

		showToast({ error, message, tone: "error", durationMs: 5000 });
	});
	await pushPendingEventMutations(viewerId);
	await pullRemoteEvents(viewerId);
}

export async function syncEventAttendees(viewerId: string, localEventId: string, remoteEventId: string) {
	const attendees = await fetchRemoteEventAttendees(remoteEventId);

	await replaceLocalEventAttendees(viewerId, localEventId, attendees);

	return attendees;
}

export async function pullRemoteEvents(viewerId: string) {
	const remoteEvents = await fetchRemoteEvents();

	for (const event of remoteEvents) {
		await upsertRemoteEvent(viewerId, event);
	}

	return remoteEvents;
}

export async function pushPendingEventMutations(viewerId: string) {
	const mutations = await listQueuedEventMutations(viewerId);

	for (const mutation of mutations) {
		await markEventMutationStatus(mutation.id, "processing");

		try {
			if (mutation.type === "create_event") {
				await pushCreateEventMutation(viewerId, mutation.id, mutation.localEventId, mutation.payload);
				continue;
			}

			if (mutation.type === "join_event" || mutation.type === "register_event") {
				await pushJoinEventMutation(viewerId, mutation.id, mutation.payload);
				continue;
			}

			showToast({
				message: "Some event updates may take a little longer to appear.",
				tone: "error",
			});
			await markEventMutationStatus(mutation.id, "failed", "Unknown event mutation type");
		} catch (error) {
			const message = error instanceof Error && error.message ? error.message : "Some event updates may take a little longer to appear.";

			showToast({
				error,
				message,
				tone: "error",
				durationMs: 5000,
			});

			if (mutation.localEventId) {
				await markLocalEventSyncStatus(mutation.localEventId, "failed");
			}

			await markEventMutationStatus(mutation.id, "failed", message);
		}
	}
}

async function pushCreateEventMutation(viewerId: string, mutationId: string, localEventId: string | null, payload: string) {
	if (!localEventId) {
		showToast({
			message: "Some event updates may take a little longer to appear.",
			tone: "error",
		});
		await markEventMutationStatus(mutationId, "failed", "Missing local event id");
		return;
	}

	const body = JSON.parse(payload) as CreateEventMutationPayload;
	const remoteEvent = await createRemoteEvent(body);

	await reconcileCreatedEvent(localEventId, viewerId, remoteEvent);
	await removeEventMutation(mutationId);
}

async function pushJoinEventMutation(viewerId: string, mutationId: string, payload: string) {
	const body = JSON.parse(payload) as JoinEventMutationPayload;
	const remoteEvent = await joinRemoteEvent(body);

	await upsertRemoteEvent(viewerId, remoteEvent);
	await removeEventMutation(mutationId);
}
