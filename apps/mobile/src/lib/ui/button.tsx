import type { ReactNode } from "react";
import { ActivityIndicator, Pressable, type PressableProps, type ViewStyle } from "react-native";
import { createStyles } from "@/lib/theme/factories";
import { darkTheme, lightTheme } from "@/lib/theme/themes";
import type { Theme } from "@/lib/theme/types";
import { Text } from "@/lib/ui/text";

type ButtonSize = "xs" | "sm" | "md" | "lg" | "xl";

type ButtonLabelSize = "xs" | "sm" | "md" | "lg";

type ButtonSizeConfig = {
	minHeight: number;
	minWidth: number;
	borderRadius: keyof Theme["radius"];
	paddingHorizontal: keyof Theme["spacing"];
	paddingVertical: keyof Theme["spacing"];
	filledLabelSize: ButtonLabelSize;
	borderlessLabelSize: ButtonLabelSize;
};

export type ButtonProps = {
	children: ReactNode;
	appearance?: "light" | "dark";
	disabled?: PressableProps["disabled"];
	flex?: boolean;
	loading?: boolean;
	onPress?: PressableProps["onPress"];
	size?: ButtonSize;
	variant?: "primary" | "surface" | "text" | "danger" | "dangerOutline" | "outline" | "white" | "link";
};

type ButtonVisualState = {
	backgroundColor: string;
	borderColor: string;
	borderRadius: number;
	borderWidth: number;
	isBorderlessVariant: boolean;
	isLinkVariant: boolean;
	minHeight: number;
	minWidth: number;
	paddingHorizontal: number;
	paddingVertical: number;
	pressedStyle?: ViewStyle;
	shadow?: ViewStyle;
	textColor: string;
};

const buttonSizes: Record<ButtonSize, ButtonSizeConfig> = {
	xs: {
		minHeight: 36,
		minWidth: 64,
		borderRadius: "sm",
		paddingHorizontal: "xs",
		paddingVertical: "xxs",
		filledLabelSize: "xs",
		borderlessLabelSize: "xs",
	},
	sm: {
		minHeight: 44,
		minWidth: 72,
		borderRadius: "md",
		paddingHorizontal: "sm",
		paddingVertical: "xs",
		filledLabelSize: "sm",
		borderlessLabelSize: "sm",
	},
	md: {
		minHeight: 56,
		minWidth: 80,
		borderRadius: "lg",
		paddingHorizontal: "lg",
		paddingVertical: "md",
		filledLabelSize: "md",
		borderlessLabelSize: "md",
	},
	lg: {
		minHeight: 64,
		minWidth: 88,
		borderRadius: "xl",
		paddingHorizontal: "xl",
		paddingVertical: "md",
		filledLabelSize: "md",
		borderlessLabelSize: "md",
	},
	xl: {
		minHeight: 72,
		minWidth: 96,
		borderRadius: "xxl",
		paddingHorizontal: "xxl",
		paddingVertical: "lg",
		filledLabelSize: "lg",
		borderlessLabelSize: "lg",
	},
};

export function Button(props: ButtonProps) {
	const { children, disabled, flex, loading, appearance, onPress, size = "md", variant = "primary" } = props;
	const { styles, theme } = useStyles();
	const buttonTheme = appearance === "light" ? lightTheme : appearance === "dark" ? darkTheme : theme;
	const sizeConfig = buttonSizes[size];
	const isLoading = Boolean(loading);
	const isDisabled = Boolean(disabled) || isLoading;
	const isLightAppearance = appearance === "light";
	const visualState = getButtonVisualState({
		buttonTheme,
		isDisabled,
		isLightAppearance,
		sizeConfig,
		variant,
	});

	return (
		<Pressable
			accessibilityRole="button"
			accessibilityState={{ busy: isLoading, disabled: isDisabled }}
			disabled={isDisabled}
			onPress={onPress}
			hitSlop={visualState.isLinkVariant ? 8 : undefined}
			style={({ pressed }) => [
				styles.base,
				flex && styles.flex,
				{
					alignSelf: visualState.isBorderlessVariant ? "flex-start" : "stretch",
					backgroundColor: visualState.backgroundColor,
					borderColor: visualState.borderColor,
					borderRadius: visualState.borderRadius,
					borderWidth: visualState.borderWidth,
					minHeight: visualState.isLinkVariant ? undefined : visualState.minHeight,
					minWidth: visualState.isLinkVariant ? undefined : visualState.minWidth,
					paddingHorizontal: visualState.isLinkVariant ? 0 : visualState.paddingHorizontal,
					paddingVertical: visualState.isLinkVariant ? 0 : visualState.paddingVertical,
					...(visualState.shadow ?? {}),
				},
				pressed && !isDisabled && styles.pressed,
				pressed && !isDisabled && visualState.pressedStyle,
			]}
		>
			{isLoading ? (
				<ActivityIndicator color={visualState.textColor} />
			) : (
				<Text
					align="center"
					color={visualState.textColor}
					lineHeight={
						buttonTheme.typography.lineHeight[visualState.isBorderlessVariant ? sizeConfig.borderlessLabelSize : sizeConfig.filledLabelSize]
					}
					size={visualState.isBorderlessVariant ? sizeConfig.borderlessLabelSize : sizeConfig.filledLabelSize}
					textDecorationLine={visualState.isLinkVariant ? "underline" : undefined}
					weight="semibold"
				>
					{children}
				</Text>
			)}
		</Pressable>
	);
}

function getButtonVisualState(props: {
	buttonTheme: ReturnType<typeof useStyles>["theme"];
	isDisabled: boolean;
	isLightAppearance: boolean;
	sizeConfig: ButtonSizeConfig;
	variant: NonNullable<ButtonProps["variant"]>;
}): ButtonVisualState {
	const { buttonTheme, isDisabled, isLightAppearance, sizeConfig, variant } = props;

	let backgroundColor = "transparent";
	let borderColor = "transparent";
	let borderWidth = 0;
	let shadow: ViewStyle | undefined;
	let textColor = buttonTheme.colors.text;
	let pressedStyle: ViewStyle | undefined;
	const isLinkVariant = variant === "link";
	const isBorderlessVariant = variant === "text" || variant === "link";

	switch (variant) {
		case "primary":
			backgroundColor = isDisabled ? buttonTheme.colors.primaryMuted : buttonTheme.colors.primary;
			borderColor = backgroundColor;
			borderWidth = 1;
			shadow = isDisabled ? undefined : buttonTheme.shadows.md;
			textColor = isDisabled ? buttonTheme.colors.textDisabled : buttonTheme.colors.textOnPrimary;
			break;
		case "surface":
			backgroundColor = isDisabled ? buttonTheme.colors.surfaceDisabled : buttonTheme.colors.surfaceRaised;
			borderColor = isDisabled ? buttonTheme.colors.borderMuted : buttonTheme.colors.border;
			borderWidth = 1;
			shadow = isDisabled ? undefined : buttonTheme.shadows.md;
			textColor = isDisabled ? buttonTheme.colors.textDisabled : buttonTheme.colors.textLink;
			break;
		case "text":
		case "link":
			backgroundColor = "transparent";
			borderColor = "transparent";
			borderWidth = 0;
			shadow = undefined;
			textColor = isDisabled ? buttonTheme.colors.textDisabled : buttonTheme.colors.textLink;
			break;
		case "danger":
			backgroundColor = isDisabled ? buttonTheme.colors.errorMuted : buttonTheme.colors.error;
			borderColor = backgroundColor;
			borderWidth = 1;
			shadow = isDisabled ? undefined : buttonTheme.shadows.md;
			textColor = isDisabled ? buttonTheme.colors.textDisabled : buttonTheme.colors.textOnPrimary;
			break;
		case "dangerOutline":
			backgroundColor = "transparent";
			borderColor = isDisabled ? buttonTheme.colors.borderMuted : buttonTheme.colors.error;
			borderWidth = 1;
			shadow = undefined;
			textColor = isDisabled ? buttonTheme.colors.textDisabled : buttonTheme.colors.error;
			break;
		case "outline":
			backgroundColor = isDisabled ? buttonTheme.colors.buttonOutlineBackgroundDisabled : buttonTheme.colors.buttonOutlineBackground;
			borderColor = isDisabled ? buttonTheme.colors.buttonOutlineBorderDisabled : buttonTheme.colors.buttonOutlineBorder;
			borderWidth = 1;
			shadow = undefined;
			textColor = isDisabled
				? isLightAppearance
					? buttonTheme.colors.borderMuted
					: buttonTheme.colors.textDisabled
				: isLightAppearance
					? buttonTheme.colors.surface
					: buttonTheme.colors.text;
			break;
		case "white":
			backgroundColor = isDisabled ? buttonTheme.colors.surfaceDisabled : buttonTheme.colors.surface;
			borderColor = buttonTheme.colors.borderMuted;
			borderWidth = 1;
			shadow = isDisabled ? undefined : buttonTheme.shadows.md;
			textColor = isDisabled ? buttonTheme.colors.textDisabled : buttonTheme.colors.text;
			break;
	}

	if (!isDisabled) {
		switch (variant) {
			case "outline":
				pressedStyle = {
					backgroundColor: buttonTheme.colors.buttonOutlineBackgroundPressed,
					borderColor: buttonTheme.colors.buttonOutlineBorderPressed,
				};
				break;
			case "primary":
				pressedStyle = { backgroundColor: buttonTheme.colors.primaryPressed };
				break;
			case "surface":
				pressedStyle = { backgroundColor: buttonTheme.colors.surfaceMuted };
				break;
			case "danger":
				pressedStyle = { backgroundColor: buttonTheme.colors.errorSurface };
				break;
			case "dangerOutline":
				pressedStyle = { backgroundColor: buttonTheme.colors.errorSurface };
				break;
			case "white":
			case "text":
				pressedStyle = { backgroundColor: buttonTheme.colors.backgroundMuted };
				break;
		}
	}

	return {
		backgroundColor,
		borderColor,
		borderRadius: buttonTheme.radius[sizeConfig.borderRadius],
		borderWidth,
		isBorderlessVariant,
		isLinkVariant,
		minHeight: sizeConfig.minHeight,
		minWidth: sizeConfig.minWidth,
		paddingHorizontal: buttonTheme.spacing[sizeConfig.paddingHorizontal],
		paddingVertical: buttonTheme.spacing[sizeConfig.paddingVertical],
		pressedStyle,
		shadow,
		textColor,
	};
}

const useStyles = createStyles(() => ({
	base: {
		alignItems: "center",
		justifyContent: "center",
	},
	flex: {
		flex: 1,
	},
	pressed: {
		opacity: 0.96,
		transform: [{ scale: 0.985 }],
	},
}));
