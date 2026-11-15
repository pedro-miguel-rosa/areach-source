export type CreateEventInput = {
	title: string;
	description: string;
	venue: string;
	capacity?: number | null;
	startAt: string;
	endAt: string;
};

export type CreateEventRecordInput = {
	id: string;
	title: string;
	description: string;
	venue: string;
	inviteCode: string;
	capacity: number | null;
	startAt: Date;
	endAt: Date;
	createdById: string;
};
