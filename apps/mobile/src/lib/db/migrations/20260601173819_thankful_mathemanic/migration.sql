CREATE TABLE `evaluation_answers` (
	`id` text PRIMARY KEY,
	`session_id` text NOT NULL,
	`task_id` text,
	`question_id` text NOT NULL,
	`question_text` text NOT NULL,
	`answer_type` text NOT NULL,
	`answer` text NOT NULL,
	`created_at` text NOT NULL,
	`sync_status` text DEFAULT 'pending' NOT NULL,
	`synced_at` text
);
--> statement-breakpoint
CREATE TABLE `evaluation_events` (
	`id` text PRIMARY KEY,
	`session_id` text NOT NULL,
	`task_id` text,
	`role` text,
	`type` text NOT NULL,
	`screen` text,
	`target` text,
	`event_id` text,
	`participant_target_id` text,
	`metadata_json` text,
	`created_at` text NOT NULL,
	`sync_status` text DEFAULT 'pending' NOT NULL,
	`synced_at` text
);
--> statement-breakpoint
CREATE TABLE `evaluation_sessions` (
	`id` text PRIMARY KEY,
	`user_id` text,
	`participant_id` text NOT NULL,
	`role` text,
	`assistant_enabled` integer DEFAULT false NOT NULL,
	`consent_accepted` integer DEFAULT false NOT NULL,
	`consent_accepted_at` text,
	`consent_version` text,
	`participant_info_version` text,
	`started_at` text NOT NULL,
	`completed_at` text,
	`stopped_at` text,
	`app_version` text,
	`device_info_json` text,
	`linked_event_id` text,
	`selected_participant_id` text,
	`sync_status` text DEFAULT 'pending' NOT NULL,
	`synced_at` text,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `evaluation_settings` (
	`id` text PRIMARY KEY,
	`has_seen_evaluation_welcome` integer DEFAULT false NOT NULL,
	`evaluation_assistant_enabled` integer DEFAULT false NOT NULL,
	`has_accepted_evaluation_consent` integer DEFAULT false NOT NULL,
	`consent_accepted_at` text,
	`consent_version` text,
	`participant_info_version` text,
	`participant_id` text,
	`evaluation_role` text,
	`current_evaluation_session_id` text,
	`current_evaluation_task_id` text,
	`evaluation_completed` integer DEFAULT false NOT NULL
);
--> statement-breakpoint
CREATE TABLE `evaluation_tasks` (
	`id` text PRIMARY KEY,
	`session_id` text NOT NULL,
	`task_id` text NOT NULL,
	`role` text NOT NULL,
	`title` text NOT NULL,
	`status` text DEFAULT 'not_started' NOT NULL,
	`started_at` text,
	`completed_at` text,
	`skipped_at` text,
	`duration_ms` integer,
	`completion_source` text,
	`sync_status` text DEFAULT 'pending' NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `evaluation_answers_session_id_idx` ON `evaluation_answers` (`session_id`);--> statement-breakpoint
CREATE INDEX `evaluation_answers_task_id_idx` ON `evaluation_answers` (`task_id`);--> statement-breakpoint
CREATE INDEX `evaluation_answers_question_id_idx` ON `evaluation_answers` (`question_id`);--> statement-breakpoint
CREATE INDEX `evaluation_answers_sync_status_idx` ON `evaluation_answers` (`sync_status`);--> statement-breakpoint
CREATE INDEX `evaluation_events_session_id_idx` ON `evaluation_events` (`session_id`);--> statement-breakpoint
CREATE INDEX `evaluation_events_task_id_idx` ON `evaluation_events` (`task_id`);--> statement-breakpoint
CREATE INDEX `evaluation_events_type_idx` ON `evaluation_events` (`type`);--> statement-breakpoint
CREATE INDEX `evaluation_events_sync_status_idx` ON `evaluation_events` (`sync_status`);--> statement-breakpoint
CREATE INDEX `evaluation_sessions_user_id_idx` ON `evaluation_sessions` (`user_id`);--> statement-breakpoint
CREATE INDEX `evaluation_sessions_participant_id_idx` ON `evaluation_sessions` (`participant_id`);--> statement-breakpoint
CREATE INDEX `evaluation_sessions_sync_status_idx` ON `evaluation_sessions` (`sync_status`);--> statement-breakpoint
CREATE INDEX `evaluation_tasks_session_id_idx` ON `evaluation_tasks` (`session_id`);--> statement-breakpoint
CREATE INDEX `evaluation_tasks_task_id_idx` ON `evaluation_tasks` (`task_id`);--> statement-breakpoint
CREATE INDEX `evaluation_tasks_status_idx` ON `evaluation_tasks` (`status`);--> statement-breakpoint
CREATE INDEX `evaluation_tasks_sync_status_idx` ON `evaluation_tasks` (`sync_status`);