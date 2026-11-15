import { showToast } from "@/lib/ui/toast";
import { saveLocalProfileUpdate } from "./repository";
import { syncProfile } from "./sync";
import type { ProfileSeed, UpdateUserProfileInput } from "./types";

type SaveProfileInput = {
	input: UpdateUserProfileInput;
	seed: ProfileSeed;
	viewerId: string;
};

export async function saveProfile(input: SaveProfileInput) {
	const nextProfile = await saveLocalProfileUpdate(input);

	showToast({ message: "Profile saved.", tone: "success" });

	void syncProfile(input.viewerId).catch((error) => {
		const message = error instanceof Error && error.message ? error.message : "Some profile updates may take longer to sync.";

		showToast({ error, message, tone: "error", durationMs: 5000 });
	});

	return nextProfile;
}
