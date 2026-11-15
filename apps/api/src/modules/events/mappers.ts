export type EventRow = {
	id: string;
	title: string;
	description: string;
	venue: string;
	inviteCode: string;
	capacity: number | null;
	startAt: Date;
	endAt: Date;
	createdById: string;
	hostName: string;
	hostVisible: boolean;
	registrationCount: number;
};

export function toEventResponse(row: EventRow, currentUserId: string) {
	const createdByUser = row.createdById === currentUserId;

	return {
		id: row.id,
		title: row.title,
		description: row.description,
		venue: row.venue,
		inviteCode: createdByUser ? row.inviteCode : null,
		capacity: row.capacity,
		registrationCount: row.registrationCount,
		createdByUser,
		hostLabel: createdByUser ? "Hosted by you" : row.hostVisible ? `Hosted by ${row.hostName}` : "Hosted event",
		startAt: row.startAt.toISOString(),
		endAt: row.endAt.toISOString(),
	};
}

export type EventAttendeeRow = {
	askMeAbout: string;
	headline: string;
	image: string | null;
	isHost: boolean;
	lastSeenAt: Date;
	name: string;
	userId: string;
};

export function toEventAttendeeResponse(row: EventAttendeeRow, currentUserId: string) {
	let parsedAskMeAbout: unknown = null;

	try {
		parsedAskMeAbout = JSON.parse(row.askMeAbout);
	} catch {
		parsedAskMeAbout = null;
	}

	const askMeAbout: string[] = [];

	if (Array.isArray(parsedAskMeAbout)) {
		askMeAbout.push(...parsedAskMeAbout.filter((topic): topic is string => typeof topic === "string"));
	}

	return {
		userId: row.userId,
		name: row.name,
		image: row.image,
		headline: row.headline,
		askMeAbout,
		role: row.isHost ? ("host" as const) : ("attendee" as const),
		isCurrentUser: row.userId === currentUserId,
		lastSeenAt: row.lastSeenAt.toISOString(),
	};
}

export type EventRegistrationRow = {
	isAttending: boolean;
	isHost: boolean;
	name: string;
	userId: string;
};

export function toEventRegistrationResponse(row: EventRegistrationRow, currentUserId: string) {
	return {
		userId: row.userId,
		name: row.name,
		role: row.isHost ? ("host" as const) : ("registrant" as const),
		isCurrentUser: row.userId === currentUserId,
		isAttending: row.isAttending,
	};
}
