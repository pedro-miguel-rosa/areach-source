ALTER TABLE `local_profile` ADD `ask_me_about` text DEFAULT '[]' NOT NULL;--> statement-breakpoint
ALTER TABLE `local_event_attendee` ADD `ask_me_about` text DEFAULT '[]' NOT NULL;--> statement-breakpoint
ALTER TABLE `local_profile` DROP COLUMN `bio`;--> statement-breakpoint
ALTER TABLE `local_profile` DROP COLUMN `links`;--> statement-breakpoint
ALTER TABLE `local_event_attendee` DROP COLUMN `bio`;--> statement-breakpoint
ALTER TABLE `local_event_attendee` DROP COLUMN `links`;
