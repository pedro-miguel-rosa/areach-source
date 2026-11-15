import { darkColors, lightColors, radius, shadows, spacing, typography } from "./tokens";
import type { Theme } from "./types";

export const lightTheme = {
	colors: lightColors,
	radius,
	spacing,
	shadows,
	typography,
	isDark: false,
} as const satisfies Theme;

export const darkTheme = {
	colors: darkColors,
	radius,
	spacing,
	shadows,
	typography,
	isDark: true,
} as const satisfies Theme;
