import { Pressable, type PressableProps } from "react-native";
import { createStyles } from "@/lib/theme/factories";
import { Icon, type IconName } from "@/lib/ui/icon";

export type IconButtonProps = {
	accessibilityLabel: string;
	icon: IconName;
	iconSize?: number;
	onPress?: PressableProps["onPress"];
};

export function IconButton(props: IconButtonProps) {
	const { accessibilityLabel, icon, iconSize = 21, onPress } = props;
	const { styles, theme } = useStyles();

	return (
		<Pressable accessibilityLabel={accessibilityLabel} accessibilityRole="button" onPress={onPress} style={styles.button}>
			<Icon color={theme.colors.text} name={icon} size={iconSize} />
		</Pressable>
	);
}

const useStyles = createStyles(() => ({
	button: {
		alignItems: "center",
		height: 44,
		justifyContent: "center",
		width: 44,
	},
}));
