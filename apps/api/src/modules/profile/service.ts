import type { Db } from "@/lib/db";
import { MAX_ASK_ME_ABOUT_TOPIC_LENGTH, MAX_ASK_ME_ABOUT_TOPICS } from "./constants";
import { getProfileRow, updateProfileRow } from "./repository";
import type { UpdateProfileInput } from "./types";

export async function getCurrentUserProfile(db: Db, userId: string) {
	const profile = await getProfileRow(db, userId);

	return profile ? toProfileResponse(profile) : null;
}

export async function updateCurrentUserProfile(db: Db, userId: string, input: UpdateProfileInput) {
	let normalizedAskMeAbout: string | undefined;

	if (input.askMeAbout !== undefined) {
		const topics: string[] = [];
		const seen = new Set<string>();

		for (const value of input.askMeAbout) {
			const topic = value.trim();

			if (!topic) {
				continue;
			}

			if (topic.length > MAX_ASK_ME_ABOUT_TOPIC_LENGTH) {
				throw new Error(`Each topic must be ${MAX_ASK_ME_ABOUT_TOPIC_LENGTH} characters or fewer.`);
			}

			const key = topic.toLocaleLowerCase();

			if (seen.has(key)) {
				continue;
			}

			seen.add(key);
			topics.push(topic);
		}

		if (topics.length > MAX_ASK_ME_ABOUT_TOPICS) {
			throw new Error(`Add up to ${MAX_ASK_ME_ABOUT_TOPICS} topics.`);
		}

		normalizedAskMeAbout = JSON.stringify(topics);
	}

	const normalizedInput = {
		...(input.name !== undefined ? { name: input.name.trim() } : {}),
		...(input.image !== undefined ? { image: normalizeNullableText(input.image) } : {}),
		...(input.headline !== undefined ? { headline: input.headline.trim() } : {}),
		...(normalizedAskMeAbout !== undefined ? { askMeAbout: normalizedAskMeAbout } : {}),
		...(input.isDiscoverable !== undefined ? { isDiscoverable: input.isDiscoverable } : {}),
	};

	await updateProfileRow(db, userId, normalizedInput);

	const profile = await getProfileRow(db, userId);

	return profile ? toProfileResponse(profile) : null;
}

function normalizeNullableText(value: string | null) {
	if (value === null) {
		return null;
	}

	const trimmed = value.trim();
	return trimmed.length > 0 ? trimmed : null;
}

function toProfileResponse(profile: NonNullable<Awaited<ReturnType<typeof getProfileRow>>>) {
	let parsedAskMeAbout: unknown = null;

	try {
		parsedAskMeAbout = JSON.parse(profile.askMeAbout);
	} catch {
		parsedAskMeAbout = null;
	}

	const askMeAbout: string[] = [];

	if (Array.isArray(parsedAskMeAbout)) {
		askMeAbout.push(...parsedAskMeAbout.filter((topic): topic is string => typeof topic === "string"));
	}

	return {
		...profile,
		askMeAbout,
	};
}
