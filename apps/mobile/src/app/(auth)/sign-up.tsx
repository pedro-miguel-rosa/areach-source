import { useState } from "react";
import { Linking } from "react-native";
import { useSignUp } from "@/lib/auth/hooks";
import { router } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { Column } from "@/lib/ui/column";
import { EmailInput } from "@/lib/ui/email-input";
import { ErrorCard } from "@/lib/ui/error-card";
import { NameInput } from "@/lib/ui/name-input";
import { PasswordInput } from "@/lib/ui/password-input";
import { Row } from "@/lib/ui/row";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";

export default function SignUpScreen() {
	const { clearError, error: submitError, isSubmitting, signUp } = useSignUp();
	const theme = useTheme();

	const [name, setName] = useState("");
	const [email, setEmail] = useState("");
	const [password, setPassword] = useState("");

	const [hasNameBlurred, setHasNameBlurred] = useState(false);
	const [hasEmailBlurred, setHasEmailBlurred] = useState(false);
	const [hasPasswordBlurred, setHasPasswordBlurred] = useState(false);

	const trimmedName = name.trim();
	const trimmedEmail = email.trim();

	const passwordRequirements = [
		{
			id: "length",
			isMet: password.length >= 8,
			label: "8+ characters",
		},
	];
	const passwordMeetsRequirements = password.length >= 8;
	const passwordHasError = hasPasswordBlurred && !passwordMeetsRequirements;
	const showPasswordRequirements = password.length > 0 || hasPasswordBlurred;

	const isNameFilled = trimmedName.length > 0;
	const isEmailFilled = trimmedEmail.length > 0;
	const isEmailValid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmedEmail);
	const isPasswordFilled = password.length > 0;

	const canSubmit = isNameFilled && isEmailFilled && isEmailValid && isPasswordFilled && passwordMeetsRequirements && !isSubmitting;

	let nameError: string | undefined;
	if (hasNameBlurred && !isNameFilled) {
		nameError = "Full name is required.";
	}

	let emailError: string | undefined;
	if (hasEmailBlurred || submitError?.code === "userAlreadyExists") {
		if (!isEmailFilled) {
			emailError = "Enter your email";
		} else if (!isEmailValid) {
			emailError = "Enter a valid email address";
		} else if (submitError?.code === "userAlreadyExists") {
			emailError = submitError.message;
		}
	}

	const submitErrorCard = submitError?.code === "network" || submitError?.code === "unknown" ? submitError : null;

	const handleSubmit = async () => {
		if (!canSubmit) {
			return;
		}

		const wasSignedUp = await signUp({ email: trimmedEmail, name: trimmedName, password });

		if (wasSignedUp) {
			router.replace("/");
		}
	};

	const handleGoToSignIn = () => {
		router.push("/sign-in");
	};

	const openLegalPage = (path: "privacy" | "terms") => {
		void Linking.openURL(`http://localhost:4321/${path}`);
	};

	return (
		<Screen fill scrollable>
			<Column flex justify="center" gap="xl" paddingVertical="xxxl" paddingHorizontal="xl" width="100%" alignSelf="center">
				<Column gap="xl">
					<Column gap="xs">
						<Text align="center" size="lg" weight="bold">
							Create account
						</Text>
						<Text align="center" color={theme.colors.textSecondary}>
							{"Join nearby events and\nmeet real people."}
						</Text>
					</Column>

					<Column gap="md">
						<NameInput
							error={nameError}
							onBlur={() => {
								setHasNameBlurred(true);
							}}
							onChange={(value) => {
								setName(value);
								clearError();
							}}
							placeholder="Full name"
							value={name}
						/>

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
								autoComplete="new-password"
								invalid={passwordHasError}
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

							{showPasswordRequirements ? (
								<Column gap="xs" marginTop="xs">
									<Text color={theme.colors.textSecondary} size="sm" weight="semibold">
										Password must contain:
									</Text>
									{passwordRequirements.map((requirement) => {
										const requirementColor = requirement.isMet
											? theme.colors.success
											: passwordHasError
												? theme.colors.error
												: theme.colors.warning;

										return (
											<Row key={requirement.id} align="center" gap="xs">
												<Text color={requirementColor} size="sm" weight="bold">
													•
												</Text>
												<Text color={requirementColor} size="sm" weight="semibold">
													{requirement.label}
												</Text>
											</Row>
										);
									})}
								</Column>
							) : null}
						</Column>

						{submitErrorCard ? <ErrorCard message={submitErrorCard.message} title={submitErrorCard.title} /> : null}

						<Button disabled={!canSubmit} loading={isSubmitting} onPress={handleSubmit}>
							Create account
						</Button>
					</Column>
				</Column>

				<Column gap="xl" align="center">
					<Row align="center" gap="xxs" justify="center">
						<Text color={theme.colors.textSecondary} size="sm">
							Already have an account?
						</Text>
						<Button onPress={handleGoToSignIn} size="sm" variant="link">
							Sign in
						</Button>
					</Row>
					<Text align="center" color={theme.colors.textSecondary} size="sm">
						By continuing, you agree to the{" "}
						<Text
							color={theme.colors.textLink}
							onPress={() => openLegalPage("terms")}
							size="sm"
							textDecorationLine="underline"
							weight="semibold"
						>
							Terms
						</Text>{" "}
						and{" "}
						<Text
							color={theme.colors.textLink}
							onPress={() => openLegalPage("privacy")}
							size="sm"
							textDecorationLine="underline"
							weight="semibold"
						>
							Privacy Policy
						</Text>
						.
					</Text>
				</Column>
			</Column>
		</Screen>
	);
}
