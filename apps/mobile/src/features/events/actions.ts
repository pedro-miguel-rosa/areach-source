import { showToast } from "@/lib/ui/toast";
import { createLocalEvent, queueJoinEvent } from "./repository";
import { syncEvents } from "./sync";
import type { CreateLocalEventInput, JoinEventInput } from "./types";

export async function createEvent(input: CreateLocalEventInput) {
	const localEventId = await createLocalEvent(input);

	void syncEvents(input.viewerId).catch((error) => {
		const message =
			error instanceof Error && error.message
				? error.message
				: "Your event was saved, but some details may take a little longer to appear.";

		showToast({ error, message, tone: "error", durationMs: 5000 });
	});

	return localEventId;
}

export async function joinEvent(input: JoinEventInput) {
	await queueJoinEvent(input);

	showToast({ message: "Invite received. Your event will appear soon.", tone: "info" });

	void syncEvents(input.viewerId).catch((error) => {
		const message = error instanceof Error && error.message ? error.message : "Some event updates may take a little longer to appear.";

		showToast({ error, message, tone: "error", durationMs: 5000 });
	});

	return true;
}
