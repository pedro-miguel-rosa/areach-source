import type { StyleProp, ViewStyle } from "react-native";
import { createStyles } from "@/lib/theme/factories";
import { Icon, type IconName } from "@/lib/ui/icon";
import { View } from "@/lib/ui/view";

export type IconIllustrationProps = {
	icon: IconName;
	size?: number;
	style?: StyleProp<ViewStyle>;
};

export function IconIllustration(props: IconIllustrationProps) {
	const { icon, size = 112, style } = props;
	const { styles, theme } = useStyles();

	const illustrationAccent = theme.colors.textLink;
	const illustrationCircle = theme.isDark ? theme.colors.surfaceDisabled : theme.colors.successSurface;
	const illustrationCircleBorder = theme.isDark ? theme.colors.borderStrong : theme.colors.successMuted;
	const decorationOpacity = theme.isDark ? 0.75 : 0.45;

	return (
		<View style={[styles.emptyWrap, style]}>
			<View
				style={[styles.illustrationDot, styles.illustrationDotTopLeft, { borderColor: illustrationAccent, opacity: decorationOpacity }]}
			/>
			<View
				style={[styles.illustrationDot, styles.illustrationDotMidLeft, { borderColor: illustrationAccent, opacity: decorationOpacity }]}
			/>
			<View
				style={[styles.illustrationDot, styles.illustrationDotLowLeft, { borderColor: illustrationAccent, opacity: decorationOpacity }]}
			/>
			<View
				style={[styles.illustrationDot, styles.illustrationDotUpperLeft, { borderColor: illustrationAccent, opacity: decorationOpacity }]}
			/>
			<View
				style={[styles.illustrationDot, styles.illustrationDotTopRight, { borderColor: illustrationAccent, opacity: decorationOpacity }]}
			/>
			<View
				style={[styles.illustrationDot, styles.illustrationDotMidRight, { borderColor: illustrationAccent, opacity: decorationOpacity }]}
			/>
			<View
				style={[styles.illustrationDot, styles.illustrationDotLowRight, { borderColor: illustrationAccent, opacity: decorationOpacity }]}
			/>
			<View
				style={[styles.illustrationDot, styles.illustrationDotLowerRight, { borderColor: illustrationAccent, opacity: decorationOpacity }]}
			/>
			<View
				style={[styles.illustrationStar, styles.illustrationStarLeft, { borderColor: illustrationAccent, opacity: decorationOpacity }]}
			/>
			<View
				style={[styles.illustrationStar, styles.illustrationStarRight, { borderColor: illustrationAccent, opacity: decorationOpacity }]}
			/>
			<View
				style={[
					styles.emptyCircle,
					{ backgroundColor: illustrationCircle, borderColor: illustrationCircleBorder, height: size, width: size },
				]}
			>
				<Icon color={illustrationAccent} name={icon} size={44} />
			</View>
		</View>
	);
}

const useStyles = createStyles((theme) => ({
	emptyCircle: {
		alignItems: "center",
		borderRadius: theme.radius.full,
		borderWidth: 1,
		justifyContent: "center",
	},
	emptyWrap: {
		alignItems: "center",
		alignSelf: "center",
		height: 144,
		justifyContent: "center",
		width: 240,
	},
	illustrationDot: {
		position: "absolute",
	},
	illustrationDotLowLeft: {
		borderRadius: 2,
		borderWidth: 1.5,
		height: 4,
		left: 38,
		top: 78,
		width: 4,
	},
	illustrationDotLowRight: {
		borderRadius: 2.5,
		borderWidth: 1.5,
		height: 5,
		right: 46,
		top: 84,
		width: 5,
	},
	illustrationDotLowerRight: {
		borderRadius: 4,
		borderWidth: 2,
		height: 8,
		right: 68,
		top: 100,
		width: 8,
	},
	illustrationDotMidLeft: {
		borderRadius: 2.5,
		borderWidth: 1.5,
		height: 5,
		left: 32,
		top: 48,
		width: 5,
	},
	illustrationDotMidRight: {
		borderRadius: 3,
		borderWidth: 2,
		height: 6,
		right: 34,
		top: 52,
		width: 6,
	},
	illustrationDotTopLeft: {
		borderRadius: 3.5,
		borderWidth: 2,
		height: 7,
		left: 56,
		top: 20,
		width: 7,
	},
	illustrationDotTopRight: {
		borderRadius: 2,
		borderWidth: 1.5,
		height: 4,
		right: 52,
		top: 22,
		width: 4,
	},
	illustrationDotUpperLeft: {
		borderRadius: 3,
		borderWidth: 2,
		height: 6,
		left: 88,
		top: 16,
		width: 6,
	},
	illustrationStar: {
		borderRadius: 2,
		borderWidth: 1.5,
		height: 5,
		position: "absolute",
		transform: [{ rotate: "45deg" }],
		width: 5,
	},
	illustrationStarLeft: {
		left: 74,
		top: 64,
	},
	illustrationStarRight: {
		right: 80,
		top: 70,
	},
}));
