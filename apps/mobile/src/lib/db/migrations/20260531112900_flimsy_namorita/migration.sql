CREATE TABLE `local_profile` (
	`id` text PRIMARY KEY,
	`name` text NOT NULL,
	`email` text NOT NULL,
	`image` text,
	`headline` text DEFAULT '' NOT NULL,
	`bio` text DEFAULT '' NOT NULL,
	`links` text DEFAULT '[]' NOT NULL,
	`sync_status` text DEFAULT 'synced' NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `profile_mutation` (
	`id` text PRIMARY KEY,
	`viewer_id` text NOT NULL,
	`status` text DEFAULT 'pending' NOT NULL,
	`payload` text NOT NULL,
	`error_message` text,
	`created_at` text NOT NULL,
	`last_attempt_at` text
);
--> statement-breakpoint
ALTER TABLE `local_event_attendee` ADD `image` text;--> statement-breakpoint
ALTER TABLE `local_event_attendee` ADD `headline` text DEFAULT '' NOT NULL;--> statement-breakpoint
ALTER TABLE `local_event_attendee` ADD `bio` text DEFAULT '' NOT NULL;--> statement-breakpoint
ALTER TABLE `local_event_attendee` ADD `links` text DEFAULT '[]' NOT NULL;--> statement-breakpoint
CREATE INDEX `local_profile_sync_status_idx` ON `local_profile` (`sync_status`);--> statement-breakpoint
CREATE INDEX `profile_mutation_viewer_id_idx` ON `profile_mutation` (`viewer_id`);--> statement-breakpoint
CREATE INDEX `profile_mutation_status_idx` ON `profile_mutation` (`status`);--> statement-breakpoint
CREATE INDEX `profile_mutation_created_at_idx` ON `profile_mutation` (`created_at`);