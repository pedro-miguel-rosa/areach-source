import { useState } from "react";
import { Alert } from "react-native";
import { useDeleteAccount } from "@/lib/auth/hooks";
import { router } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { Card } from "@/lib/ui/card";
import { Column } from "@/lib/ui/column";
import { ErrorCard } from "@/lib/ui/error-card";
import { PasswordInput } from "@/lib/ui/password-input";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";

export default function DeleteAccountScreen() {
	const theme = useTheme();
	const { deleteAccount, error, isSubmitting, clearError } = useDeleteAccount();
	const [password, setPassword] = useState("");
	const [hasBlurred, setHasBlurred] = useState(false);

	const passwordError =
		hasBlurred && password.length === 0 ? "Enter your password" : error?.code === "invalidPassword" ? error.message : undefined;
	const canContinue = password.length > 0 && !isSubmitting;

	const submit = () => {
		if (!canContinue) {
			setHasBlurred(true);
			return;
		}

		Alert.alert(
			"Delete your account?",
			"This permanently deletes your AReach account, hosted events, attendee data, blocks, reports, and cached device data. This cannot be undone.",
			[
				{ text: "Cancel", style: "cancel" },
				{
					text: "Delete Account",
					style: "destructive",
					onPress: () => void confirmDelete(),
				},
			],
		);
	};

	const confirmDelete = async () => {
		const deleted = await deleteAccount(password);

		if (deleted) {
			setPassword("");
			router.replace("/" as never);
			return;
		}
	};

	return (
		<Screen headerInset scrollable>
			<Column gap="lg" paddingBottom="xl" paddingHorizontal="lg" paddingTop="lg">
				<Column gap="xs">
					<Text color={theme.colors.error} size="lg" weight="bold">
						Delete account permanently
					</Text>
					<Text color={theme.colors.textSecondary} size="sm">
						Your account and account-owned hosted events will be deleted. Previously collected study records may be retained in
						de-identified form when required by the study protocol.
					</Text>
				</Column>

				<Card padding="lg">
					<Column gap="md">
						<PasswordInput
							error={passwordError}
							label="Confirm with your password"
							onBlur={() => setHasBlurred(true)}
							onChange={(value) => {
								setPassword(value);
								clearError();
							}}
							placeholder="Current password"
							value={password}
						/>

						{error && error.code !== "invalidPassword" ? <ErrorCard message={error.message} title={error.title} /> : null}

						<Button disabled={!canContinue} loading={isSubmitting} onPress={submit} variant="danger">
							Delete Account
						</Button>
					</Column>
				</Card>
			</Column>
		</Screen>
	);
}
