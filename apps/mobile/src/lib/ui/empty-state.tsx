import { type StyleProp, View, type ViewStyle } from "react-native";
import { createStyles } from "@/lib/theme/factories";
import { Button } from "@/lib/ui/button";
import { Icon, type IconName } from "@/lib/ui/icon";
import { Text } from "@/lib/ui/text";

type EmptyStateAction = {
	label: string;
	onPress: () => void;
};

export type EmptyStateProps = {
	description: string;
	icon: IconName;
	primaryAction?: EmptyStateAction;
	secondaryAction?: EmptyStateAction;
	style?: StyleProp<ViewStyle>;
	title: string;
};

export function EmptyState(props: EmptyStateProps) {
	const { description, icon, primaryAction, secondaryAction, style, title } = props;
	const { styles, theme } = useStyles();

	return (
		<View style={[styles.container, style]}>
			<View style={styles.iconCircle}>
				<Icon color={theme.colors.success} name={icon} size={28} />
			</View>
			<View style={styles.copy}>
				<Text align="center" color={theme.colors.text} size="lg" weight="bold">
					{title}
				</Text>
				<Text align="center" color={theme.colors.textSecondary} size="md">
					{description}
				</Text>
			</View>
			{primaryAction ? <Button onPress={primaryAction.onPress}>{primaryAction.label}</Button> : null}
			{secondaryAction ? (
				<Button onPress={secondaryAction.onPress} variant="text">
					{secondaryAction.label}
				</Button>
			) : null}
		</View>
	);
}

const useStyles = createStyles((theme) => ({
	container: {
		alignItems: "center",
		gap: theme.spacing.lg,
		padding: theme.spacing.lg,
	},
	copy: {
		alignItems: "center",
		gap: theme.spacing.xs,
	},
	iconCircle: {
		alignItems: "center",
		backgroundColor: theme.colors.successSurface,
		borderRadius: theme.radius.full,
		height: 72,
		justifyContent: "center",
		width: 72,
	},
}));
