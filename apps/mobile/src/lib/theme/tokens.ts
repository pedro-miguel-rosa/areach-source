import type { TextStyle, ViewStyle } from "react-native";
import type { Colors } from "./types";

export const radius = {
	sm: 8,
	md: 12,
	lg: 16,
	xl: 20,
	xxl: 24,
	full: 999,
} as const;

export const spacing = {
	xxs: 4,
	xs: 8,
	sm: 12,
	md: 16,
	lg: 24,
	xl: 32,
	xxl: 48,
	xxxl: 64,
} as const;

export const fontSizes = {
	xs: 12,
	sm: 14,
	md: 16,
	lg: 22,
	xl: 30,
	xxl: 42,
} as const;

export const fontWeights = {
	regular: "400",
	semibold: "600",
	bold: "700",
} as const satisfies Record<string, TextStyle["fontWeight"]>;

export const lineHeights = {
	xs: 18,
	sm: 20,
	md: 24,
	lg: 30,
	xl: 38,
	xxl: 48,
} as const;

export const typography = {
	size: fontSizes,
	lineHeight: lineHeights,
	weight: fontWeights,
} as const;

export const shadows = {
	xs: {
		shadowColor: "#0B1613",
		shadowOffset: { width: 0, height: 4 },
		shadowOpacity: 0.04,
		shadowRadius: 12,
		elevation: 1,
	},
	sm: {
		shadowColor: "#0B1613",
		shadowOffset: { width: 0, height: 4 },
		shadowOpacity: 0.06,
		shadowRadius: 16,
		elevation: 3,
	},
	md: {
		shadowColor: "#0B1613",
		shadowOffset: { width: 0, height: 8 },
		shadowOpacity: 0.1,
		shadowRadius: 24,
		elevation: 5,
	},
	lg: {
		shadowColor: "#0B1613",
		shadowOffset: { width: 0, height: 12 },
		shadowOpacity: 0.06,
		shadowRadius: 28,
		elevation: 6,
	},
} as const satisfies Record<"xs" | "sm" | "md" | "lg", ViewStyle>;

export const lightColors = {
	background: "#FFFFFF",
	backgroundMuted: "#F8FAFC",
	surface: "#FFFFFF",
	surfaceRaised: "#FFFFFF",
	surfaceMuted: "#F8FAFC",
	surfaceDisabled: "#F2F4F7",

	text: "#0B1613",
	textSecondary: "#4E5A54",
	textMuted: "#5B6670",
	textDisabled: "#8793A0",
	textPlaceholder: "#8E99A8",
	textInverse: "#FFFFFF",
	textOnPrimary: "#FFFFFF",
	textLink: "#14664A",

	border: "#E2E8F0",
	borderMuted: "#F2F4F7",
	borderStrong: "#CBD5E1",
	borderFocus: "#14664A",
	inputSurface: "#FFFFFF",

	buttonOutlineBackground: "rgba(255, 255, 255, 0.04)",
	buttonOutlineBackgroundDisabled: "rgba(255, 255, 255, 0.025)",
	buttonOutlineBackgroundPressed: "rgba(255, 255, 255, 0.08)",
	buttonOutlineBorder: "rgba(255, 255, 255, 0.34)",
	buttonOutlineBorderDisabled: "rgba(255, 255, 255, 0.18)",
	buttonOutlineBorderPressed: "rgba(255, 255, 255, 0.48)",

	primary: "#14664A",
	primaryPressed: "#0F5B42",
	primaryMuted: "#ECFDF5",

	accent: "#14664A",
	accentMuted: "#ECFDF5",

	success: "#047857",
	successSurface: "#ECFDF5",
	successMuted: "#D1FAE5",
	successBorder: "#D1FAE5",

	warning: "#B45309",
	warningSurface: "#FFFBEB",
	warningMuted: "#FEF3C7",
	warningBorder: "#FEF3C7",

	error: "#B91C1C",
	errorSurface: "#FEF2F2",
	errorMuted: "#FEE2E2",
	errorBorder: "#FEE2E2",

	info: "#1D4ED8",
	infoSurface: "#EFF6FF",
	infoMuted: "#DBEAFE",
	infoBorder: "#DBEAFE",

	backdrop: "#00000066",
	shadow: "#0B1613",
} as const satisfies Colors;

export const darkColors = {
	background: "#0B1613",
	backgroundMuted: "#07110E",
	surface: "#0B1613",
	surfaceRaised: "#09120F",
	surfaceMuted: "#08100D",
	surfaceDisabled: "#112019",

	text: "#FFFFFF",
	textSecondary: "#B7C0B8",
	textMuted: "#98A39C",
	textDisabled: "#66716B",
	textPlaceholder: "#78817B",
	textInverse: "#0B1613",
	textOnPrimary: "#FFFFFF",
	textLink: "#63B77A",

	border: "#1E2522",
	borderMuted: "#131815",
	borderStrong: "#303A34",
	borderFocus: "#63B77A",
	inputSurface: "#0C1314",

	buttonOutlineBackground: "rgba(255, 255, 255, 0.04)",
	buttonOutlineBackgroundDisabled: "rgba(255, 255, 255, 0.025)",
	buttonOutlineBackgroundPressed: "rgba(255, 255, 255, 0.08)",
	buttonOutlineBorder: "rgba(255, 255, 255, 0.34)",
	buttonOutlineBorderDisabled: "rgba(255, 255, 255, 0.18)",
	buttonOutlineBorderPressed: "rgba(255, 255, 255, 0.48)",

	primary: "#0E3826",
	primaryPressed: "#0A2F1F",
	primaryMuted: "#071B12",

	accent: "#0E3826",
	accentMuted: "#071B12",

	success: "#4EA76D",
	successSurface: "#051E15",
	successMuted: "#0E3525",
	successBorder: "#143D2B",

	warning: "#FCD34D",
	warningSurface: "#451A03",
	warningMuted: "#92400E",
	warningBorder: "#92400E",

	error: "#FCA5A5",
	errorSurface: "#450A0A",
	errorMuted: "#991B1B",
	errorBorder: "#991B1B",

	info: "#93C5FD",
	infoSurface: "#172554",
	infoMuted: "#1E40AF",
	infoBorder: "#1E40AF",

	backdrop: "#00000099",
	shadow: "#000000",
} as const satisfies Colors;
