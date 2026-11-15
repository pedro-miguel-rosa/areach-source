export const ATTENDEE_REPORT_REASONS = [
	"inappropriate_profile_content",
	"harassment_or_abusive_behavior",
	"impersonation",
	"spam",
	"other",
] as const;

export type AttendeeReportReason = (typeof ATTENDEE_REPORT_REASONS)[number];

export type BlockedUser = {
	image: string | null;
	name: string;
	userId: string;
};

export type ReportResult = {
	created: boolean;
	id: string;
	status: "dismissed" | "pending" | "reviewed" | "resolved";
};
