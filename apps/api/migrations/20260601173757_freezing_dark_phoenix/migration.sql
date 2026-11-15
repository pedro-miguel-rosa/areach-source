CREATE TABLE "evaluation_answers" (
	"id" text PRIMARY KEY,
	"session_id" text NOT NULL,
	"user_id" text,
	"task_id" text,
	"question_id" text NOT NULL,
	"question_text" text NOT NULL,
	"answer_type" text NOT NULL,
	"answer" text NOT NULL,
	"created_at" timestamp NOT NULL
);
--> statement-breakpoint
CREATE TABLE "evaluation_events" (
	"id" text PRIMARY KEY,
	"session_id" text NOT NULL,
	"user_id" text,
	"task_id" text,
	"role" text,
	"type" text NOT NULL,
	"screen" text,
	"target" text,
	"event_id" text,
	"participant_target_id" text,
	"metadata_json" text,
	"created_at" timestamp NOT NULL
);
--> statement-breakpoint
CREATE TABLE "evaluation_sessions" (
	"id" text PRIMARY KEY,
	"user_id" text,
	"participant_id" text NOT NULL,
	"role" text,
	"assistant_enabled" boolean DEFAULT false NOT NULL,
	"consent_accepted" boolean DEFAULT false NOT NULL,
	"consent_accepted_at" timestamp,
	"consent_version" text,
	"participant_info_version" text,
	"started_at" timestamp NOT NULL,
	"completed_at" timestamp,
	"stopped_at" timestamp,
	"app_version" text,
	"device_info_json" text,
	"linked_event_id" text,
	"selected_participant_id" text,
	"created_at" timestamp NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "evaluation_tasks" (
	"id" text PRIMARY KEY,
	"session_id" text NOT NULL,
	"user_id" text,
	"task_id" text NOT NULL,
	"role" text NOT NULL,
	"title" text NOT NULL,
	"status" text NOT NULL,
	"started_at" timestamp,
	"completed_at" timestamp,
	"skipped_at" timestamp,
	"duration_ms" integer,
	"completion_source" text,
	"created_at" timestamp NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE INDEX "evaluation_answers_session_id_idx" ON "evaluation_answers" ("session_id");--> statement-breakpoint
CREATE INDEX "evaluation_answers_user_id_idx" ON "evaluation_answers" ("user_id");--> statement-breakpoint
CREATE INDEX "evaluation_answers_task_id_idx" ON "evaluation_answers" ("task_id");--> statement-breakpoint
CREATE INDEX "evaluation_answers_question_id_idx" ON "evaluation_answers" ("question_id");--> statement-breakpoint
CREATE INDEX "evaluation_events_session_id_idx" ON "evaluation_events" ("session_id");--> statement-breakpoint
CREATE INDEX "evaluation_events_user_id_idx" ON "evaluation_events" ("user_id");--> statement-breakpoint
CREATE INDEX "evaluation_events_task_id_idx" ON "evaluation_events" ("task_id");--> statement-breakpoint
CREATE INDEX "evaluation_events_type_idx" ON "evaluation_events" ("type");--> statement-breakpoint
CREATE INDEX "evaluation_events_created_at_idx" ON "evaluation_events" ("created_at");--> statement-breakpoint
CREATE INDEX "evaluation_sessions_user_id_idx" ON "evaluation_sessions" ("user_id");--> statement-breakpoint
CREATE INDEX "evaluation_sessions_participant_id_idx" ON "evaluation_sessions" ("participant_id");--> statement-breakpoint
CREATE INDEX "evaluation_sessions_started_at_idx" ON "evaluation_sessions" ("started_at");--> statement-breakpoint
CREATE INDEX "evaluation_tasks_session_id_idx" ON "evaluation_tasks" ("session_id");--> statement-breakpoint
CREATE INDEX "evaluation_tasks_user_id_idx" ON "evaluation_tasks" ("user_id");--> statement-breakpoint
CREATE INDEX "evaluation_tasks_task_id_idx" ON "evaluation_tasks" ("task_id");--> statement-breakpoint
CREATE INDEX "evaluation_tasks_status_idx" ON "evaluation_tasks" ("status");--> statement-breakpoint
ALTER TABLE "evaluation_answers" ADD CONSTRAINT "evaluation_answers_session_id_evaluation_sessions_id_fkey" FOREIGN KEY ("session_id") REFERENCES "evaluation_sessions"("id") ON DELETE CASCADE;--> statement-breakpoint
ALTER TABLE "evaluation_answers" ADD CONSTRAINT "evaluation_answers_user_id_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE SET NULL;--> statement-breakpoint
ALTER TABLE "evaluation_events" ADD CONSTRAINT "evaluation_events_session_id_evaluation_sessions_id_fkey" FOREIGN KEY ("session_id") REFERENCES "evaluation_sessions"("id") ON DELETE CASCADE;--> statement-breakpoint
ALTER TABLE "evaluation_events" ADD CONSTRAINT "evaluation_events_user_id_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE SET NULL;--> statement-breakpoint
ALTER TABLE "evaluation_sessions" ADD CONSTRAINT "evaluation_sessions_user_id_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE SET NULL;--> statement-breakpoint
ALTER TABLE "evaluation_tasks" ADD CONSTRAINT "evaluation_tasks_session_id_evaluation_sessions_id_fkey" FOREIGN KEY ("session_id") REFERENCES "evaluation_sessions"("id") ON DELETE CASCADE;--> statement-breakpoint
ALTER TABLE "evaluation_tasks" ADD CONSTRAINT "evaluation_tasks_user_id_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE SET NULL;