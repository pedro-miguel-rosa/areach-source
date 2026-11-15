import type { StyleProp, ViewStyle } from "react-native";
import { createStyles } from "@/lib/theme/factories";
import { View } from "@/lib/ui/view";

type SkeletonProps = {
	height: ViewStyle["height"];
	radius?: number;
	style?: StyleProp<ViewStyle>;
	width?: ViewStyle["width"];
};

export function Skeleton(props: SkeletonProps) {
	const { height, radius, style, width = "100%" } = props;
	const { styles, theme } = useStyles();

	return (
		<View
			accessibilityElementsHidden
			importantForAccessibility="no-hide-descendants"
			style={[styles.skeleton, { borderRadius: radius ?? theme.radius.md, height, opacity: 0.64, width }, style]}
		/>
	);
}

const useStyles = createStyles((theme) => ({
	skeleton: {
		backgroundColor: theme.colors.surfaceMuted,
	},
}));
