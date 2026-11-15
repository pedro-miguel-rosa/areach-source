import { useEffect, useRef, useState } from "react";
import { Animated, Easing, Pressable, TextInput as RNTextInput } from "react-native";
import { createStyles } from "@/lib/theme/factories";
import { Text } from "@/lib/ui/text";
import { View } from "@/lib/ui/view";

export type CodeInputProps = {
	length: number;
	onChange: (value: string) => void;
	value: string;
	accessibilityLabel?: string;
};

export function CodeInput(props: CodeInputProps) {
	const { accessibilityLabel = "Code input", length, onChange, value } = props;
	const { styles } = useStyles();
	const inputRef = useRef<RNTextInput>(null);
	const [isFocused, setIsFocused] = useState(false);
	const cursorOpacity = useRef(new Animated.Value(1)).current;
	const activeIndex = Math.min(value.length, length - 1);
	const boxes = Array.from({ length }, (_, index) => ({
		character: value[index] ?? "",
		id: `code-box-${index + 1}`,
		isActive: isFocused && index === activeIndex,
	}));

	useEffect(() => {
		if (!isFocused) {
			cursorOpacity.setValue(0);
			return;
		}

		cursorOpacity.setValue(1);
		const animation = Animated.loop(
			Animated.sequence([
				Animated.timing(cursorOpacity, {
					toValue: 0,
					duration: 500,
					easing: Easing.linear,
					useNativeDriver: true,
				}),
				Animated.timing(cursorOpacity, {
					toValue: 1,
					duration: 500,
					easing: Easing.linear,
					useNativeDriver: true,
				}),
			]),
		);

		animation.start();

		return () => {
			animation.stop();
		};
	}, [cursorOpacity, isFocused]);

	return (
		<Pressable
			accessibilityLabel={accessibilityLabel}
			accessibilityRole="button"
			onPress={() => inputRef.current?.focus()}
			style={styles.codeInputWrap}
		>
			{boxes.map(({ character, id, isActive }) => (
				<View key={id} style={[styles.codeBox, character && styles.codeBoxFilled, isActive && styles.codeBoxFocused]}>
					<Text align="center" size="lg" weight="bold">
						{character}
					</Text>
					{isActive && !character ? <Animated.View pointerEvents="none" style={[styles.cursor, { opacity: cursorOpacity }]} /> : null}
				</View>
			))}
			<RNTextInput
				autoCapitalize="characters"
				autoCorrect={false}
				keyboardType="ascii-capable"
				maxLength={length}
				onChangeText={onChange}
				ref={inputRef}
				returnKeyType="done"
				style={styles.hiddenCodeInput}
				value={value}
				onBlur={() => setIsFocused(false)}
				onFocus={() => setIsFocused(true)}
			/>
		</Pressable>
	);
}

const useStyles = createStyles((theme) => ({
	codeBox: {
		alignItems: "center",
		backgroundColor: theme.colors.inputSurface,
		borderColor: theme.colors.border,
		borderRadius: theme.radius.md,
		borderWidth: 1,
		flex: 1,
		minWidth: 0,
		height: 56,
		justifyContent: "center",
		...theme.shadows.xs,
	},
	codeBoxFilled: {
		borderColor: theme.colors.borderFocus,
	},
	codeBoxFocused: {
		borderColor: theme.colors.borderFocus,
		borderWidth: 2,
	},
	cursor: {
		backgroundColor: theme.colors.borderFocus,
		height: 28,
		left: "50%",
		position: "absolute",
		top: 14,
		transform: [{ translateX: -1 }],
		width: 2,
	},
	codeInputWrap: {
		alignItems: "center",
		flexDirection: "row",
		gap: theme.spacing.sm,
		justifyContent: "center",
		position: "relative",
		width: "100%",
	},
	hiddenCodeInput: {
		height: 1,
		opacity: 0,
		position: "absolute",
		width: 1,
	},
}));
