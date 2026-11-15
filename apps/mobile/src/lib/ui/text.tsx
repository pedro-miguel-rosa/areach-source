import type { ReactNode } from "react";
import { Text as RNText, type TextProps as RNTextProps, type TextStyle } from "react-native";
import { useTheme } from "@/lib/theme/hooks";
import { darkTheme, lightTheme } from "@/lib/theme/themes";
import type { Theme } from "@/lib/theme/types";

export type TextProps = {
	align?: TextStyle["textAlign"];
	children: ReactNode;
	backgroundColor?: TextStyle["backgroundColor"];
	color?: TextStyle["color"];
	opacity?: TextStyle["opacity"];
	lineHeight?: TextStyle["lineHeight"];
	appearance?: "light" | "dark";
	onPress?: RNTextProps["onPress"];
	numberOfLines?: RNTextProps["numberOfLines"];
	textDecorationLine?: TextStyle["textDecorationLine"];
	size?: keyof Theme["typography"]["size"];
	weight?: "semibold" | "bold";
};

export function Text(props: TextProps) {
	const {
		align,
		backgroundColor,
		children,
		color,
		lineHeight,
		appearance,
		numberOfLines,
		onPress,
		opacity,
		size = "md",
		textDecorationLine,
		weight,
	} = props;
	const theme = useTheme();
	const resolvedTheme = appearance === "light" ? lightTheme : appearance === "dark" ? darkTheme : theme;

	const textStyle: TextStyle = {
		backgroundColor,
		color: color ?? resolvedTheme.colors.text,
		fontSize: resolvedTheme.typography.size[size],
		lineHeight: lineHeight ?? resolvedTheme.typography.lineHeight[size],
		opacity,
		textDecorationLine,
		fontWeight: weight ? resolvedTheme.typography.weight[weight] : resolvedTheme.typography.weight.regular,
		textAlign: align,
	};

	return (
		<RNText numberOfLines={numberOfLines} onPress={onPress} style={textStyle}>
			{children}
		</RNText>
	);
}
