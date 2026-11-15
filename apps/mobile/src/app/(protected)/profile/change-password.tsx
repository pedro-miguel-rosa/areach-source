import { useState } from "react";
import { useChangePassword } from "@/lib/auth/hooks";
import { router } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { Card } from "@/lib/ui/card";
import { Column } from "@/lib/ui/column";
import { ErrorCard } from "@/lib/ui/error-card";
import { PasswordInput } from "@/lib/ui/password-input";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";

export default function ChangePasswordScreen() {
	const { changePassword, clearError, error: submitError, isSubmitting } = useChangePassword();
	const theme = useTheme();

	const [currentPassword, setCurrentPassword] = useState("");
	const [newPassword, setNewPassword] = useState("");
	const [confirmPassword, setConfirmPassword] = useState("");
	const [hasCurrentPasswordBlurred, setHasCurrentPasswordBlurred] = useState(false);
	const [hasNewPasswordBlurred, setHasNewPasswordBlurred] = useState(false);
	const [hasConfirmPasswordBlurred, setHasConfirmPasswordBlurred] = useState(false);

	const passwordMeetsRequirements = newPassword.length >= 8;
	const passwordsMatch = newPassword === confirmPassword && confirmPassword.length > 0;
	const canSubmit = currentPassword.length > 0 && passwordMeetsRequirements && passwordsMatch && !isSubmitting;
	const showPasswordRequirements = newPassword.length > 0 || hasNewPasswordBlurred;

	const currentPasswordError =
		hasCurrentPasswordBlurred && currentPassword.length === 0
			? "Enter your current password"
			: submitError?.code === "invalidPassword"
				? submitError.message
				: undefined;

	const newPasswordError =
		hasNewPasswordBlurred && !passwordMeetsRequirements
			? "Use at least 8 characters"
			: submitError?.code === "passwordTooShort" || submitError?.code === "passwordTooLong"
				? submitError.message
				: undefined;

	const confirmPasswordError = hasConfirmPasswordBlurred && !passwordsMatch ? "Passwords do not match" : undefined;

	const submitErrorCard = submitError?.code === "network" || submitError?.code === "unknown" ? submitError : null;

	const handleSubmit = async () => {
		if (!canSubmit) {
			return;
		}

		const wasChanged = await changePassword({ currentPassword, newPassword });

		if (wasChanged) {
			router.back();
		}
	};

	return (
		<Screen headerInset scrollable>
			<Column gap="lg" paddingBottom="xl" paddingHorizontal="lg" paddingTop="lg">
				<Column gap="xs">
					<Text size="lg" weight="bold">
						Update your password
					</Text>
					<Text color={theme.colors.textSecondary} size="sm">
						Choose a new password to keep your account secure.
					</Text>
				</Column>

				<Card padding="lg">
					<Column gap="md">
						<PasswordInput
							error={currentPasswordError}
							onBlur={() => setHasCurrentPasswordBlurred(true)}
							onChange={(value) => {
								setCurrentPassword(value);
								clearError();
							}}
							placeholder="Current password"
							value={currentPassword}
						/>

						<Column gap="xs">
							<PasswordInput
								autoComplete="new-password"
								error={newPasswordError}
								onBlur={() => setHasNewPasswordBlurred(true)}
								onChange={(value) => {
									setNewPassword(value);
									clearError();
								}}
								placeholder="New password"
								value={newPassword}
							/>

							{showPasswordRequirements ? (
								<Text color={passwordMeetsRequirements ? theme.colors.success : theme.colors.warning} size="sm" weight="semibold">
									{passwordMeetsRequirements ? "Password meets the minimum length." : "Use at least 8 characters."}
								</Text>
							) : null}
						</Column>

						<PasswordInput
							autoComplete="new-password"
							error={confirmPasswordError}
							onBlur={() => setHasConfirmPasswordBlurred(true)}
							onChange={(value) => {
								setConfirmPassword(value);
								clearError();
							}}
							placeholder="Confirm new password"
							value={confirmPassword}
						/>

						{submitErrorCard ? <ErrorCard message={submitErrorCard.message} title={submitErrorCard.title} /> : null}

						<Button disabled={!canSubmit} loading={isSubmitting} onPress={handleSubmit}>
							Change password
						</Button>
					</Column>
				</Card>
			</Column>
		</Screen>
	);
}
