import type { z } from "@hono/zod-openapi";
import type { updateProfileBodySchema } from "./routes";

export type UpdateProfileInput = Partial<z.infer<typeof updateProfileBodySchema>>;

export type UpdateProfileRecord = Omit<UpdateProfileInput, "askMeAbout"> & {
	askMeAbout?: string;
};
