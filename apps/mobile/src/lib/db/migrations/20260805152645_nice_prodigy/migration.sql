ALTER TABLE `local_event` RENAME COLUMN `server_id` TO `remote_id`;--> statement-breakpoint
DROP INDEX IF EXISTS `local_event_server_id_idx`;--> statement-breakpoint
CREATE UNIQUE INDEX `local_event_remote_id_idx` ON `local_event` (`remote_id`);