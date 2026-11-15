import { useState } from "react";
import { useSignIn } from "@/lib/auth/hooks";
import { router } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { Column } from "@/lib/ui/column";
import { EmailInput } from "@/lib/ui/email-input";
import { ErrorCard } from "@/lib/ui/error-card";
import { PasswordInput } from "@/lib/ui/password-input";
import { Row } from "@/lib/ui/row";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";

export default function SignInScreen() {
	const { clearError, error: submitError, isSubmitting, signIn } = useSignIn();
	const theme = useTheme();

	const [email, setEmail] = useState("");
	const [password, setPassword] = useState("");

	const [hasEmailBlurred, setHasEmailBlurred] = useState(false);
	const [hasPasswordBlurred, setHasPasswordBlurred] = useState(false);

	const trimmedEmail = email.trim();

	const isEmailFilled = trimmedEmail.length > 0;
	const isEmailValid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmedEmail);
	const isPasswordFilled = password.length > 0;

	const canSubmit = isEmailFilled && isEmailValid && isPasswordFilled && !isSubmitting;

	let emailError: string | undefined;
	if (hasEmailBlurred) {
		if (!isEmailFilled) {
			emailError = "Enter your email";
		} else if (!isEmailValid) {
			emailError = "Enter a valid email address";
		}
	}

	let passwordError: string | undefined;
	if (hasPasswordBlurred && !isPasswordFilled) {
		passwordError = "Enter your password";
	}

	const handleSubmit = async () => {
		if (!canSubmit) {
			return;
		}

		const wasSignedIn = await signIn({ email: trimmedEmail, password });

		if (wasSignedIn) {
			router.replace("/");
		}
	};

	return (
		<Screen fill scrollable>
			<Column flex justify="center" gap="xl" paddingVertical="xxxl" paddingHorizontal="xl" width="100%">
				<Column gap="xl">
					<Column gap="xs">
						<Text align="center" size="lg" weight="bold">
							Welcome back
						</Text>
						<Text align="center" color={theme.colors.textSecondary}>
							Sign in to continue to AReach.
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

						<Column gap="xs">
							<PasswordInput
								error={passwordError}
								onBlur={() => {
									setHasPasswordBlurred(true);
								}}
								onChange={(value) => {
									setPassword(value);
									clearError();
								}}
								placeholder="Password"
								value={password}
							/>
							<Row justify="flex-end">
								<Button onPress={() => router.push("/reset-password")} size="sm" variant="text">
									Forgot password?
								</Button>
							</Row>
						</Column>

						{submitError ? <ErrorCard message={submitError.message} title={submitError.title} /> : null}

						<Button disabled={!canSubmit} loading={isSubmitting} onPress={handleSubmit}>
							Sign in
						</Button>
					</Column>
				</Column>

				<Row align="center" gap="xxs" justify="center">
					<Text color={theme.colors.textSecondary} size="sm">
						No account?
					</Text>
					<Button onPress={() => router.push("/sign-up")} size="sm" variant="link">
						Create one
					</Button>
				</Row>
			</Column>
		</Screen>
	);
}
