CREATE TABLE `local_block` (
	`viewer_id` text NOT NULL,
	`blocked_user_id` text NOT NULL,
	`name` text NOT NULL,
	`image` text,
	`created_at` text NOT NULL,
	CONSTRAINT `local_block_pk` PRIMARY KEY(`viewer_id`, `blocked_user_id`)
);
--> statement-breakpoint
ALTER TABLE `local_profile` ADD `is_discoverable` integer DEFAULT true NOT NULL;--> statement-breakpoint
CREATE INDEX `local_block_viewer_id_idx` ON `local_block` (`viewer_id`);--> statement-breakpoint
CREATE INDEX `local_block_blocked_user_id_idx` ON `local_block` (`blocked_user_id`);