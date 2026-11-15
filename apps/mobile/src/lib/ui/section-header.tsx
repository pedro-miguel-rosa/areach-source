import type { ReactNode } from "react";
import { type StyleProp, View, type ViewStyle } from "react-native";
import { createStyles } from "@/lib/theme/factories";
import { Text } from "@/lib/ui/text";

export type SectionHeaderProps = {
	action?: ReactNode;
	style?: StyleProp<ViewStyle>;
	subtitle?: string;
	title: string;
};

export function SectionHeader(props: SectionHeaderProps) {
	const { action, style, subtitle, title } = props;
	const { styles, theme } = useStyles();

	return (
		<View style={[styles.container, style]}>
			<View style={styles.copy}>
				<Text size="lg" weight="bold">
					{title}
				</Text>
				{subtitle ? (
					<Text color={theme.colors.textSecondary} size="md">
						{subtitle}
					</Text>
				) : null}
			</View>
			{action}
		</View>
	);
}

const useStyles = createStyles((theme) => ({
	container: {
		alignItems: "flex-start",
		flexDirection: "row",
		gap: theme.spacing.md,
		justifyContent: "space-between",
	},
	copy: {
		flex: 1,
		gap: theme.spacing.xs,
	},
}));
