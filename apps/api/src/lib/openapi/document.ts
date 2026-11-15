import type { createAuth } from "@/lib/auth";
import type { App } from "@/lib/openapi";

const AUTH_TAG_NAME = "Auth";
const AUTH_TAG_DESCRIPTION = "Authentication endpoints.";
const AUTH_BASE_PATH = "/auth";
const AUTH_SOURCE_TAGS = new Set(["Default", "Expo"]);
const AUTH_OPERATION_IDS: Record<string, string> = {
	"POST /sign-in/social": "socialSignIn",
	"GET /callback/{id}": "callbackOAuth",
	"POST /callback/{id}": "callbackOAuthPost",
	"GET /get-session": "getSession",
	"POST /get-session": "refreshSession",
	"POST /sign-out": "signOut",
	"POST /sign-up/email": "signUpEmail",
	"POST /sign-in/email": "signInEmail",
	"POST /reset-password": "resetPassword",
	"POST /verify-password": "verifyPassword",
	"GET /verify-email": "verifyEmail",
	"POST /send-verification-email": "sendVerificationEmail",
	"POST /change-email": "changeEmail",
	"POST /change-password": "changePassword",
	"POST /update-session": "updateSession",
	"POST /update-user": "updateUser",
	"POST /delete-user": "deleteUser",
	"POST /request-password-reset": "requestPasswordReset",
	"GET /reset-password/{token}": "resetPasswordCallback",
	"GET /list-sessions": "listUserSessions",
	"POST /revoke-session": "revokeSession",
	"POST /revoke-sessions": "revokeSessions",
	"POST /revoke-other-sessions": "revokeOtherSessions",
	"POST /link-social": "linkSocialAccount",
	"GET /list-accounts": "listUserAccounts",
	"GET /delete-user/callback": "deleteUserCallback",
	"POST /unlink-account": "unlinkAccount",
	"POST /refresh-token": "refreshToken",
	"POST /get-access-token": "getAccessToken",
	"GET /account-info": "accountInfo",
	"GET /ok": "ok",
	"GET /error": "error",
	"GET /expo-authorization-proxy": "expoAuthorizationProxy",
};

const AUTH_REQUEST_EXAMPLES = [
	[
		"/sign-in/email",
		{
			email: "support@example.invalid",
			password: "supersecure123",
			rememberMe: true,
			callbackURL: "areach://",
		},
	],
	[
		"/sign-up/email",
		{
			name: "Pedro Silva",
			email: "support@example.invalid",
			password: "supersecure123",
			image: "https://example.invalid/avatar.png",
			callbackURL: "areach://",
		},
	],
] as const;

type OpenApiDocument = ReturnType<App["getOpenAPIDocument"]>;
type AuthOpenApiDocument = Awaited<ReturnType<ReturnType<typeof createAuth>["api"]["generateOpenAPISchema"]>>;

type OpenApiComponents = {
	schemas?: unknown;
	securitySchemes?: unknown;
	[key: string]: unknown;
};

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null;
}

function toRecord(value: unknown) {
	return isRecord(value) ? value : {};
}

function mergeRecords(base: unknown, extra: unknown) {
	return { ...toRecord(base), ...toRecord(extra) };
}

function normalizeAuthTag(tag: string) {
	return AUTH_SOURCE_TAGS.has(tag) ? AUTH_TAG_NAME : tag;
}

function getAuthOperationId(method: string, path: string) {
	return AUTH_OPERATION_IDS[`${method.toUpperCase()} ${path}`];
}

function prefixAndNormalizeAuthPaths(paths: unknown) {
	return Object.fromEntries(
		Object.entries(toRecord(paths)).map(([path, operations]) => [
			`${AUTH_BASE_PATH}${path}`,
			Object.fromEntries(
				Object.entries(toRecord(operations)).map(([method, operation]) => {
					if (!isRecord(operation)) {
						return [method, operation];
					}

					return [
						method,
						{
							...operation,
							...(Array.isArray(operation.tags)
								? { tags: operation.tags.map((tag) => (typeof tag === "string" ? normalizeAuthTag(tag) : tag)) }
								: {}),
							...(getAuthOperationId(method, path) ? { operationId: getAuthOperationId(method, path) } : {}),
						},
					];
				}),
			),
		]),
	);
}

function setJsonRequestExample<T>(document: T, path: string, example: Record<string, unknown>): T {
	if (!isRecord(document)) return document;

	const paths = toRecord(document.paths);
	const pathItem = toRecord(paths[path]);
	const operation = toRecord(pathItem.post);

	if (!paths[path] || !pathItem.post) return document;

	const requestBody = toRecord(operation.requestBody);
	const content = toRecord(requestBody.content);
	const jsonContent = toRecord(content["application/json"]);

	content["application/json"] = { ...jsonContent, example };

	pathItem.post = {
		...operation,
		requestBody: { ...requestBody, content },
	};

	paths[path] = pathItem;

	return { ...document, paths } as T;
}

function getAuthDocumentTags(tags: unknown) {
	const rawTags = Array.isArray(tags) ? tags : [];

	return [
		...rawTags.filter((tag) => !isRecord(tag) || !AUTH_SOURCE_TAGS.has(String(tag.name))),
		{ name: AUTH_TAG_NAME, description: AUTH_TAG_DESCRIPTION },
	];
}

function customizeAuthDocument<T>(document: T): T {
	if (!isRecord(document)) return document;

	// Better Auth generates its own OpenAPI document; we patch it here
	// so it fits the rest of our API surface and docs.
	const withExamples = AUTH_REQUEST_EXAMPLES.reduce(
		(currentDocument, [path, example]) => setJsonRequestExample(currentDocument, path, example),
		document,
	);

	return {
		...withExamples,
		tags: getAuthDocumentTags(withExamples.tags),
		paths: prefixAndNormalizeAuthPaths(withExamples.paths),
	} as T;
}

export function mergeDocuments(apiDoc: OpenApiDocument, authDoc: AuthOpenApiDocument) {
	const customizedAuthDoc = customizeAuthDocument(authDoc);
	const apiComponents = toRecord(apiDoc.components) as OpenApiComponents;
	const authComponents = toRecord(customizedAuthDoc.components) as OpenApiComponents;

	return {
		...apiDoc,
		paths: mergeRecords(apiDoc.paths, customizedAuthDoc.paths),
		components: {
			...apiComponents,
			...authComponents,
			schemas: mergeRecords(apiComponents.schemas, authComponents.schemas),
			securitySchemes: mergeRecords(apiComponents.securitySchemes, authComponents.securitySchemes),
		},
		tags: [...(apiDoc.tags ?? []), ...(customizedAuthDoc.tags ?? [])],
	};
}
