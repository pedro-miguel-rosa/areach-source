import type { ReactNode } from "react";
import { Pressable, type PressableProps, View } from "react-native";
import { createStyles } from "@/lib/theme/factories";

export type CardProps = {
	accessibilityLabel?: string;
	children: ReactNode;
	onPress?: PressableProps["onPress"];
	padding?: "sm" | "md" | "lg";
	shadow?: "sm" | "md" | "lg";
};

export function Card(props: CardProps) {
	const { accessibilityLabel, children, onPress, padding = "lg", shadow = "sm" } = props;
	const { styles, theme } = useStyles();

	const paddingStyle = { padding: theme.spacing[padding] };
	const cardStyle = [styles.card, paddingStyle, theme.shadows[shadow]];

	if (onPress) {
		return (
			<Pressable
				accessibilityLabel={accessibilityLabel}
				accessibilityRole="button"
				onPress={onPress}
				style={({ pressed }) => [cardStyle, pressed && styles.pressed]}
			>
				{children}
			</Pressable>
		);
	}

	return <View style={cardStyle}>{children}</View>;
}

const useStyles = createStyles((theme) => ({
	card: {
		backgroundColor: theme.colors.surfaceRaised,
		borderColor: theme.colors.border,
		borderRadius: theme.radius.lg,
		borderWidth: 1,
	},
	pressed: {
		opacity: 0.96,
		transform: [{ scale: 0.985 }],
	},
}));
