import { useTheme } from "@/lib/theme/hooks";
import { Icon } from "@/lib/ui/icon";
import { TextInput, type TextInputProps } from "@/lib/ui/text-input";

export type EmailInputProps = {
	defaultValue?: string;
	error?: string;
	label?: string;
	onBlur?: TextInputProps["onBlur"];
	onChange?: (value: string) => void;
	placeholder?: string;
	value?: string;
};

export function EmailInput(props: EmailInputProps) {
	const theme = useTheme();
	const iconColor = props.error ? theme.colors.error : theme.colors.textSecondary;

	return (
		<TextInput
			{...props}
			leftSection={<Icon color={iconColor} name="mail" size={19} />}
			autoCapitalize="none"
			autoComplete="email"
			autoCorrect={false}
			keyboardType="email-address"
			textContentType="emailAddress"
		/>
	);
}
