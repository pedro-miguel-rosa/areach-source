import { useLayoutEffect, useRef, useState } from "react";
import { Animated, Easing, Pressable } from "react-native";
import { createStyles } from "@/lib/theme/factories";
import { Text } from "@/lib/ui/text";
import { View } from "@/lib/ui/view";

export type SegmentedControlOption = {
	label: string;
	value: string;
};

export type SegmentedControlProps = {
	onChange: (value: string) => void;
	options: Array<SegmentedControlOption>;
	value: string;
};

export function SegmentedControl(props: SegmentedControlProps) {
	const { onChange, options, value } = props;
	const { styles, theme } = useStyles();
	const [controlWidth, setControlWidth] = useState(0);
	const translateX = useRef(new Animated.Value(0)).current;
	const indicatorScale = useRef(new Animated.Value(1)).current;
	const selectedIndex = Math.max(
		options.findIndex((option) => option.value === value),
		0,
	);

	const segmentWidth = options.length > 0 ? controlWidth / options.length : 0;
	const hasMeasuredRef = useRef(false);

	useLayoutEffect(() => {
		if (segmentWidth <= 0) {
			return;
		}

		const nextTranslateX = selectedIndex * segmentWidth;

		if (!hasMeasuredRef.current) {
			translateX.setValue(nextTranslateX);
			hasMeasuredRef.current = true;
			return;
		}

		const animation = Animated.parallel([
			Animated.spring(translateX, {
				toValue: nextTranslateX,
				damping: 22,
				mass: 0.75,
				overshootClamping: true,
				stiffness: 260,
				useNativeDriver: true,
			}),
			Animated.sequence([
				Animated.timing(indicatorScale, {
					toValue: 0.985,
					duration: 70,
					easing: Easing.out(Easing.quad),
					useNativeDriver: true,
				}),
				Animated.spring(indicatorScale, {
					toValue: 1,
					damping: 18,
					mass: 0.7,
					overshootClamping: true,
					stiffness: 280,
					useNativeDriver: true,
				}),
			]),
		]);

		animation.start();

		return () => {
			animation.stop();
		};
	}, [indicatorScale, selectedIndex, segmentWidth, translateX]);

	return (
		<View
			onLayout={(event) => {
				setControlWidth(event.nativeEvent.layout.width);
			}}
			style={styles.segmentedControl}
		>
			<Animated.View
				pointerEvents="none"
				style={[
					styles.indicator,
					{
						opacity: segmentWidth > 0 ? 1 : 0,
						transform: [{ translateX }, { scale: indicatorScale }],
						width: segmentWidth,
					},
				]}
			/>
			{options.map((option) => {
				const isSelected = option.value === value;

				return (
					<Pressable
						accessibilityRole="button"
						accessibilityState={{ selected: isSelected }}
						key={option.value}
						onPress={() => onChange(option.value)}
						style={({ pressed }) => [styles.segment, pressed && styles.segmentPressed]}
					>
						<Text align="center" color={isSelected ? theme.colors.textOnPrimary : theme.colors.text} size="sm" weight="semibold">
							{option.label}
						</Text>
					</Pressable>
				);
			})}
		</View>
	);
}

const useStyles = createStyles((theme) => ({
	segment: {
		alignItems: "center",
		borderRadius: theme.radius.md,
		flex: 1,
		justifyContent: "center",
		flexShrink: 0,
		minHeight: 44,
		paddingHorizontal: theme.spacing.md,
	},
	segmentPressed: {
		opacity: 0.9,
		transform: [{ scale: 0.985 }],
	},
	segmentedControl: {
		backgroundColor: theme.colors.surfaceMuted,
		borderRadius: theme.radius.lg,
		flexDirection: "row",
		overflow: "hidden",
		width: "100%",
		position: "relative",
	},
	indicator: {
		...theme.shadows.sm,
		backgroundColor: theme.colors.primary,
		borderRadius: theme.radius.md,
		bottom: 0,
		left: 0,
		position: "absolute",
		top: 0,
	},
}));
