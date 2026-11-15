import type { ReactNode } from "react";
import { Text as RNText, View } from "react-native";
import { createStyles } from "@/lib/theme/factories";
import { type InputProps as BaseInputProps, Input } from "@/lib/ui/input";

export type TextInputProps = {
	autoCapitalize?: BaseInputProps["autoCapitalize"];
	autoComplete?: BaseInputProps["autoComplete"];
	autoCorrect?: BaseInputProps["autoCorrect"];
	autoFocus?: BaseInputProps["autoFocus"];
	defaultValue?: BaseInputProps["defaultValue"];
	editable?: BaseInputProps["editable"];
	error?: string;
	keyboardType?: BaseInputProps["keyboardType"];
	leftSection?: ReactNode;
	label?: string;
	maxLength?: BaseInputProps["maxLength"];
	multiline?: BaseInputProps["multiline"];
	numberOfLines?: BaseInputProps["numberOfLines"];
	onBlur?: BaseInputProps["onBlur"];
	onChange?: BaseInputProps["onChange"];
	onFocus?: BaseInputProps["onFocus"];
	onSubmitEditing?: BaseInputProps["onSubmitEditing"];
	placeholder?: BaseInputProps["placeholder"];
	returnKeyType?: BaseInputProps["returnKeyType"];
	secureTextEntry?: BaseInputProps["secureTextEntry"];
	textAlignVertical?: BaseInputProps["textAlignVertical"];
	textContentType?: BaseInputProps["textContentType"];
	rightSection?: ReactNode;
	invalid?: boolean;
	value?: BaseInputProps["value"];
};

export function TextInput(props: TextInputProps) {
	const { error, invalid, label, leftSection, rightSection, ...inputProps } = props;
	const { styles } = useStyles();

	return (
		<View>
			{label ? <RNText style={styles.label}>{label}</RNText> : null}
			<Input {...inputProps} invalid={invalid ?? Boolean(error)} leftSection={leftSection} rightSection={rightSection} />
			{error ? <RNText style={styles.error}>{error}</RNText> : null}
		</View>
	);
}

const useStyles = createStyles((theme) => {
	const fieldText = {
		fontSize: theme.typography.size.sm,
		lineHeight: theme.typography.lineHeight.xs,
	};

	return {
		error: {
			...fieldText,
			fontWeight: theme.typography.weight.regular,
			color: theme.colors.error,
			marginTop: theme.spacing.xs,
		},
		label: {
			...fieldText,
			fontWeight: theme.typography.weight.semibold,
			color: theme.colors.textSecondary,
			marginBottom: theme.spacing.xs,
		},
	};
});
