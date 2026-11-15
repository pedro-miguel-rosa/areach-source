ALTER TABLE "profile" ADD COLUMN "ask_me_about" text DEFAULT '[]' NOT NULL;--> statement-breakpoint
ALTER TABLE "profile" DROP COLUMN "bio";--> statement-breakpoint
ALTER TABLE "profile" DROP COLUMN "links";--> statement-breakpoint
