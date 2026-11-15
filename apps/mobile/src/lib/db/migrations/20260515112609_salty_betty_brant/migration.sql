CREATE TABLE `event_mutation` (
	`id` text PRIMARY KEY,
	`viewer_id` text NOT NULL,
	`type` text NOT NULL,
	`status` text DEFAULT 'pending' NOT NULL,
	`local_event_id` text,
	`payload` text NOT NULL,
	`error_message` text,
	`created_at` text NOT NULL,
	`last_attempt_at` text
);
--> statement-breakpoint
CREATE TABLE `local_event` (
	`id` text PRIMARY KEY,
	`server_id` text,
	`viewer_id` text NOT NULL,
	`title` text NOT NULL,
	`description` text DEFAULT '' NOT NULL,
	`venue` text NOT NULL,
	`host_label` text NOT NULL,
	`registration_count` integer DEFAULT 0 NOT NULL,
	`created_by_user` integer NOT NULL,
	`invite_code` text,
	`capacity` integer,
	`start_at` text NOT NULL,
	`end_at` text NOT NULL,
	`sync_status` text DEFAULT 'synced' NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `local_event_attendee` (
	`event_id` text NOT NULL,
	`viewer_id` text NOT NULL,
	`user_id` text NOT NULL,
	`name` text NOT NULL,
	`role` text NOT NULL,
	`is_current_user` integer DEFAULT false NOT NULL,
	`last_seen_at` text NOT NULL,
	`updated_at` text NOT NULL,
	CONSTRAINT `local_event_attendee_pk` PRIMARY KEY(`event_id`, `user_id`)
);
--> statement-breakpoint
CREATE INDEX `event_mutation_viewer_id_idx` ON `event_mutation` (`viewer_id`);--> statement-breakpoint
CREATE INDEX `event_mutation_status_idx` ON `event_mutation` (`status`);--> statement-breakpoint
CREATE INDEX `event_mutation_created_at_idx` ON `event_mutation` (`created_at`);--> statement-breakpoint
CREATE UNIQUE INDEX `local_event_server_id_idx` ON `local_event` (`server_id`);--> statement-breakpoint
CREATE INDEX `local_event_viewer_id_idx` ON `local_event` (`viewer_id`);--> statement-breakpoint
CREATE INDEX `local_event_start_at_idx` ON `local_event` (`start_at`);--> statement-breakpoint
CREATE INDEX `local_event_end_at_idx` ON `local_event` (`end_at`);--> statement-breakpoint
CREATE INDEX `local_event_attendee_event_id_idx` ON `local_event_attendee` (`event_id`);--> statement-breakpoint
CREATE INDEX `local_event_attendee_viewer_id_idx` ON `local_event_attendee` (`viewer_id`);--> statement-breakpoint
CREATE INDEX `local_event_attendee_user_id_idx` ON `local_event_attendee` (`user_id`);