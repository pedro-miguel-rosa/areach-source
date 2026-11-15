export type EventStatus = "live" | "past" | "upcoming";

export type EventSyncStatus = "failed" | "pending_create" | "synced";

export type EventMutationStatus = "failed" | "pending" | "processing";

export type EventMutationType = "create_event" | "join_event" | "register_event";

export type EventAttendeeRole = "attendee" | "host";

export type EventAttendee = {
	askMeAbout: string[];
	distance?: number;
	headline: string;
	image: string | null;
	isCurrentUser: boolean;
	lastSeenAt: string;
	name: string;
	role: EventAttendeeRole;
	userId: string;
};

export type Event = {
	capacity: number | null;
	createdByUser: boolean;
	description: string;
	endAt: Date;
	hostLabel: string;
	id: string;
	inviteCode: string | null;
	registrationCount: number;
	remoteId: string | null;
	startAt: Date;
	syncStatus: EventSyncStatus;
	title: string;
	venue: string;
};

export type RemoteEvent = {
	capacity: number | null;
	createdByUser: boolean;
	description: string;
	endAt: string;
	hostLabel: string;
	id: string;
	inviteCode: string | null;
	registrationCount: number;
	startAt: string;
	title: string;
	venue: string;
};

export type RemoteEventAttendee = EventAttendee;

export type LiveEventAttendance = {
	eventId: string;
	lastSeenAt: string;
	nearbyCredential: string;
	nearbyCredentialExpiresAt: string;
	nearbyEventScope: string;
	nearbyTransportKey: string;
	userId: string;
};

export type NearbyIdentity = {
	peerId: string;
	publicKey: string;
};

export type ResolvedNearbyIdentity = NearbyIdentity & {
	attendee: RemoteEventAttendee;
	credential: string;
};

export type CreateLocalEventInput = {
	capacity: number | null;
	description: string;
	endAt: string;
	startAt: string;
	title: string;
	venue: string;
	viewerId: string;
};

export type JoinEventInput = {
	inviteCode: string;
	viewerId: string;
};

export type CreateEventMutationPayload = {
	capacity: number | null;
	description: string;
	endAt: string;
	startAt: string;
	title: string;
	venue: string;
};

export type JoinEventMutationPayload = {
	inviteCode: string;
};
