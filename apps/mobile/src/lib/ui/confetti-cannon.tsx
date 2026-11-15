import { useEffect, useRef } from "react";
import { Animated, Easing, useWindowDimensions } from "react-native";
import { useTheme } from "@/lib/theme/hooks";
import { View } from "@/lib/ui/view";

const CONFETTI_PARTICLES = [
	{ color: "primary", delay: 0, drift: -210, height: 10, originX: "50%", peak: 0.62, rotation: 260, width: 5 },
	{ color: "accent", delay: 30, drift: 180, height: 7, originX: "50%", peak: 0.52, rotation: 180, width: 9 },
	{ color: "success", delay: 60, drift: -135, height: 11, originX: "50%", peak: 0.7, rotation: 310, width: 5 },
	{ color: "warning", delay: 90, drift: 240, height: 8, originX: "50%", peak: 0.58, rotation: 220, width: 7 },
	{ color: "info", delay: 120, drift: -75, height: 10, originX: "50%", peak: 0.78, rotation: 340, width: 5 },
	{ color: "primary", delay: 150, drift: 95, height: 7, originX: "50%", peak: 0.66, rotation: 160, width: 9 },
	{ color: "success", delay: 180, drift: -270, height: 10, originX: "50%", peak: 0.48, rotation: 280, width: 5 },
	{ color: "accent", delay: 210, drift: 285, height: 8, originX: "50%", peak: 0.44, rotation: 240, width: 7 },
	{ color: "warning", delay: 240, drift: -175, height: 7, originX: "50%", peak: 0.84, rotation: 190, width: 9 },
	{ color: "info", delay: 20, drift: 145, height: 9, originX: "50%", peak: 0.74, rotation: 320, width: 5 },
	{ color: "success", delay: 50, drift: -230, height: 6, originX: "50%", peak: 0.55, rotation: 150, width: 8 },
	{ color: "warning", delay: 80, drift: 220, height: 10, originX: "50%", peak: 0.68, rotation: 275, width: 5 },
	{ color: "primary", delay: 110, drift: -105, height: 7, originX: "50%", peak: 0.9, rotation: 205, width: 9 },
	{ color: "accent", delay: 140, drift: 260, height: 11, originX: "50%", peak: 0.5, rotation: 335, width: 5 },
	{ color: "info", delay: 170, drift: -310, height: 8, originX: "50%", peak: 0.4, rotation: 175, width: 7 },
	{ color: "success", delay: 200, drift: 115, height: 6, originX: "50%", peak: 0.82, rotation: 295, width: 9 },
	{ color: "warning", delay: 230, drift: -250, height: 10, originX: "50%", peak: 0.64, rotation: 230, width: 5 },
	{ color: "primary", delay: 260, drift: 305, height: 7, originX: "50%", peak: 0.46, rotation: 185, width: 8 },
	{ color: "accent", delay: 290, drift: -155, height: 9, originX: "50%", peak: 0.76, rotation: 315, width: 5 },
	{ color: "info", delay: 320, drift: 200, height: 8, originX: "50%", peak: 0.6, rotation: 250, width: 7 },
	{ color: "primary", delay: 350, drift: -185, height: 6, originX: "50%", peak: 0.72, rotation: 145, width: 8 },
	{ color: "success", delay: 380, drift: 155, height: 9, originX: "50%", peak: 0.58, rotation: 290, width: 5 },
	{ color: "warning", delay: 410, drift: -295, height: 8, originX: "50%", peak: 0.5, rotation: 215, width: 7 },
	{ color: "accent", delay: 440, drift: 275, height: 11, originX: "50%", peak: 0.42, rotation: 325, width: 5 },
	{ color: "info", delay: 470, drift: -120, height: 7, originX: "50%", peak: 0.86, rotation: 195, width: 9 },
	{ color: "primary", delay: 500, drift: 235, height: 10, originX: "50%", peak: 0.63, rotation: 270, width: 5 },
	{ color: "success", delay: 530, drift: -265, height: 6, originX: "50%", peak: 0.77, rotation: 175, width: 8 },
	{ color: "warning", delay: 560, drift: 130, height: 9, originX: "50%", peak: 0.91, rotation: 345, width: 5 },
	{ color: "accent", delay: 590, drift: -220, height: 8, originX: "50%", peak: 0.57, rotation: 230, width: 7 },
	{ color: "info", delay: 620, drift: 310, height: 7, originX: "50%", peak: 0.47, rotation: 185, width: 9 },
	{ color: "primary", delay: 650, drift: -150, height: 10, originX: "50%", peak: 0.69, rotation: 305, width: 5 },
	{ color: "success", delay: 680, drift: 195, height: 6, originX: "50%", peak: 0.82, rotation: 155, width: 8 },
	{ color: "warning", delay: 710, drift: -325, height: 9, originX: "50%", peak: 0.39, rotation: 265, width: 5 },
	{ color: "accent", delay: 740, drift: 250, height: 8, originX: "50%", peak: 0.74, rotation: 335, width: 7 },
	{ color: "info", delay: 770, drift: -90, height: 11, originX: "50%", peak: 0.88, rotation: 205, width: 5 },
	{ color: "primary", delay: 800, drift: 285, height: 7, originX: "50%", peak: 0.53, rotation: 290, width: 9 },
	{ color: "success", delay: 830, drift: -240, height: 10, originX: "50%", peak: 0.66, rotation: 170, width: 5 },
	{ color: "warning", delay: 860, drift: 105, height: 6, originX: "50%", peak: 0.8, rotation: 250, width: 8 },
	{ color: "accent", delay: 890, drift: -280, height: 9, originX: "50%", peak: 0.61, rotation: 320, width: 5 },
	{ color: "primary", delay: 140, drift: -340, height: 13, originX: "50%", peak: 0.43, rotation: 280, width: 7 },
	{ color: "success", delay: 175, drift: 320, height: 10, originX: "50%", peak: 0.55, rotation: 190, width: 11 },
	{ color: "warning", delay: 205, drift: -190, height: 14, originX: "50%", peak: 0.73, rotation: 350, width: 7 },
	{ color: "accent", delay: 235, drift: 205, height: 11, originX: "50%", peak: 0.65, rotation: 225, width: 10 },
	{ color: "info", delay: 265, drift: -315, height: 12, originX: "50%", peak: 0.48, rotation: 165, width: 8 },
	{ color: "primary", delay: 295, drift: 295, height: 10, originX: "50%", peak: 0.8, rotation: 305, width: 12 },
	{ color: "success", delay: 325, drift: -145, height: 15, originX: "50%", peak: 0.58, rotation: 245, width: 8 },
	{ color: "warning", delay: 355, drift: 175, height: 12, originX: "50%", peak: 0.9, rotation: 315, width: 10 },
	{ color: "accent", delay: 385, drift: -275, height: 11, originX: "50%", peak: 0.69, rotation: 205, width: 7 },
	{ color: "info", delay: 415, drift: 345, height: 14, originX: "50%", peak: 0.4, rotation: 270, width: 9 },
	{ color: "primary", delay: 445, drift: -225, height: 10, originX: "50%", peak: 0.83, rotation: 185, width: 12 },
	{ color: "success", delay: 475, drift: 265, height: 13, originX: "50%", peak: 0.52, rotation: 335, width: 7 },
	{ color: "warning", delay: 505, drift: -105, height: 11, originX: "50%", peak: 0.76, rotation: 230, width: 10 },
	{ color: "accent", delay: 535, drift: 115, height: 15, originX: "50%", peak: 0.62, rotation: 295, width: 8 },
	{ color: "info", delay: 565, drift: -355, height: 12, originX: "50%", peak: 0.46, rotation: 155, width: 11 },
	{ color: "primary", delay: 595, drift: 225, height: 10, originX: "50%", peak: 0.87, rotation: 320, width: 7 },
	{ color: "success", delay: 625, drift: -165, height: 13, originX: "50%", peak: 0.67, rotation: 215, width: 10 },
	{ color: "warning", delay: 655, drift: 340, height: 11, originX: "50%", peak: 0.57, rotation: 275, width: 8 },
	{ color: "accent", delay: 685, drift: -305, height: 14, originX: "50%", peak: 0.71, rotation: 345, width: 9 },
] as const;

type ConfettiCannonProps = {
	trigger?: string | number;
};

export function ConfettiCannon({ trigger }: ConfettiCannonProps) {
	const theme = useTheme();
	const { height } = useWindowDimensions();
	const confettiProgress = useRef(CONFETTI_PARTICLES.map(() => new Animated.Value(0))).current;

	useEffect(() => {
		if (trigger === undefined) {
			return;
		}

		const animation = Animated.parallel(
			confettiProgress.map((progress, index) => {
				progress.setValue(0);

				return Animated.timing(progress, {
					toValue: 1,
					duration: 3000,
					delay: CONFETTI_PARTICLES[index].delay,
					easing: Easing.out(Easing.cubic),
					useNativeDriver: true,
				});
			}),
		);

		animation.start();

		return () => animation.stop();
	}, [confettiProgress, trigger]);

	if (trigger === undefined) {
		return null;
	}

	return (
		<View pointerEvents="none" style={{ bottom: 0, left: 0, overflow: "hidden", position: "absolute", right: 0, top: 0 }}>
			{CONFETTI_PARTICLES.map((particle, index) => {
				const progress = confettiProgress[index];

				return (
					<Animated.View
						key={`${particle.delay}-${particle.drift}`}
						style={{
							backgroundColor: theme.colors[particle.color],
							borderRadius: 3,
							height: particle.height * 1.35,
							left: particle.originX,
							opacity: progress.interpolate({
								inputRange: [0, 0.04, 0.86, 1],
								outputRange: [0, 1, 1, 0],
							}),
							position: "absolute",
							top: height - 112,
							transform: [
								{
									translateY: progress.interpolate({
										inputRange: [0, 0.38, 1],
										outputRange: [0, -height * particle.peak, height * 0.28],
									}),
								},
								{
									translateX: progress.interpolate({
										inputRange: [0, 0.38, 1],
										outputRange: [0, particle.drift, particle.drift * 1.2],
									}),
								},
								{
									rotate: progress.interpolate({ inputRange: [0, 1], outputRange: ["0deg", `${particle.rotation}deg`] }),
								},
								{
									scale: progress.interpolate({ inputRange: [0, 0.1, 1], outputRange: [0.4, 1, 0.85] }),
								},
							],
							width: particle.width * 1.35,
						}}
					/>
				);
			})}
		</View>
	);
}
