import { and, asc, eq, inArray } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { MAX_ASK_ME_ABOUT_TOPIC_LENGTH, MAX_ASK_ME_ABOUT_TOPICS } from "./constants";
import { serializeAskMeAbout, toUserProfile } from "./mappers";
import { localProfile, profileMutation } from "./schema";
import type { ProfileMutationStatus, ProfileSeed, ProfileSyncStatus, UpdateUserProfileInput, UserProfile } from "./types";

type SaveLocalProfileInput = {
	input: UpdateUserProfileInput;
	seed: ProfileSeed;
	viewerId: string;
};

export function getLocalProfileQuery(viewerId: string) {
	return db.select().from(localProfile).where(eq(localProfile.id, viewerId)).limit(1);
}

export async function seedLocalProfile(viewerId: string, seed: ProfileSeed) {
	const existingRows = await db.select({ id: localProfile.id }).from(localProfile).where(eq(localProfile.id, viewerId)).limit(1);

	if (existingRows[0]) {
		return;
	}

	const now = new Date().toISOString();

	await db.insert(localProfile).values({
		id: viewerId,
		name: seed.name,
		email: seed.email,
		image: seed.image ?? null,
		headline: "",
		askMeAbout: "[]",
		isDiscoverable: true,
		syncStatus: "synced",
		createdAt: now,
		updatedAt: now,
	});
}

export async function saveLocalProfileUpdate({ input, seed, viewerId }: SaveLocalProfileInput) {
	const existingRows = await db.select().from(localProfile).where(eq(localProfile.id, viewerId)).limit(1);
	const existingProfile = existingRows[0] ? toUserProfile(existingRows[0]) : undefined;
	const values = input.askMeAbout ?? existingProfile?.askMeAbout ?? [];
	const askMeAbout: string[] = [];
	const seen = new Set<string>();

	for (const value of values) {
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
		askMeAbout.push(topic);
	}

	if (askMeAbout.length > MAX_ASK_ME_ABOUT_TOPICS) {
		throw new Error(`Add up to ${MAX_ASK_ME_ABOUT_TOPICS} topics.`);
	}

	const nextProfile: UserProfile = {
		userId: viewerId,
		name: normalizeName(input.name ?? existingProfile?.name ?? seed.name),
		email: existingProfile?.email ?? seed.email,
		image: input.image !== undefined ? input.image : (existingProfile?.image ?? seed.image ?? null),
		headline: normalizeText(input.headline ?? existingProfile?.headline ?? ""),
		isDiscoverable: input.isDiscoverable ?? existingProfile?.isDiscoverable ?? true,
		askMeAbout,
	};
	const now = new Date().toISOString();

	if (existingRows[0]) {
		await db
			.update(localProfile)
			.set({
				name: nextProfile.name,
				email: nextProfile.email,
				image: nextProfile.image,
				headline: nextProfile.headline,
				isDiscoverable: nextProfile.isDiscoverable,
				askMeAbout: serializeAskMeAbout(nextProfile.askMeAbout),
				syncStatus: "pending_update",
				updatedAt: now,
			})
			.where(eq(localProfile.id, viewerId));
	} else {
		await db.insert(localProfile).values({
			id: viewerId,
			name: nextProfile.name,
			email: nextProfile.email,
			image: nextProfile.image,
			headline: nextProfile.headline,
			isDiscoverable: nextProfile.isDiscoverable,
			askMeAbout: serializeAskMeAbout(nextProfile.askMeAbout),
			syncStatus: "pending_update",
			createdAt: now,
			updatedAt: now,
		});
	}

	await replaceQueuedProfileMutation(viewerId, nextProfile);

	return nextProfile;
}

export async function upsertRemoteProfile(viewerId: string, profile: UserProfile) {
	const hasPendingUpdate = await hasQueuedProfileMutation(viewerId);
	const existingRows = await db.select({ id: localProfile.id }).from(localProfile).where(eq(localProfile.id, viewerId)).limit(1);

	if (hasPendingUpdate && existingRows[0]) {
		return;
	}

	await writeRemoteProfile(viewerId, profile, "synced");
}

export async function reconcileRemoteProfile(viewerId: string, profile: UserProfile) {
	await writeRemoteProfile(viewerId, profile, "synced");
}

export async function listQueuedProfileMutations(viewerId: string) {
	return db
		.select()
		.from(profileMutation)
		.where(and(eq(profileMutation.viewerId, viewerId), inArray(profileMutation.status, ["pending", "failed"])))
		.orderBy(asc(profileMutation.createdAt));
}

export async function markProfileMutationStatus(mutationId: string, status: ProfileMutationStatus, errorMessage: string | null = null) {
	await db
		.update(profileMutation)
		.set({
			status,
			errorMessage,
			lastAttemptAt: new Date().toISOString(),
		})
		.where(eq(profileMutation.id, mutationId));
}

export async function markLocalProfileSyncStatus(viewerId: string, syncStatus: ProfileSyncStatus) {
	await db
		.update(localProfile)
		.set({
			syncStatus,
			updatedAt: new Date().toISOString(),
		})
		.where(eq(localProfile.id, viewerId));
}

export async function removeProfileMutation(mutationId: string) {
	await db.delete(profileMutation).where(eq(profileMutation.id, mutationId));
}

async function writeRemoteProfile(viewerId: string, profile: UserProfile, syncStatus: ProfileSyncStatus) {
	const existingRows = await db.select({ id: localProfile.id }).from(localProfile).where(eq(localProfile.id, viewerId)).limit(1);
	const now = new Date().toISOString();
	const values = {
		name: profile.name,
		email: profile.email,
		image: profile.image,
		headline: profile.headline,
		isDiscoverable: profile.isDiscoverable,
		askMeAbout: serializeAskMeAbout(profile.askMeAbout),
		syncStatus,
		updatedAt: now,
	};

	if (existingRows[0]) {
		await db.update(localProfile).set(values).where(eq(localProfile.id, viewerId));
		return;
	}

	await db.insert(localProfile).values({
		id: viewerId,
		...values,
		createdAt: now,
	});
}

async function replaceQueuedProfileMutation(viewerId: string, profile: UserProfile) {
	await db
		.delete(profileMutation)
		.where(and(eq(profileMutation.viewerId, viewerId), inArray(profileMutation.status, ["pending", "failed", "processing"])));

	await db.insert(profileMutation).values({
		id: createId("profile-mutation"),
		viewerId,
		status: "pending",
		payload: JSON.stringify({
			name: profile.name,
			image: profile.image,
			headline: profile.headline,
			isDiscoverable: profile.isDiscoverable,
			askMeAbout: profile.askMeAbout,
		} satisfies UpdateUserProfileInput),
		errorMessage: null,
		createdAt: new Date().toISOString(),
		lastAttemptAt: null,
	});
}

async function hasQueuedProfileMutation(viewerId: string) {
	const rows = await db
		.select({ id: profileMutation.id })
		.from(profileMutation)
		.where(and(eq(profileMutation.viewerId, viewerId), inArray(profileMutation.status, ["pending", "failed", "processing"])))
		.limit(1);

	return rows.length > 0;
}

function normalizeName(value: string) {
	const trimmed = value.trim();

	if (!trimmed) {
		throw new Error("Name is required.");
	}

	return trimmed;
}

function normalizeText(value: string) {
	return value.trim();
}

function createId(prefix: string) {
	const timestamp = Date.now().toString(36);
	const random = Math.random().toString(36).slice(2, 10);

	return `${prefix}:${timestamp}:${random}`;
}
