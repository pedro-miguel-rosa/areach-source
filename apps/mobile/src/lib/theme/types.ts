import type { radius, shadows, spacing, typography } from "./tokens";

export type Colors = {
	background: string;
	backgroundMuted: string;

	surface: string;
	surfaceRaised: string;
	surfaceMuted: string;
	surfaceDisabled: string;

	text: string;
	textSecondary: string;
	textMuted: string;
	textDisabled: string;
	textPlaceholder: string;
	textInverse: string;
	textOnPrimary: string;
	textLink: string;

	border: string;
	borderMuted: string;
	borderStrong: string;
	borderFocus: string;
	inputSurface: string;

	buttonOutlineBackground: string;
	buttonOutlineBackgroundDisabled: string;
	buttonOutlineBackgroundPressed: string;
	buttonOutlineBorder: string;
	buttonOutlineBorderDisabled: string;
	buttonOutlineBorderPressed: string;

	primary: string;
	primaryPressed: string;
	primaryMuted: string;

	accent: string;
	accentMuted: string;

	success: string;
	successSurface: string;
	successMuted: string;
	successBorder: string;

	warning: string;
	warningSurface: string;
	warningMuted: string;
	warningBorder: string;

	error: string;
	errorSurface: string;
	errorMuted: string;
	errorBorder: string;

	info: string;
	infoSurface: string;
	infoMuted: string;
	infoBorder: string;

	backdrop: string;
	shadow: string;
};

export type Theme = {
	colors: Colors;
	radius: typeof radius;
	spacing: typeof spacing;
	shadows: typeof shadows;
	typography: typeof typography;
	isDark: boolean;
};
