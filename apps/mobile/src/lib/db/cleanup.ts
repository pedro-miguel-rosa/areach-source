import { eventMutation, localEvent, localEventAttendee } from "@/features/events/schema";
import { localBlock } from "@/features/privacy/schema";
import { localProfile, profileMutation } from "@/features/profile/schema";
import { evaluationAnswer, evaluationEvent, evaluationSession, evaluationSettings, evaluationTask } from "@/lib/db/legacy-study-schema";
import { db } from "./client";

/** Clears all account-scoped data retained in the device database. */
export async function clearLocalAccountData() {
	db.transaction((transaction) => {
		transaction.delete(eventMutation).run();
		transaction.delete(localEventAttendee).run();
		transaction.delete(localEvent).run();
		transaction.delete(localBlock).run();
		transaction.delete(profileMutation).run();
		transaction.delete(localProfile).run();
		transaction.delete(evaluationAnswer).run();
		transaction.delete(evaluationEvent).run();
		transaction.delete(evaluationTask).run();
		transaction.delete(evaluationSession).run();
		transaction.delete(evaluationSettings).run();
	});
}
