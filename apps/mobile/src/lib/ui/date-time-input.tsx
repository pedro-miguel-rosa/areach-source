import DateTimePicker from "@expo/ui/community/datetime-picker";
import { useEffect, useRef, useState } from "react";
import { Animated, Easing, Modal, Pressable } from "react-native";
import { createStyles } from "@/lib/theme/factories";
import { Button } from "@/lib/ui/button";
import { Text } from "@/lib/ui/text";
import { View } from "@/lib/ui/view";

const FLOAT_LABEL_DURATION_MS = 160;
const MODAL_OPEN_BACKDROP_DURATION_MS = 260;
const MODAL_OPEN_SHEET_DURATION_MS = 380;
const MODAL_CLOSE_BACKDROP_DURATION_MS = 180;
const MODAL_CLOSE_SHEET_DURATION_MS = 260;
const PHONE_SHEET_HIDDEN_OFFSET = 480;
const LABEL_RESTING_TOP = 14;
const LABEL_FLOATING_TOP = -10;

type DateTimeInputProps = {
	label: string;
	minimumDate?: Date;
	mode: "date" | "time";
	onChange: (value: Date) => void;
	renderValue: (value: Date) => string;
	title: string;
	value: Date;
};

export function DateTimeInput(props: DateTimeInputProps) {
	const { label, minimumDate, mode, onChange, renderValue, title, value } = props;

	const [open, setOpen] = useState(false);
	const [isVisible, setIsVisible] = useState(false);

	const { styles, theme } = useFieldStyles();
	const { styles: modalStyles, theme: modalTheme } = useModalStyles();
	const isDateMode = mode === "date";
	const hasValue = value != null;
	const isLabelFloating = open || hasValue;
	const labelAnimation = useRef(new Animated.Value(isLabelFloating ? 1 : 0)).current;
	const modalOpacity = useRef(new Animated.Value(0)).current;
	const sheetProgress = useRef(new Animated.Value(0)).current;

	useEffect(() => {
		Animated.timing(labelAnimation, {
			toValue: isLabelFloating ? 1 : 0,
			duration: FLOAT_LABEL_DURATION_MS,
			easing: Easing.out(Easing.ease),
			useNativeDriver: false,
		}).start();
	}, [isLabelFloating, labelAnimation]);

	useEffect(() => {
		if (open) {
			setIsVisible(true);

			animateModal({
				backdropDuration: MODAL_OPEN_BACKDROP_DURATION_MS,
				backdropOpacity: modalOpacity,
				backdropToValue: 1,
				sheetDuration: MODAL_OPEN_SHEET_DURATION_MS,
				sheetEasing: Easing.out(Easing.quad),
				sheetProgress,
				sheetToValue: 1,
			}).start();

			return;
		}

		animateModal({
			backdropDuration: MODAL_CLOSE_BACKDROP_DURATION_MS,
			backdropOpacity: modalOpacity,
			backdropToValue: 0,
			sheetDuration: MODAL_CLOSE_SHEET_DURATION_MS,
			sheetEasing: Easing.in(Easing.quad),
			sheetProgress,
			sheetToValue: 0,
		}).start(({ finished }) => {
			if (finished) {
				setIsVisible(false);
			}
		});
	}, [modalOpacity, open, sheetProgress]);

	const animatedLabelStyle = getAnimatedLabelStyle(labelAnimation, theme);
	const labelColor = open ? theme.colors.textLink : hasValue ? theme.colors.textSecondary : theme.colors.textMuted;
	const sheetAnimatedStyle = {
		transform: [
			{
				translateY: sheetProgress.interpolate({
					inputRange: [0, 1],
					outputRange: [PHONE_SHEET_HIDDEN_OFFSET, 0],
				}),
			},
		],
	};

	return (
		<>
			<View style={[styles.fieldContainer, open && styles.fieldContainerFocused]}>
				<Animated.Text pointerEvents="none" style={[styles.label, { color: labelColor }, animatedLabelStyle]}>
					{label}
				</Animated.Text>
				<Pressable onPress={handleOpen} style={({ pressed }) => [styles.field, pressed && styles.fieldPressed]}>
					<Text color={theme.colors.text}>{renderValue(value)}</Text>
				</Pressable>
			</View>

			{isVisible ? (
				<Modal animationType="none" onRequestClose={handleClose} transparent visible={isVisible}>
					<View style={modalStyles.overlay}>
						<Animated.View pointerEvents="none" style={[modalStyles.backdrop, { opacity: modalOpacity }]} />
						<Pressable onPress={handleClose} style={modalStyles.backdropPressTarget} />
						<Animated.View style={[modalStyles.sheet, sheetAnimatedStyle]}>
							<View style={modalStyles.sheetHeader}>
								<Text size="lg" weight="bold">
									{title}
								</Text>
								<Button onPress={handleClose} size="sm" variant="text">
									Done
								</Button>
							</View>

							<View style={[modalStyles.pickerSurface, isDateMode && modalStyles.pickerSurfaceDate]}>
								<DateTimePicker
									accentColor={modalTheme.colors.primary}
									display="spinner"
									minimumDate={minimumDate}
									mode={mode}
									onValueChange={(_, selectedDate) => {
										onChange(selectedDate);
									}}
									style={[modalStyles.picker, isDateMode && modalStyles.pickerDate]}
									value={value}
								/>
							</View>
						</Animated.View>
					</View>
				</Modal>
			) : null}
		</>
	);

	function handleOpen() {
		setOpen(true);
	}

	function handleClose() {
		setOpen(false);
	}
}

function animateModal(params: {
	backdropDuration: number;
	backdropOpacity: Animated.Value;
	backdropToValue: number;
	sheetDuration: number;
	sheetEasing: (value: number) => number;
	sheetProgress: Animated.Value;
	sheetToValue: number;
}) {
	const { backdropDuration, backdropOpacity, backdropToValue, sheetDuration, sheetEasing, sheetProgress, sheetToValue } = params;

	return Animated.parallel([
		Animated.timing(backdropOpacity, {
			toValue: backdropToValue,
			duration: backdropDuration,
			easing: Easing.out(Easing.ease),
			useNativeDriver: true,
		}),
		Animated.timing(sheetProgress, {
			toValue: sheetToValue,
			duration: sheetDuration,
			easing: sheetEasing,
			useNativeDriver: true,
		}),
	]);
}

function getAnimatedLabelStyle(labelAnimation: Animated.Value, theme: ReturnType<typeof useFieldStyles>["theme"]) {
	return {
		fontSize: labelAnimation.interpolate({
			inputRange: [0, 1],
			outputRange: [theme.typography.size.md, theme.typography.size.xs],
		}),
		lineHeight: labelAnimation.interpolate({
			inputRange: [0, 1],
			outputRange: [theme.typography.lineHeight.md, theme.typography.lineHeight.xs],
		}),
		top: labelAnimation.interpolate({
			inputRange: [0, 1],
			outputRange: [LABEL_RESTING_TOP, LABEL_FLOATING_TOP],
		}),
	};
}

const useFieldStyles = createStyles((theme) => ({
	fieldContainer: {
		borderWidth: 1,
		borderColor: theme.colors.border,
		borderRadius: theme.radius.lg,
		backgroundColor: theme.colors.surface,
		minHeight: 56,
		position: "relative",
		overflow: "visible",
	},
	fieldContainerFocused: {
		borderColor: theme.colors.borderFocus,
	},
	field: {
		paddingHorizontal: theme.spacing.md,
		paddingTop: theme.spacing.md,
		paddingBottom: theme.spacing.md,
		minHeight: 56,
		justifyContent: "center",
	},
	fieldPressed: {
		opacity: 0.9,
	},
	label: {
		position: "absolute",
		left: theme.spacing.md - 4,
		zIndex: 1,
		paddingHorizontal: 4,
		borderRadius: theme.radius.full,
		backgroundColor: theme.colors.surface,
	},
}));

const useModalStyles = createStyles((theme) => ({
	overlay: {
		flex: 1,
		justifyContent: "flex-end",
	},
	backdrop: {
		position: "absolute",
		top: 0,
		right: 0,
		bottom: 0,
		left: 0,
		backgroundColor: theme.colors.backdrop,
	},
	backdropPressTarget: {
		position: "absolute",
		top: 0,
		right: 0,
		bottom: 0,
		left: 0,
	},
	sheet: {
		borderTopLeftRadius: 28,
		borderTopRightRadius: 28,
		backgroundColor: theme.colors.surface,
		paddingTop: theme.spacing.lg,
		paddingHorizontal: theme.spacing.lg,
		paddingBottom: theme.spacing.xl,
		gap: theme.spacing.md,
	},
	sheetHeader: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "space-between",
	},
	pickerSurface: {
		borderRadius: 20,
		backgroundColor: theme.colors.surface,
		paddingHorizontal: theme.spacing.sm,
		paddingVertical: theme.spacing.xs,
		overflow: "hidden",
	},
	pickerSurfaceDate: {
		paddingVertical: theme.spacing.sm,
	},
	picker: {
		alignSelf: "stretch",
	},
	pickerDate: {
		minHeight: 216,
	},
}));
