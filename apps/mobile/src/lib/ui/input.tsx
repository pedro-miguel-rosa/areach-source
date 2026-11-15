import { type ReactNode, useState } from "react";
import { TextInput as RNTextInput, type TextInputProps as RNTextInputProps, View } from "react-native";
import { createStyles } from "@/lib/theme/factories";

const INPUT_SHELL_MIN_HEIGHT = 58;
const INPUT_CONTENT_HEIGHT = INPUT_SHELL_MIN_HEIGHT - 2;

export type InputProps = {
	autoCapitalize?: RNTextInputProps["autoCapitalize"];
	autoComplete?: RNTextInputProps["autoComplete"];
	autoCorrect?: RNTextInputProps["autoCorrect"];
	autoFocus?: RNTextInputProps["autoFocus"];
	defaultValue?: RNTextInputProps["defaultValue"];
	editable?: RNTextInputProps["editable"];
	keyboardType?: RNTextInputProps["keyboardType"];
	maxLength?: RNTextInputProps["maxLength"];
	multiline?: RNTextInputProps["multiline"];
	numberOfLines?: RNTextInputProps["numberOfLines"];
	onBlur?: RNTextInputProps["onBlur"];
	onChange?: RNTextInputProps["onChangeText"];
	onFocus?: RNTextInputProps["onFocus"];
	onSubmitEditing?: RNTextInputProps["onSubmitEditing"];
	placeholder?: RNTextInputProps["placeholder"];
	returnKeyType?: RNTextInputProps["returnKeyType"];
	secureTextEntry?: RNTextInputProps["secureTextEntry"];
	textAlignVertical?: RNTextInputProps["textAlignVertical"];
	textContentType?: RNTextInputProps["textContentType"];
	value?: RNTextInputProps["value"];
	invalid?: boolean;
	leftSection?: ReactNode;
	rightSection?: ReactNode;
};

export function Input(props: InputProps) {
	const {
		autoCapitalize,
		autoComplete,
		autoCorrect,
		autoFocus,
		defaultValue,
		editable,
		keyboardType,
		maxLength,
		multiline,
		numberOfLines,
		invalid,
		leftSection,
		onBlur,
		onChange,
		onFocus,
		onSubmitEditing,
		placeholder,
		returnKeyType,
		secureTextEntry,
		textAlignVertical,
		textContentType,
		rightSection,
		value,
	} = props;
	const { styles, theme } = useStyles();
	const [isFocused, setIsFocused] = useState(false);
	const isMultiline = Boolean(multiline);
	const resolvedTextAlignVertical = textAlignVertical ?? (isMultiline ? "top" : "center");
	const borderColor = invalid ? theme.colors.error : isFocused ? theme.colors.borderFocus : theme.colors.border;
	const selectionColor = invalid ? theme.colors.error : theme.colors.borderFocus;
	const inputStyles = [styles.input, isMultiline && styles.inputMultiline];

	const handleFocus: NonNullable<RNTextInputProps["onFocus"]> = (event) => {
		setIsFocused(true);
		onFocus?.(event);
	};

	const handleBlur: NonNullable<RNTextInputProps["onBlur"]> = (event) => {
		setIsFocused(false);
		onBlur?.(event);
	};

	const handleChangeText: NonNullable<RNTextInputProps["onChangeText"]> = (text) => {
		onChange?.(text);
	};

	return (
		<View style={[styles.inputShell, isMultiline && styles.inputShellMultiline, { borderColor }]}>
			{leftSection}
			<View style={[styles.inputFrame, isMultiline && styles.inputFrameMultiline]}>
				<RNTextInput
					defaultValue={defaultValue}
					autoCapitalize={autoCapitalize}
					autoComplete={autoComplete}
					autoCorrect={autoCorrect}
					autoFocus={autoFocus}
					editable={editable}
					keyboardType={keyboardType}
					maxLength={maxLength}
					multiline={multiline}
					numberOfLines={numberOfLines}
					placeholder={placeholder}
					placeholderTextColor={theme.colors.textPlaceholder}
					returnKeyType={returnKeyType}
					secureTextEntry={secureTextEntry}
					textContentType={textContentType}
					value={value}
					selectionColor={selectionColor}
					style={inputStyles}
					textAlignVertical={resolvedTextAlignVertical}
					underlineColorAndroid="transparent"
					onBlur={handleBlur}
					onChangeText={handleChangeText}
					onFocus={handleFocus}
					onSubmitEditing={onSubmitEditing}
				/>
			</View>
			{rightSection}
		</View>
	);
}

const useStyles = createStyles((theme) => ({
	input: {
		color: theme.colors.text,
		fontSize: theme.typography.size.md,
		fontWeight: theme.typography.weight.regular,
		height: INPUT_CONTENT_HEIGHT,
		includeFontPadding: false,
		position: "relative",
		zIndex: 2,
		paddingBottom: 0,
		paddingTop: 0,
	},
	inputFrame: {
		flex: 1,
		height: INPUT_CONTENT_HEIGHT,
		justifyContent: "center",
		position: "relative",
	},
	inputFrameMultiline: {
		height: undefined,
		justifyContent: "flex-start",
		minHeight: 112,
	},
	inputMultiline: {
		height: undefined,
		includeFontPadding: true,
		lineHeight: theme.typography.lineHeight.md,
		minHeight: 112,
		paddingVertical: theme.spacing.sm,
	},
	inputShell: {
		alignItems: "center",
		...theme.shadows.xs,
		backgroundColor: theme.colors.inputSurface,
		borderColor: theme.colors.border,
		borderRadius: theme.radius.md,
		borderWidth: 1,
		flexDirection: "row",
		gap: theme.spacing.sm,
		minHeight: INPUT_SHELL_MIN_HEIGHT,
		paddingHorizontal: theme.spacing.md,
	},
	inputShellMultiline: {
		alignItems: "flex-start",
		minHeight: 144,
		paddingVertical: theme.spacing.sm,
	},
}));
