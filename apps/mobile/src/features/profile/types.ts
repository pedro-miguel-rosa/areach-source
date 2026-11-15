export type ProfileSyncStatus = "failed" | "pending_update" | "synced";

export type ProfileMutationStatus = "failed" | "pending" | "processing";

export type UserProfile = {
	userId: string;
	name: string;
	email: string;
	image: string | null;
	headline: string;
	isDiscoverable: boolean;
	askMeAbout: string[];
};

export type UpdateUserProfileInput = {
	name?: string;
	image?: string | null;
	headline?: string;
	askMeAbout?: string[];
	isDiscoverable?: boolean;
};

export type ProfileSeed = {
	email: string;
	image?: string | null;
	name: string;
};
