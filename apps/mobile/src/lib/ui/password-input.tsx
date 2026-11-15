import { useState } from "react";
import { Pressable } from "react-native";
import { createStyles } from "@/lib/theme/factories";
import { Icon } from "@/lib/ui/icon";
import { TextInput, type TextInputProps } from "@/lib/ui/text-input";

export type PasswordInputProps = {
	autoComplete?: "password" | "new-password";
	defaultValue?: string;
	error?: string;
	invalid?: boolean;
	label?: string;
	onBlur?: TextInputProps["onBlur"];
	onChange?: (value: string) => void;
	placeholder?: string;
	value?: string;
};

export function PasswordInput(props: PasswordInputProps) {
	const { styles, theme } = useStyles();
	const { autoComplete = "password", error, invalid, ...inputProps } = props;
	const [isPasswordVisible, setIsPasswordVisible] = useState(false);
	const isInvalid = Boolean(error) || Boolean(invalid);
	const iconColor = isInvalid ? theme.colors.error : theme.colors.textSecondary;

	return (
		<TextInput
			{...inputProps}
			error={error}
			invalid={isInvalid}
			leftSection={<Icon color={iconColor} name="lock" size={19} />}
			autoCapitalize="none"
			autoComplete={autoComplete}
			autoCorrect={false}
			secureTextEntry={!isPasswordVisible}
			textContentType={autoComplete === "new-password" ? "newPassword" : "password"}
			rightSection={
				<Pressable
					accessibilityLabel={isPasswordVisible ? "Hide password" : "Show password"}
					accessibilityRole="button"
					hitSlop={8}
					onPress={() => setIsPasswordVisible((currentValue) => !currentValue)}
					style={({ pressed }) => [styles.iconButton, pressed && styles.iconButtonPressed]}
				>
					<Icon color={theme.colors.textSecondary} name={isPasswordVisible ? "eyeOff" : "eye"} size={20} />
				</Pressable>
			}
		/>
	);
}

const useStyles = createStyles((theme) => ({
	iconButton: {
		alignItems: "center",
		height: 40,
		justifyContent: "center",
		marginRight: -theme.spacing.xs,
		width: 40,
	},
	iconButtonPressed: {
		opacity: 0.7,
	},
}));
