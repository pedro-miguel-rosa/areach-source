import type { ReactNode } from "react";
import type { ViewStyle } from "react-native";
import { createStyles } from "@/lib/theme/factories";
import type { spacing } from "@/lib/theme/tokens";
import { View } from "@/lib/ui/view";

type SpacingToken = keyof typeof spacing;

export type ColumnProps = {
	children: ReactNode;
	align?: ViewStyle["alignItems"];
	alignSelf?: ViewStyle["alignSelf"];
	backgroundColor?: ViewStyle["backgroundColor"];
	flex?: boolean;
	gap?: SpacingToken;
	justify?: ViewStyle["justifyContent"];
	maxWidth?: ViewStyle["maxWidth"];
	minWidth?: ViewStyle["minWidth"];
	margin?: SpacingToken;
	marginBottom?: SpacingToken;
	marginHorizontal?: SpacingToken;
	marginLeft?: SpacingToken;
	marginRight?: SpacingToken;
	marginTop?: SpacingToken;
	marginVertical?: SpacingToken;
	padding?: SpacingToken;
	paddingBottom?: SpacingToken;
	paddingHorizontal?: SpacingToken;
	paddingLeft?: SpacingToken;
	paddingRight?: SpacingToken;
	paddingTop?: SpacingToken;
	paddingVertical?: SpacingToken;
	width?: ViewStyle["width"];
};

export function Column(props: ColumnProps) {
	const {
		align,
		alignSelf,
		backgroundColor,
		children,
		flex = false,
		gap,
		justify,
		margin,
		marginBottom,
		marginHorizontal,
		marginLeft,
		marginRight,
		marginTop,
		marginVertical,
		maxWidth,
		minWidth,
		padding,
		paddingBottom,
		paddingHorizontal,
		paddingLeft,
		paddingRight,
		paddingTop,
		paddingVertical,
		width,
	} = props;
	const { theme, styles } = useStyles();

	const layoutStyle = {
		alignItems: align,
		alignSelf,
		backgroundColor,
		...(gap && { gap: theme.spacing[gap] }),
		justifyContent: justify,
		width,
		maxWidth,
		minWidth,
	};
	const marginStyle = {
		...(margin && { margin: theme.spacing[margin] }),
		...(marginHorizontal && { marginHorizontal: theme.spacing[marginHorizontal] }),
		...(marginVertical && { marginVertical: theme.spacing[marginVertical] }),
		...(marginTop && { marginTop: theme.spacing[marginTop] }),
		...(marginRight && { marginRight: theme.spacing[marginRight] }),
		...(marginBottom && { marginBottom: theme.spacing[marginBottom] }),
		...(marginLeft && { marginLeft: theme.spacing[marginLeft] }),
	};
	const paddingStyle = {
		...(padding && { padding: theme.spacing[padding] }),
		...(paddingHorizontal && { paddingHorizontal: theme.spacing[paddingHorizontal] }),
		...(paddingVertical && { paddingVertical: theme.spacing[paddingVertical] }),
		...(paddingTop && { paddingTop: theme.spacing[paddingTop] }),
		...(paddingRight && { paddingRight: theme.spacing[paddingRight] }),
		...(paddingBottom && { paddingBottom: theme.spacing[paddingBottom] }),
		...(paddingLeft && { paddingLeft: theme.spacing[paddingLeft] }),
	};

	const columnStyle = [styles.column, flex && styles.flex, layoutStyle, marginStyle, paddingStyle];

	return <View style={columnStyle}>{children}</View>;
}

const useStyles = createStyles(() => ({
	column: {
		flexDirection: "column",
	},
	flex: {
		flex: 1,
	},
}));
