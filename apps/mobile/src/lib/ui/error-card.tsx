import { type StyleProp, View, type ViewStyle } from "react-native";
import { createStyles } from "@/lib/theme/factories";
import { Icon } from "@/lib/ui/icon";
import { Text } from "@/lib/ui/text";

export type ErrorCardProps = {
	message: string;
	style?: StyleProp<ViewStyle>;
	title: string;
};

export function ErrorCard(props: ErrorCardProps) {
	const { message, style, title } = props;
	const { styles, theme } = useStyles();

	return (
		<View style={[styles.card, style]}>
			<Icon color={theme.colors.error} name="alertTriangle" size={21} style={styles.icon} />
			<View style={styles.copy}>
				<Text color={theme.colors.error} lineHeight={theme.typography.lineHeight.xs} size="sm" weight="bold">
					{title}
				</Text>
				<Text color={theme.colors.textSecondary} lineHeight={theme.typography.lineHeight.xs} size="sm">
					{message}
				</Text>
			</View>
		</View>
	);
}

const useStyles = createStyles((theme) => ({
	card: {
		alignItems: "flex-start",
		backgroundColor: theme.colors.errorSurface,
		borderColor: theme.colors.errorBorder,
		borderRadius: theme.radius.md,
		borderWidth: 1,
		flexDirection: "row",
		gap: theme.spacing.sm,
		paddingHorizontal: theme.spacing.md,
		paddingVertical: theme.spacing.md,
	},
	icon: {
		transform: [{ translateY: -1 }],
	},
	copy: {
		flex: 1,
		gap: 2,
	},
}));
