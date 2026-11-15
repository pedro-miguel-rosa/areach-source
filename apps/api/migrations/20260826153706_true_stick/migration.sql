ALTER TABLE "event_attendee" ADD COLUMN "nearby_peer_id" text;--> statement-breakpoint
ALTER TABLE "event_attendee" ADD COLUMN "nearby_public_key" text;--> statement-breakpoint
ALTER TABLE "event_attendee" ADD COLUMN "nearby_credential" text;--> statement-breakpoint
ALTER TABLE "event_attendee" ADD COLUMN "nearby_credential_expires_at" timestamp;