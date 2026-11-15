import { expoClient } from "@better-auth/expo/client";
import type { BetterAuthClientPlugin } from "better-auth/client";
import { createAuthClient } from "better-auth/react";
import * as SecureStore from "expo-secure-store";

type BetterAuthClientActions = NonNullable<BetterAuthClientPlugin["getActions"]>;

// @better-auth/expo@1.6.25 still types this action factory with two arguments,
// while better-auth's core client expects the newer optional third argument.
// The runtime factory ignores that argument, so adapt the type at this boundary
// and keep the getCookie action available to the rest of the app.
type ExpoAuthClientPlugin = Omit<BetterAuthClientPlugin, "getActions"> & {
	getActions: (
		$fetch: Parameters<BetterAuthClientActions>[0],
		$store: Parameters<BetterAuthClientActions>[1],
		options: Parameters<BetterAuthClientActions>[2],
	) => { getCookie: () => string };
};

const apiUrl = process.env.EXPO_PUBLIC_API_URL;

if (!apiUrl) {
	throw new Error("Missing environment variable: EXPO_PUBLIC_API_URL");
}

const expoClientPlugin = expoClient({
	scheme: "areach",
	storagePrefix: "areach",
	storage: SecureStore,
});

const expoAuthClientPlugin = {
	...expoClientPlugin,
	getActions: expoClientPlugin.getActions as unknown as ExpoAuthClientPlugin["getActions"],
};

export const authClient = createAuthClient({
	baseURL: apiUrl,
	basePath: "/auth",
	plugins: [expoAuthClientPlugin],
});

export function getStoredAuthUserId() {
	const session = authClient.$store.atoms.session?.get() as { data?: { user?: { id?: unknown } } } | undefined;
	const userId = session?.data?.user?.id;

	return typeof userId === "string" && userId.length > 0 ? userId : null;
}

/**
 * Account deletion is not sign-out, so the Expo plugin does not clear its
 * cached session automatically. Clear both the cache and any chunked values
 * before the auth guard can render another protected screen.
 */
export async function clearStoredAuthSession() {
	const storageKeys = ["areach_cookie", "areach_session_data"];
	const chunkKeys = storageKeys.flatMap((key) => Array.from({ length: 64 }, (_, index) => `${key}.${index}`));

	await Promise.all([...storageKeys, ...chunkKeys].map((key) => SecureStore.deleteItemAsync(key).catch(() => undefined)));

	const sessionAtom = authClient.$store.atoms.session;
	sessionAtom?.set({
		...sessionAtom.get(),
		data: null,
		error: null,
		isPending: false,
		isRefetching: false,
	});
}
