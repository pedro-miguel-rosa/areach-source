import { useState } from "react";
import { useChangeEmail, useSession } from "@/lib/auth/hooks";
import { router } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { Card } from "@/lib/ui/card";
import { Column } from "@/lib/ui/column";
import { EmailInput } from "@/lib/ui/email-input";
import { ErrorCard } from "@/lib/ui/error-card";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";

export default function ChangeEmailScreen() {
	const { session } = useSession();
	const { changeEmail, clearError, error: submitError, isSubmitting } = useChangeEmail();
	const theme = useTheme();

	const currentEmail = session?.user.email ?? "";
	const [email, setEmail] = useState("");
	const [hasEmailBlurred, setHasEmailBlurred] = useState(false);

	const trimmedEmail = email.trim();
	const isEmailFilled = trimmedEmail.length > 0;
	const isEmailValid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmedEmail);
	const isSameEmail = currentEmail.length > 0 && trimmedEmail.toLocaleLowerCase() === currentEmail.toLocaleLowerCase();
	const canSubmit = isEmailFilled && isEmailValid && !isSameEmail && !isSubmitting;

	let emailError: string | undefined;
	if (hasEmailBlurred) {
		if (!isEmailFilled) {
			emailError = "Enter your new email";
		} else if (!isEmailValid) {
			emailError = "Enter a valid email address";
		} else if (isSameEmail) {
			emailError = "Enter a different email address";
		}
	} else if (submitError?.code === "emailIsSame" || submitError?.code === "emailAlreadyInUse") {
		emailError = submitError.message;
	}

	const submitErrorCard = submitError?.code === "network" || submitError?.code === "unknown" ? submitError : null;

	const handleEmailChange = (value: string) => {
		setEmail(value);
		clearError();
	};

	const handleSubmit = async () => {
		if (!canSubmit) {
			return;
		}

		const wasRequested = await changeEmail(trimmedEmail.toLocaleLowerCase());

		if (wasRequested) {
			router.back();
		}
	};

	return (
		<Screen headerInset scrollable>
			<Column gap="lg" paddingBottom="xl" paddingHorizontal="lg" paddingTop="lg">
				<Column gap="xs">
					<Text size="lg" weight="bold">
						Update your email address
					</Text>
					<Text color={theme.colors.textSecondary} size="sm">
						Your current email stays active until the new address is verified.
					</Text>
					{currentEmail ? (
						<Text color={theme.colors.textSecondary} size="sm">
							Current email: {currentEmail}
						</Text>
					) : null}
				</Column>

				<Card padding="lg">
					<Column gap="md">
						<EmailInput
							error={emailError}
							label="New email"
							onBlur={() => setHasEmailBlurred(true)}
							onChange={handleEmailChange}
							placeholder="Email"
							value={email}
						/>

						{submitErrorCard ? <ErrorCard message={submitErrorCard.message} title={submitErrorCard.title} /> : null}

						<Button disabled={!canSubmit} loading={isSubmitting} onPress={handleSubmit}>
							Send confirmation email
						</Button>
					</Column>
				</Card>
			</Column>
		</Screen>
	);
}
