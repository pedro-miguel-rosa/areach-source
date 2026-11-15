import type { ReactNode } from "react";
import { useEffect, useRef } from "react";
import { Animated, Easing, type ImageSourcePropType, StyleSheet, View } from "react-native";

type AnimatedWelcomeBackgroundProps = {
	children: ReactNode;
	source: ImageSourcePropType;
};

export function AnimatedWelcomeBackground(props: AnimatedWelcomeBackgroundProps) {
	const { children, source } = props;
	const primarySway = useRef(new Animated.Value(0)).current;
	const secondarySway = useRef(new Animated.Value(0)).current;

	useEffect(() => {
		const primaryAnimation = Animated.loop(
			Animated.sequence([
				Animated.timing(primarySway, {
					toValue: 1,
					duration: 5400,
					easing: Easing.inOut(Easing.sin),
					useNativeDriver: true,
				}),
				Animated.timing(primarySway, {
					toValue: 0,
					duration: 6600,
					easing: Easing.inOut(Easing.sin),
					useNativeDriver: true,
				}),
			]),
		);
		const secondaryAnimation = Animated.loop(
			Animated.sequence([
				Animated.timing(secondarySway, {
					toValue: 1,
					duration: 7200,
					easing: Easing.inOut(Easing.sin),
					useNativeDriver: true,
				}),
				Animated.timing(secondarySway, {
					toValue: 0,
					duration: 6000,
					easing: Easing.inOut(Easing.sin),
					useNativeDriver: true,
				}),
			]),
		);

		primaryAnimation.start();
		secondaryAnimation.start();

		return () => {
			primaryAnimation.stop();
			secondaryAnimation.stop();
		};
	}, [primarySway, secondarySway]);

	const primaryLayerStyle = {
		transform: [
			{ scale: primarySway.interpolate({ inputRange: [0, 0.5, 1], outputRange: [1.1, 1.14, 1.1] }) },
			{ translateX: primarySway.interpolate({ inputRange: [0, 1], outputRange: [-18, 20] }) },
			{ translateY: primarySway.interpolate({ inputRange: [0, 1], outputRange: [12, -14] }) },
			{ rotate: primarySway.interpolate({ inputRange: [0, 1], outputRange: ["-1.3deg", "1.3deg"] }) },
		],
	};
	const nearLeavesLayerStyle = {
		opacity: secondarySway.interpolate({ inputRange: [0, 0.5, 1], outputRange: [0.16, 0.3, 0.2] }),
		transform: [
			{ scale: 1.18 },
			{ translateX: secondarySway.interpolate({ inputRange: [0, 1], outputRange: [28, -28] }) },
			{ translateY: secondarySway.interpolate({ inputRange: [0, 1], outputRange: [-18, 20] }) },
			{ rotate: secondarySway.interpolate({ inputRange: [0, 1], outputRange: ["1.6deg", "-1.6deg"] }) },
		],
	};
	const farLeavesLayerStyle = {
		opacity: primarySway.interpolate({ inputRange: [0, 0.5, 1], outputRange: [0.1, 0.2, 0.12] }),
		transform: [
			{ scale: 1.28 },
			{ translateX: primarySway.interpolate({ inputRange: [0, 1], outputRange: [-34, 32] }) },
			{ translateY: secondarySway.interpolate({ inputRange: [0, 1], outputRange: [22, -24] }) },
			{ rotate: primarySway.interpolate({ inputRange: [0, 1], outputRange: ["-2deg", "2deg"] }) },
		],
	};

	return (
		<View style={styles.background}>
			<View pointerEvents="none" style={styles.canopyLayer}>
				<Animated.Image resizeMode="cover" source={source} style={[styles.canopyImage, primaryLayerStyle]} />
			</View>
			<View pointerEvents="none" style={styles.canopyLayer}>
				<Animated.Image blurRadius={12} resizeMode="cover" source={source} style={[styles.canopyImage, nearLeavesLayerStyle]} />
			</View>
			<View pointerEvents="none" style={styles.canopyLayer}>
				<Animated.Image blurRadius={20} resizeMode="cover" source={source} style={[styles.canopyImage, farLeavesLayerStyle]} />
			</View>
			<View style={styles.content}>{children}</View>
		</View>
	);
}

const styles = StyleSheet.create({
	background: {
		flex: 1,
		backgroundColor: "#06130d",
		overflow: "hidden",
	},
	canopyLayer: {
		bottom: -56,
		left: -56,
		position: "absolute",
		right: -56,
		top: -56,
	},
	canopyImage: {
		height: "100%",
		width: "100%",
	},
	content: {
		flex: 1,
	},
});
