import { index, integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

type EvaluationSyncStatus = "pending" | "synced" | "failed";
type EvaluationRole = "host" | "joiner";
type EvaluationTaskStatus = "not_started" | "active" | "completed" | "skipped";
type EvaluationCompletionSource = "automatic" | "manual" | "questionnaire";
type EvaluationAnswerType = "likert_1_5" | "text" | "boolean" | "single_choice";

// Retained only to represent legacy local tables and clear them during account
// deletion. The mobile app no longer creates, reads, or synchronises these rows.
export const evaluationSettings = sqliteTable("evaluation_settings", {
	id: text("id").primaryKey(),
	hasSeenEvaluationWelcome: integer("has_seen_evaluation_welcome", { mode: "boolean" }).notNull().default(false),
	evaluationAssistantEnabled: integer("evaluation_assistant_enabled", { mode: "boolean" }).notNull().default(false),
	hasAcceptedEvaluationConsent: integer("has_accepted_evaluation_consent", { mode: "boolean" }).notNull().default(false),
	consentAcceptedAt: text("consent_accepted_at"),
	consentVersion: text("consent_version"),
	participantInfoVersion: text("participant_info_version"),
	participantId: text("participant_id"),
	evaluationRole: text("evaluation_role", { enum: ["host", "joiner"] }).$type<EvaluationRole>(),
	currentEvaluationSessionId: text("current_evaluation_session_id"),
	currentEvaluationTaskId: text("current_evaluation_task_id"),
	evaluationCompleted: integer("evaluation_completed", { mode: "boolean" }).notNull().default(false),
});

export type EvaluationSettingsRecord = typeof evaluationSettings.$inferSelect;

export const evaluationSession = sqliteTable(
	"evaluation_sessions",
	{
		id: text("id").primaryKey(),
		userId: text("user_id"),
		participantId: text("participant_id").notNull(),
		role: text("role", { enum: ["host", "joiner"] }).$type<EvaluationRole>(),
		assistantEnabled: integer("assistant_enabled", { mode: "boolean" }).notNull().default(false),
		consentAccepted: integer("consent_accepted", { mode: "boolean" }).notNull().default(false),
		consentAcceptedAt: text("consent_accepted_at"),
		consentVersion: text("consent_version"),
		participantInfoVersion: text("participant_info_version"),
		startedAt: text("started_at").notNull(),
		completedAt: text("completed_at"),
		stoppedAt: text("stopped_at"),
		appVersion: text("app_version"),
		deviceInfoJson: text("device_info_json"),
		linkedEventId: text("linked_event_id"),
		selectedParticipantId: text("selected_participant_id"),
		syncStatus: text("sync_status", { enum: ["pending", "synced", "failed"] })
			.$type<EvaluationSyncStatus>()
			.notNull()
			.default("pending"),
		syncedAt: text("synced_at"),
		createdAt: text("created_at").notNull(),
		updatedAt: text("updated_at").notNull(),
	},
	(table) => [
		index("evaluation_sessions_user_id_idx").on(table.userId),
		index("evaluation_sessions_participant_id_idx").on(table.participantId),
		index("evaluation_sessions_sync_status_idx").on(table.syncStatus),
	],
);

export type EvaluationSessionRecord = typeof evaluationSession.$inferSelect;

// Legacy task storage retained so existing local databases can migrate safely.
// The active study flow does not create, read, or synchronise these rows.
export const evaluationTask = sqliteTable(
	"evaluation_tasks",
	{
		id: text("id").primaryKey(),
		sessionId: text("session_id").notNull(),
		taskId: text("task_id").notNull(),
		role: text("role", { enum: ["host", "joiner"] })
			.$type<EvaluationRole>()
			.notNull(),
		title: text("title").notNull(),
		status: text("status", { enum: ["not_started", "active", "completed", "skipped"] })
			.$type<EvaluationTaskStatus>()
			.notNull()
			.default("not_started"),
		startedAt: text("started_at"),
		completedAt: text("completed_at"),
		skippedAt: text("skipped_at"),
		durationMs: integer("duration_ms"),
		completionSource: text("completion_source", { enum: ["automatic", "manual", "questionnaire"] }).$type<EvaluationCompletionSource>(),
		syncStatus: text("sync_status", { enum: ["pending", "synced", "failed"] })
			.$type<EvaluationSyncStatus>()
			.notNull()
			.default("pending"),
		createdAt: text("created_at").notNull(),
		updatedAt: text("updated_at").notNull(),
	},
	(table) => [
		index("evaluation_tasks_session_id_idx").on(table.sessionId),
		index("evaluation_tasks_task_id_idx").on(table.taskId),
		index("evaluation_tasks_status_idx").on(table.status),
		index("evaluation_tasks_sync_status_idx").on(table.syncStatus),
	],
);

export type EvaluationTaskRecord = typeof evaluationTask.$inferSelect;

export const evaluationEvent = sqliteTable(
	"evaluation_events",
	{
		id: text("id").primaryKey(),
		sessionId: text("session_id").notNull(),
		taskId: text("task_id"),
		role: text("role", { enum: ["host", "joiner"] }).$type<EvaluationRole>(),
		type: text("type").notNull(),
		screen: text("screen"),
		target: text("target"),
		eventId: text("event_id"),
		participantTargetId: text("participant_target_id"),
		metadataJson: text("metadata_json"),
		createdAt: text("created_at").notNull(),
		syncStatus: text("sync_status", { enum: ["pending", "synced", "failed"] })
			.$type<EvaluationSyncStatus>()
			.notNull()
			.default("pending"),
		syncedAt: text("synced_at"),
	},
	(table) => [
		index("evaluation_events_session_id_idx").on(table.sessionId),
		index("evaluation_events_task_id_idx").on(table.taskId),
		index("evaluation_events_type_idx").on(table.type),
		index("evaluation_events_sync_status_idx").on(table.syncStatus),
	],
);

export type EvaluationEventRecord = typeof evaluationEvent.$inferSelect;

// Legacy questionnaire storage retained for local cleanup and migration
// compatibility. The current questionnaire is administered externally.
export const evaluationAnswer = sqliteTable(
	"evaluation_answers",
	{
		id: text("id").primaryKey(),
		sessionId: text("session_id").notNull(),
		taskId: text("task_id"),
		questionId: text("question_id").notNull(),
		questionText: text("question_text").notNull(),
		answerType: text("answer_type", {
			enum: ["likert_1_5", "text", "boolean", "single_choice"],
		})
			.$type<EvaluationAnswerType>()
			.notNull(),
		answer: text("answer").notNull(),
		createdAt: text("created_at").notNull(),
		syncStatus: text("sync_status", { enum: ["pending", "synced", "failed"] })
			.$type<EvaluationSyncStatus>()
			.notNull()
			.default("pending"),
		syncedAt: text("synced_at"),
	},
	(table) => [
		index("evaluation_answers_session_id_idx").on(table.sessionId),
		index("evaluation_answers_task_id_idx").on(table.taskId),
		index("evaluation_answers_question_id_idx").on(table.questionId),
		index("evaluation_answers_sync_status_idx").on(table.syncStatus),
	],
);

export type EvaluationAnswerRecord = typeof evaluationAnswer.$inferSelect;
