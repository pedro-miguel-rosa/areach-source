import { boolean, index, integer, pgTable, text, timestamp } from "drizzle-orm/pg-core";
import { user } from "@/lib/auth/schemas";

// Legacy study tables retained to preserve existing database contents and keep
// migration state represented. The API no longer exposes or writes these tables.
export const studyAccess = pgTable("study_access", {
	userId: text("user_id")
		.primaryKey()
		.references(() => user.id, { onDelete: "cascade" }),
	enabled: boolean("enabled").notNull().default(true),
	createdAt: timestamp("created_at").defaultNow().notNull(),
	updatedAt: timestamp("updated_at")
		.defaultNow()
		.$onUpdate(() => new Date())
		.notNull(),
});

export const evaluationSession = pgTable(
	"evaluation_sessions",
	{
		id: text("id").primaryKey(),
		userId: text("user_id").references(() => user.id, { onDelete: "set null" }),
		participantId: text("participant_id").notNull(),
		role: text("role"),
		assistantEnabled: boolean("assistant_enabled").notNull().default(false),
		consentAccepted: boolean("consent_accepted").notNull().default(false),
		consentAcceptedAt: timestamp("consent_accepted_at"),
		consentVersion: text("consent_version"),
		participantInfoVersion: text("participant_info_version"),
		startedAt: timestamp("started_at").notNull(),
		completedAt: timestamp("completed_at"),
		stoppedAt: timestamp("stopped_at"),
		appVersion: text("app_version"),
		deviceInfoJson: text("device_info_json"),
		linkedEventId: text("linked_event_id"),
		selectedParticipantId: text("selected_participant_id"),
		createdAt: timestamp("created_at").notNull(),
		updatedAt: timestamp("updated_at")
			.defaultNow()
			.$onUpdate(() => new Date())
			.notNull(),
	},
	(table) => [
		index("evaluation_sessions_user_id_idx").on(table.userId),
		index("evaluation_sessions_participant_id_idx").on(table.participantId),
		index("evaluation_sessions_started_at_idx").on(table.startedAt),
	],
);

// Legacy task storage retained for migration compatibility.
// The active study sync contract does not read or write this table.
export const evaluationTask = pgTable(
	"evaluation_tasks",
	{
		id: text("id").primaryKey(),
		sessionId: text("session_id")
			.notNull()
			.references(() => evaluationSession.id, { onDelete: "cascade" }),
		userId: text("user_id").references(() => user.id, { onDelete: "set null" }),
		taskId: text("task_id").notNull(),
		role: text("role").notNull(),
		title: text("title").notNull(),
		status: text("status").notNull(),
		startedAt: timestamp("started_at"),
		completedAt: timestamp("completed_at"),
		skippedAt: timestamp("skipped_at"),
		durationMs: integer("duration_ms"),
		completionSource: text("completion_source"),
		createdAt: timestamp("created_at").notNull(),
		updatedAt: timestamp("updated_at")
			.defaultNow()
			.$onUpdate(() => new Date())
			.notNull(),
	},
	(table) => [
		index("evaluation_tasks_session_id_idx").on(table.sessionId),
		index("evaluation_tasks_user_id_idx").on(table.userId),
		index("evaluation_tasks_task_id_idx").on(table.taskId),
		index("evaluation_tasks_status_idx").on(table.status),
	],
);

export const evaluationEvent = pgTable(
	"evaluation_events",
	{
		id: text("id").primaryKey(),
		sessionId: text("session_id")
			.notNull()
			.references(() => evaluationSession.id, { onDelete: "cascade" }),
		userId: text("user_id").references(() => user.id, { onDelete: "set null" }),
		taskId: text("task_id"),
		role: text("role"),
		type: text("type").notNull(),
		screen: text("screen"),
		target: text("target"),
		eventId: text("event_id"),
		participantTargetId: text("participant_target_id"),
		metadataJson: text("metadata_json"),
		createdAt: timestamp("created_at").notNull(),
	},
	(table) => [
		index("evaluation_events_session_id_idx").on(table.sessionId),
		index("evaluation_events_user_id_idx").on(table.userId),
		index("evaluation_events_task_id_idx").on(table.taskId),
		index("evaluation_events_type_idx").on(table.type),
		index("evaluation_events_created_at_idx").on(table.createdAt),
	],
);

// Legacy questionnaire storage retained for migration compatibility.
// The current questionnaire is administered externally.
export const evaluationAnswer = pgTable(
	"evaluation_answers",
	{
		id: text("id").primaryKey(),
		sessionId: text("session_id")
			.notNull()
			.references(() => evaluationSession.id, { onDelete: "cascade" }),
		userId: text("user_id").references(() => user.id, { onDelete: "set null" }),
		taskId: text("task_id"),
		questionId: text("question_id").notNull(),
		questionText: text("question_text").notNull(),
		answerType: text("answer_type").notNull(),
		answer: text("answer").notNull(),
		createdAt: timestamp("created_at").notNull(),
	},
	(table) => [
		index("evaluation_answers_session_id_idx").on(table.sessionId),
		index("evaluation_answers_user_id_idx").on(table.userId),
		index("evaluation_answers_task_id_idx").on(table.taskId),
		index("evaluation_answers_question_id_idx").on(table.questionId),
	],
);
