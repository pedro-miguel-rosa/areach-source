import { expo } from "@better-auth/expo";
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { openAPI } from "better-auth/plugins";
import { getDb } from "../db";
import { sendChangeEmailConfirmationEmail, sendResetPasswordEmail, sendVerificationEmail } from "./email";
import * as authSchemas from "./schemas";

export function createAuth(env: CloudflareBindings) {
	const db = getDb(env);

	return betterAuth({
		database: drizzleAdapter(db, { provider: "pg", schema: authSchemas }),
		appName: "AReach API",
		basePath: "/auth",
		baseURL: env.BETTER_AUTH_URL,
		secret: env.BETTER_AUTH_SECRET,
		trustedOrigins: ["areach://"],
		emailAndPassword: {
			enabled: true,
			sendResetPassword: (data) => sendResetPasswordEmail(env.EMAIL, data),
		},
		emailVerification: {
			sendVerificationEmail: (data) => sendVerificationEmail(env.EMAIL, data),
		},
		user: {
			deleteUser: {
				enabled: true,
			},
			changeEmail: {
				enabled: true,
				sendChangeEmailConfirmation: (data) => sendChangeEmailConfirmationEmail(env.EMAIL, data),
			},
		},
		plugins: [openAPI(), expo()],
	});
}
