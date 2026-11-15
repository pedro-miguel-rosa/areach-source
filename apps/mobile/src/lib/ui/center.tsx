import type { ViewStyle } from "react-native";
import { createStyles } from "@/lib/theme/factories";
import { View, type ViewProps } from "@/lib/ui/view";

export type CenterProps = ViewProps & {
	height: ViewStyle["height"];
	width: ViewStyle["width"];
};

export function Center(props: CenterProps) {
	const { height, style, width, ...viewProps } = props;
	const { styles } = useStyles();

	return <View {...viewProps} style={[styles.center, style, { height, width }]} />;
}

const useStyles = createStyles(() => ({
	center: {
		alignItems: "center",
		justifyContent: "center",
	},
}));
