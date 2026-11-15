import { useState } from "react";
import { useRequestPasswordReset } from "@/lib/auth/hooks";
import { router } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { Column } from "@/lib/ui/column";
import { EmailInput } from "@/lib/ui/email-input";
import { ErrorCard } from "@/lib/ui/error-card";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";

export default function ResetPasswordScreen() {
	const { clearError, error: submitError, isSubmitting, requestPasswordReset } = useRequestPasswordReset();
	const theme = useTheme();

	const [email, setEmail] = useState("");
	const [hasEmailBlurred, setHasEmailBlurred] = useState(false);

	const trimmedEmail = email.trim();

	const isEmailFilled = trimmedEmail.length > 0;
	const isEmailValid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmedEmail);

	const canSubmit = isEmailFilled && isEmailValid && !isSubmitting;

	let emailError: string | undefined;
	if (hasEmailBlurred) {
		if (!isEmailFilled) {
			emailError = "Enter your email";
		} else if (!isEmailValid) {
			emailError = "Enter a valid email address";
		}
	}

	const handleSubmit = async () => {
		if (!canSubmit) {
			return;
		}

		const wasRequested = await requestPasswordReset({ email: trimmedEmail });

		if (wasRequested) {
			router.push({ pathname: "/reset-link-sent", params: { email: trimmedEmail } });
		}
	};

	return (
		<Screen fill scrollable>
			<Column flex justify="center" gap="xl" paddingVertical="xxxl" paddingHorizontal="xl" width="100%">
				<Column gap="xl">
					<Column gap="xs">
						<Text align="center" size="lg" weight="bold">
							Reset password
						</Text>
						<Text align="center" color={theme.colors.textSecondary}>
							Enter your email and we'll send you a secure link to reset your password.
						</Text>
					</Column>

					<Column gap="md">
						<EmailInput
							error={emailError}
							onBlur={() => {
								setHasEmailBlurred(true);
							}}
							onChange={(value) => {
								setEmail(value);
								clearError();
							}}
							placeholder="Email"
							value={email}
						/>

						{submitError ? <ErrorCard message={submitError.message} title={submitError.title} /> : null}

						<Button disabled={!canSubmit} loading={isSubmitting} onPress={handleSubmit}>
							Send reset link
						</Button>
					</Column>
				</Column>
			</Column>
		</Screen>
	);
}
