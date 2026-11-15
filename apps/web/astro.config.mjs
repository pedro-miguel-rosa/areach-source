// @ts-check

import cloudflare from "@astrojs/cloudflare";
import { defineConfig } from "astro/config";

// http://localhost:4321
export default defineConfig({
	adapter: cloudflare(),
	site: "http://localhost:4321",
});
