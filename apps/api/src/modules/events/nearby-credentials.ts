import type { Db } from "@/lib/db";
import { getEventAttendanceNearbyIdentity, saveEventAttendanceNearbyIdentity } from "./repository";

const CREDENTIAL_VERSION = "v2";

type NearbyCredentialPayload = {
	eventId: string;
	expiresAt: string;
	peerId: string;
	publicKey: string;
	userId: string;
};

export async function issueNearbyCredential(
	secret: string,
	eventId: string,
	userId: string,
	peerId: string,
	publicKey: string,
	eventEndsAt: Date,
) {
	const expiresAt = eventEndsAt.toISOString();
	const payload: NearbyCredentialPayload = { eventId, expiresAt, peerId, publicKey, userId };
	const initializationVector = crypto.getRandomValues(new Uint8Array(12));
	const key = await nearbyCredentialKey(secret);
	const encryptedPayload = await crypto.subtle.encrypt(
		{ name: "AES-GCM", iv: initializationVector },
		key,
		new TextEncoder().encode(JSON.stringify(payload)),
	);

	return {
		nearbyCredential: `${CREDENTIAL_VERSION}.${encodeBase64Url(initializationVector)}.${encodeBase64Url(new Uint8Array(encryptedPayload))}`,
		nearbyCredentialExpiresAt: expiresAt,
		nearbyEventScope: await nearbyEventScope(secret, eventId),
		nearbyTransportKey: await nearbyTransportKey(secret, eventId),
	};
}

export async function getOrIssueNearbyCredential(
	db: Db,
	secret: string,
	eventId: string,
	userId: string,
	peerId: string,
	publicKey: string,
	eventEndsAt: Date,
) {
	const existing = await getEventAttendanceNearbyIdentity(db, eventId, userId);
	const existingExpiresAt = existing?.nearbyCredentialExpiresAt;

	if (
		existing?.nearbyPeerId === peerId &&
		existing.nearbyPublicKey === publicKey &&
		existing.nearbyCredential &&
		existingExpiresAt &&
		existingExpiresAt.getTime() > Date.now()
	) {
		return {
			nearbyCredential: existing.nearbyCredential,
			nearbyCredentialExpiresAt: existingExpiresAt.toISOString(),
			nearbyEventScope: await nearbyEventScope(secret, eventId),
			nearbyTransportKey: await nearbyTransportKey(secret, eventId),
		};
	}

	const issued = await issueNearbyCredential(secret, eventId, userId, peerId, publicKey, eventEndsAt);

	await saveEventAttendanceNearbyIdentity(db, eventId, userId, {
		nearbyCredential: issued.nearbyCredential,
		nearbyCredentialExpiresAt: eventEndsAt,
		nearbyPeerId: peerId,
		nearbyPublicKey: publicKey,
	});

	return issued;
}

export async function readNearbyCredential(secret: string, credential: string) {
	try {
		const [version, encodedInitializationVector, encodedPayload] = credential.split(".");

		if (version !== CREDENTIAL_VERSION || !encodedInitializationVector || !encodedPayload) {
			return null;
		}

		const key = await nearbyCredentialKey(secret);
		const decryptedPayload = await crypto.subtle.decrypt(
			{ name: "AES-GCM", iv: decodeBase64Url(encodedInitializationVector) },
			key,
			decodeBase64Url(encodedPayload),
		);
		const payload: unknown = JSON.parse(new TextDecoder().decode(decryptedPayload));

		if (!isNearbyCredentialPayload(payload)) {
			return null;
		}

		const expiresAt = new Date(payload.expiresAt).getTime();

		if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
			return null;
		}

		return payload;
	} catch {
		return null;
	}
}

async function nearbyCredentialKey(secret: string) {
	const keyMaterial = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`areach-nearby-credential:${secret}`));

	return crypto.subtle.importKey("raw", keyMaterial, "AES-GCM", false, ["encrypt", "decrypt"]);
}

async function nearbyEventScope(secret: string, eventId: string) {
	const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`areach-nearby-scope:${secret}:${eventId}`));

	return encodeBase64Url(new Uint8Array(digest).slice(0, 18));
}

async function nearbyTransportKey(secret: string, eventId: string) {
	const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { hash: "SHA-256", name: "HMAC" }, false, ["sign"]);
	const transportKey = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`areach-nearby-transport:${eventId}`));

	return encodeBase64Url(new Uint8Array(transportKey));
}

function isNearbyCredentialPayload(value: unknown): value is NearbyCredentialPayload {
	if (!value || typeof value !== "object") {
		return false;
	}

	const payload = value as Record<string, unknown>;

	return (
		typeof payload.eventId === "string" &&
		payload.eventId.length > 0 &&
		typeof payload.expiresAt === "string" &&
		typeof payload.peerId === "string" &&
		payload.peerId.length > 0 &&
		typeof payload.publicKey === "string" &&
		payload.publicKey.length > 0 &&
		typeof payload.userId === "string" &&
		payload.userId.length > 0
	);
}

function encodeBase64Url(value: Uint8Array) {
	let binary = "";

	for (const byte of value) {
		binary += String.fromCharCode(byte);
	}

	return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function decodeBase64Url(value: string) {
	const base64 = value
		.replaceAll("-", "+")
		.replaceAll("_", "/")
		.padEnd(Math.ceil(value.length / 4) * 4, "=");
	const binary = atob(base64);

	return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}
