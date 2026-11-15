export const ATTENDEE_REPORT_REASONS = [
	"inappropriate_profile_content",
	"harassment_or_abusive_behavior",
	"impersonation",
	"spam",
	"other",
] as const;

export type AttendeeReportReason = (typeof ATTENDEE_REPORT_REASONS)[number];

export const REPORT_STATUSES = ["pending", "reviewed", "resolved", "dismissed"] as const;

export type ReportStatus = (typeof REPORT_STATUSES)[number];
