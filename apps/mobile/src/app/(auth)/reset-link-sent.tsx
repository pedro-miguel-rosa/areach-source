import { useRequestPasswordReset } from "@/lib/auth/hooks";
import { router, usePathParam } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { Column } from "@/lib/ui/column";
import { ErrorCard } from "@/lib/ui/error-card";
import { Icon } from "@/lib/ui/icon";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";
import { View } from "@/lib/ui/view";

export default function ResetLinkSentScreen() {
	const emailValue = usePathParam("email");
	const { error: submitError, isSubmitting, requestPasswordReset } = useRequestPasswordReset();
	const theme = useTheme();

	const handleResend = async () => {
		if (!emailValue) {
			router.replace("/reset-password");
			return;
		}

		await requestPasswordReset({ email: emailValue });
	};

	return (
		<Screen fill scrollable>
			<Column flex justify="center" gap="xl" paddingVertical="xxxl" paddingHorizontal="xl" width="100%" alignSelf="center">
				<Column align="center" gap="lg">
					<View
						style={{
							alignItems: "center",
							backgroundColor: theme.colors.successSurface,
							borderRadius: 9999,
							height: 96,
							justifyContent: "center",
							width: 96,
						}}
					>
						<Icon color={theme.colors.success} name="check" size={44} />
					</View>

					<Column align="center" gap="xs">
						<Text align="center" size="lg" weight="bold">
							Check your inbox
						</Text>
						<Text align="center" color={theme.colors.textSecondary}>
							We've sent a password reset link to your email address.
						</Text>
					</Column>
				</Column>

				<Column gap="md">
					{submitError ? <ErrorCard message={submitError.message} title={submitError.title} /> : null}

					<Button onPress={() => router.replace("/sign-in")} variant="surface">
						Back to sign in
					</Button>
					<Button loading={isSubmitting} onPress={handleResend} variant="text">
						Resend email
					</Button>
				</Column>
			</Column>
		</Screen>
	);
}
