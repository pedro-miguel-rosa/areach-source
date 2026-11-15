import createClient, { type Middleware } from "openapi-fetch";
import { authClient } from "@/lib/auth/client";
import type { paths } from "./generated/schema";

const apiUrl = process.env.EXPO_PUBLIC_API_URL;

if (!apiUrl) {
	throw new Error("Missing environment variable: EXPO_PUBLIC_API_URL");
}

const authMiddleware: Middleware = {
	async onRequest({ request }) {
		const cookie = authClient.getCookie();

		if (cookie) {
			request.headers.set("cookie", cookie);
		}

		return request;
	},
};

export const apiClient = createClient<paths>({ baseUrl: apiUrl });

apiClient.use(authMiddleware);
