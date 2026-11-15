CREATE TABLE "attendee_report" (
	"id" text PRIMARY KEY,
	"reporter_user_id" text NOT NULL,
	"reported_user_id" text NOT NULL,
	"event_id" text NOT NULL,
	"reason" text NOT NULL,
	"status" text DEFAULT 'pending' NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "user_block" (
	"blocker_user_id" text,
	"blocked_user_id" text,
	"created_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "user_block_pkey" PRIMARY KEY("blocker_user_id","blocked_user_id"),
	CONSTRAINT "user_block_distinct_users_check" CHECK ("blocker_user_id" <> "blocked_user_id")
);
--> statement-breakpoint
ALTER TABLE "profile" ADD COLUMN "is_discoverable" boolean DEFAULT true NOT NULL;--> statement-breakpoint
CREATE UNIQUE INDEX "attendee_report_reporter_target_event_idx" ON "attendee_report" ("reporter_user_id","reported_user_id","event_id");--> statement-breakpoint
CREATE INDEX "attendee_report_reported_user_id_idx" ON "attendee_report" ("reported_user_id");--> statement-breakpoint
CREATE INDEX "attendee_report_event_id_idx" ON "attendee_report" ("event_id");--> statement-breakpoint
CREATE INDEX "attendee_report_status_idx" ON "attendee_report" ("status");--> statement-breakpoint
CREATE INDEX "user_block_blocker_user_id_idx" ON "user_block" ("blocker_user_id");--> statement-breakpoint
CREATE INDEX "user_block_blocked_user_id_idx" ON "user_block" ("blocked_user_id");--> statement-breakpoint
ALTER TABLE "attendee_report" ADD CONSTRAINT "attendee_report_reporter_user_id_user_id_fkey" FOREIGN KEY ("reporter_user_id") REFERENCES "user"("id") ON DELETE CASCADE;--> statement-breakpoint
ALTER TABLE "attendee_report" ADD CONSTRAINT "attendee_report_reported_user_id_user_id_fkey" FOREIGN KEY ("reported_user_id") REFERENCES "user"("id") ON DELETE CASCADE;--> statement-breakpoint
ALTER TABLE "attendee_report" ADD CONSTRAINT "attendee_report_event_id_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "event"("id") ON DELETE CASCADE;--> statement-breakpoint
ALTER TABLE "user_block" ADD CONSTRAINT "user_block_blocker_user_id_user_id_fkey" FOREIGN KEY ("blocker_user_id") REFERENCES "user"("id") ON DELETE CASCADE;--> statement-breakpoint
ALTER TABLE "user_block" ADD CONSTRAINT "user_block_blocked_user_id_user_id_fkey" FOREIGN KEY ("blocked_user_id") REFERENCES "user"("id") ON DELETE CASCADE;