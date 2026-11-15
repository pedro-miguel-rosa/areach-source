import type { ReactNode } from "react";
import type { ViewStyle } from "react-native";
import { createStyles } from "@/lib/theme/factories";
import type { spacing } from "@/lib/theme/tokens";
import { View } from "@/lib/ui/view";

type SpacingToken = keyof typeof spacing;

export type RowProps = {
	align?: ViewStyle["alignItems"];
	backgroundColor?: ViewStyle["backgroundColor"];
	borderColor?: ViewStyle["borderColor"];
	borderRadius?: ViewStyle["borderRadius"];
	borderWidth?: ViewStyle["borderWidth"];
	children: ReactNode;
	fill?: boolean;
	gap?: SpacingToken;
	height?: ViewStyle["height"];
	justify?: ViewStyle["justifyContent"];
	margin?: SpacingToken;
	marginBottom?: SpacingToken;
	marginHorizontal?: SpacingToken;
	marginLeft?: SpacingToken;
	marginRight?: SpacingToken;
	marginTop?: SpacingToken;
	marginVertical?: SpacingToken;
	minHeight?: ViewStyle["minHeight"];
	padding?: SpacingToken;
	paddingBottom?: SpacingToken;
	paddingHorizontal?: SpacingToken;
	paddingLeft?: SpacingToken;
	paddingRight?: SpacingToken;
	paddingTop?: SpacingToken;
	paddingVertical?: SpacingToken;
	style?: ViewStyle;
	width?: ViewStyle["width"];
};

export function Row(props: RowProps) {
	const {
		align,
		backgroundColor,
		borderColor,
		borderRadius,
		borderWidth,
		children,
		fill,
		gap = "md",
		height,
		justify,
		margin,
		marginBottom,
		marginHorizontal,
		marginLeft,
		marginRight,
		marginTop,
		marginVertical,
		minHeight,
		padding,
		paddingBottom,
		paddingHorizontal,
		paddingLeft,
		paddingRight,
		paddingTop,
		paddingVertical,
		style,
		width,
	} = props;

	const { theme, styles } = useStyles();

	const rowStyle = [
		styles.row,
		fill && styles.fill,
		{
			alignItems: align,
			backgroundColor,
			borderColor,
			borderRadius,
			borderWidth,
			gap: theme.spacing[gap],
			height,
			justifyContent: justify,
			minHeight,
			width,
		},
		padding && { padding: theme.spacing[padding] },
		paddingHorizontal && { paddingHorizontal: theme.spacing[paddingHorizontal] },
		paddingVertical && { paddingVertical: theme.spacing[paddingVertical] },
		paddingTop && { paddingTop: theme.spacing[paddingTop] },
		paddingRight && { paddingRight: theme.spacing[paddingRight] },
		paddingBottom && { paddingBottom: theme.spacing[paddingBottom] },
		paddingLeft && { paddingLeft: theme.spacing[paddingLeft] },
		margin && { margin: theme.spacing[margin] },
		marginHorizontal && { marginHorizontal: theme.spacing[marginHorizontal] },
		marginVertical && { marginVertical: theme.spacing[marginVertical] },
		marginTop && { marginTop: theme.spacing[marginTop] },
		marginRight && { marginRight: theme.spacing[marginRight] },
		marginBottom && { marginBottom: theme.spacing[marginBottom] },
		marginLeft && { marginLeft: theme.spacing[marginLeft] },
		style,
	];

	return <View style={rowStyle}>{children}</View>;
}

const useStyles = createStyles(() => ({
	row: {
		flexDirection: "row",
	},
	fill: {
		flex: 1,
	},
}));
