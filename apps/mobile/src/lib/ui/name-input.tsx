import { useTheme } from "@/lib/theme/hooks";
import { Icon } from "@/lib/ui/icon";
import { TextInput, type TextInputProps } from "@/lib/ui/text-input";

export type NameInputProps = {
	defaultValue?: string;
	error?: string;
	label?: string;
	onBlur?: TextInputProps["onBlur"];
	onChange?: (value: string) => void;
	placeholder?: string;
	value?: string;
};

export function NameInput(props: NameInputProps) {
	const theme = useTheme();
	const iconColor = props.error ? theme.colors.error : theme.colors.textSecondary;

	return (
		<TextInput
			{...props}
			leftSection={<Icon color={iconColor} name="user" size={19} />}
			autoCapitalize="words"
			autoComplete="name"
			textContentType="name"
		/>
	);
}
