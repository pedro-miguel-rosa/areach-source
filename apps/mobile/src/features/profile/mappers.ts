import type { LocalProfileRow } from "./schema";
import type { UserProfile } from "./types";

export function toUserProfile(row: LocalProfileRow): UserProfile {
	let askMeAbout: string[] = [];

	try {
		const parsed: unknown = JSON.parse(row.askMeAbout);

		if (Array.isArray(parsed)) {
			askMeAbout = parsed.filter((topic): topic is string => typeof topic === "string");
		}
	} catch {
		// Keep malformed persisted values empty.
	}

	return {
		userId: row.id,
		name: row.name,
		email: row.email,
		image: row.image,
		headline: row.headline,
		isDiscoverable: row.isDiscoverable,
		askMeAbout,
	};
}

export function serializeAskMeAbout(topics: string[]) {
	return JSON.stringify(topics);
}
