import type { ReactNode } from "react";
import { type StyleProp, Text, View, type ViewStyle } from "react-native";
import { createStyles } from "@/lib/theme/factories";

export type ChipVariant = "live" | "upcoming" | "full" | "neutral" | "skill" | "interest";

export type ChipProps = {
	children: ReactNode;
	dot?: boolean;
	style?: StyleProp<ViewStyle>;
	variant?: ChipVariant;
};

export function Chip(props: ChipProps) {
	const { children, dot = false, style, variant = "neutral" } = props;
	const { styles, theme } = useStyles();
	const palette = getChipColors(variant, theme);

	return (
		<View style={[styles.chip, { backgroundColor: palette.background, borderColor: palette.border }, style]}>
			{dot ? <View style={[styles.dot, { backgroundColor: palette.text }]} /> : null}
			<Text style={[styles.label, { color: palette.text }]}>{children}</Text>
		</View>
	);
}

function getChipColors(variant: ChipVariant, theme: ReturnType<typeof useStyles>["theme"]) {
	switch (variant) {
		case "full":
			return {
				background: theme.colors.errorSurface,
				border: theme.colors.errorBorder,
				text: theme.colors.error,
			};
		case "interest":
			return {
				background: theme.colors.surfaceMuted,
				border: theme.colors.primary,
				text: theme.colors.textLink,
			};
		case "live":
			return {
				background: theme.colors.successSurface,
				border: theme.colors.successBorder,
				text: theme.colors.success,
			};
		case "neutral":
			return {
				background: theme.colors.background,
				border: theme.colors.border,
				text: theme.colors.textSecondary,
			};
		case "skill":
			return {
				background: theme.colors.surfaceMuted,
				border: theme.colors.borderStrong,
				text: theme.colors.text,
			};
		case "upcoming":
			return {
				background: theme.colors.infoSurface,
				border: theme.colors.infoBorder,
				text: theme.colors.info,
			};
	}

	return {
		background: theme.colors.background,
		border: theme.colors.border,
		text: theme.colors.textSecondary,
	};
}

const useStyles = createStyles((theme) => ({
	chip: {
		alignItems: "center",
		alignSelf: "flex-start",
		borderRadius: theme.radius.full,
		borderWidth: 1,
		flexDirection: "row",
		gap: 6,
		paddingHorizontal: theme.spacing.sm,
		paddingVertical: 6,
	},
	dot: {
		borderRadius: theme.radius.full,
		height: 6,
		width: 6,
	},
	label: {
		fontSize: theme.typography.size.sm,
		lineHeight: theme.typography.lineHeight.xs,
		fontWeight: theme.typography.weight.semibold,
	},
}));
