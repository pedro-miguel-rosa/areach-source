import type { ReactNode } from "react";
import { createStyles } from "@/lib/theme/factories";
import { Icon, type IconName } from "@/lib/ui/icon";
import { Text } from "@/lib/ui/text";
import { View } from "@/lib/ui/view";

export type BadgeVariant = "accent" | "info" | "neutral" | "success";

type BadgeProps = {
	children: ReactNode;
	icon?: IconName;
	variant: BadgeVariant;
};

export function Badge(props: BadgeProps) {
	const { children, icon, variant } = props;
	const { styles, theme } = useStyles();

	const palette = {
		accent: {
			background: theme.colors.surfaceMuted,
			text: theme.colors.textLink,
		},
		info: {
			background: theme.colors.infoSurface,
			text: theme.colors.info,
		},
		neutral: {
			background: theme.colors.surfaceMuted,
			text: theme.colors.textSecondary,
		},
		success: {
			background: theme.colors.successSurface,
			text: theme.colors.success,
		},
	}[variant];

	const badgeStyle = [
		styles.badge,
		{
			backgroundColor: palette.background,
			borderColor: variant === "neutral" ? theme.colors.border : undefined,
			borderWidth: variant === "neutral" ? 1 : 0,
			paddingLeft: icon ? theme.spacing.sm : theme.spacing.md,
		},
	];

	return (
		<View style={badgeStyle}>
			{icon ? <Icon color={palette.text} name={icon} size={11} /> : null}
			<Text color={palette.text} lineHeight={theme.typography.lineHeight.xs} size="sm" weight="semibold">
				{children}
			</Text>
		</View>
	);
}

const useStyles = createStyles((theme) => ({
	badge: {
		alignItems: "center",
		flexDirection: "row",
		gap: 6,
		borderRadius: theme.radius.full,
		paddingHorizontal: theme.spacing.md,
		paddingVertical: 6,
	},
}));
