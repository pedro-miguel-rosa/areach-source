import { apiClient } from "@/lib/api/client";
import type { UpdateUserProfileInput, UserProfile } from "./types";

export async function fetchUserProfile() {
	const { data, error } = await apiClient.GET("/profile");

	if (error || !data) {
		throw new Error(error?.message ?? "Profile request failed");
	}

	return data as UserProfile;
}

export async function updateUserProfile(input: UpdateUserProfileInput) {
	const { data, error } = await apiClient.PATCH("/profile", {
		body: input,
	});

	if (error || !data) {
		throw new Error(error?.message ?? "Profile request failed");
	}

	return data as UserProfile;
}
