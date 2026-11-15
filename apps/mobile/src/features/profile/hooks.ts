import { useLiveQuery } from "drizzle-orm/expo-sqlite";
import { useCallback, useEffect, useMemo, useState } from "react";
import { showToast } from "@/lib/ui/toast";
import { saveProfile } from "./actions";
import { toUserProfile } from "./mappers";
import { getLocalProfileQuery, seedLocalProfile } from "./repository";
import { syncProfile } from "./sync";
import type { ProfileSeed, UpdateUserProfileInput } from "./types";

export function useProfile(viewerId: string, seed: ProfileSeed | undefined) {
	const profileQuery = useMemo(() => getLocalProfileQuery(viewerId), [viewerId]);
	const queryState = useLiveQuery(profileQuery, [viewerId]);
	const [isSubmitting, setIsSubmitting] = useState(false);
	const row = queryState.data[0];
	const profile = useMemo(() => (row ? toUserProfile(row) : undefined), [row]);

	useEffect(() => {
		if (!viewerId || !seed) {
			return;
		}

		void seedLocalProfile(viewerId, seed).catch((error) => {
			const message = error instanceof Error && error.message ? error.message : "Unable to prepare your local profile.";

			showToast({ error, message, tone: "error", durationMs: 5000 });
		});
	}, [seed, viewerId]);

	useEffect(() => {
		if (!viewerId) {
			return;
		}

		void syncProfile(viewerId).catch((error) => {
			const message = error instanceof Error && error.message ? error.message : "Some profile updates may take longer to sync.";

			showToast({ error, message, tone: "error", durationMs: 5000 });
		});
	}, [viewerId]);

	const submitProfile = useCallback(
		async (input: UpdateUserProfileInput) => {
			if (!viewerId || !seed) {
				showToast({ message: "Your profile is not ready yet.", tone: "error", durationMs: 5000 });
				return undefined;
			}

			setIsSubmitting(true);

			try {
				return await saveProfile({ viewerId, seed, input });
			} catch (submitError) {
				const message = submitError instanceof Error && submitError.message ? submitError.message : "Unable to save your profile.";

				showToast({
					error: submitError,
					message,
					tone: "error",
					durationMs: 5000,
				});
				return undefined;
			} finally {
				setIsSubmitting(false);
			}
		},
		[seed, viewerId],
	);

	return {
		error: queryState.error,
		isPending: !queryState.updatedAt && !queryState.error,
		isSubmitting,
		profile,
		submitProfile,
	};
}
