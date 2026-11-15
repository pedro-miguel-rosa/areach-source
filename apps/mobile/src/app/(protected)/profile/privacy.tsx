import { useMemo } from "react";
import { ActivityIndicator, Switch } from "react-native";
import { useProfile } from "@/features/profile/hooks";
import { useSession } from "@/lib/auth/hooks";
import { useTheme } from "@/lib/theme/hooks";
import { Card } from "@/lib/ui/card";
import { Column } from "@/lib/ui/column";
import { ErrorCard } from "@/lib/ui/error-card";
import { Row } from "@/lib/ui/row";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";

export default function PrivacyScreen() {
	const theme = useTheme();
	const { session } = useSession();
	const user = session?.user;
	const viewerId = user?.id ?? "";
	const userEmail = user?.email;
	const userImage = user?.image;
	const userName = user?.name;
	const profileSeed = useMemo(
		() => (userEmail ? { name: userName || userEmail, email: userEmail, image: userImage } : undefined),
		[userEmail, userImage, userName],
	);
	const { error, profile, isPending, isSubmitting, submitProfile } = useProfile(viewerId, profileSeed);

	const isDiscoverable = profile?.isDiscoverable ?? true;

	const updateDiscoverability = async (nextValue: boolean) => {
		if (isSubmitting || !profile) {
			return;
		}

		await submitProfile({ isDiscoverable: nextValue });
	};

	return (
		<Screen headerInset scrollable>
			<Column gap="lg" paddingBottom="xl" paddingHorizontal="lg" paddingTop="lg">
				<Column gap="xs">
					<Text size="lg" weight="bold">
						Nearby privacy
					</Text>
					<Text color={theme.colors.textSecondary} size="sm">
						Choose whether other attendees can discover your profile during events.
					</Text>
				</Column>

				{isPending ? (
					<Card>
						<Row align="center" gap="md">
							<ActivityIndicator color={theme.colors.primary} />
							<Text color={theme.colors.textSecondary}>Loading your privacy settings…</Text>
						</Row>
					</Card>
				) : (
					<Column gap="sm">
						{error ? <ErrorCard message={error.message} title="Unable to load privacy settings" /> : null}
						<Card padding="md">
							<Row align="center" gap="md" justify="space-between">
								<Column flex gap="xs">
									<Text weight="semibold">Visible to nearby attendees</Text>
									<Text color={theme.colors.textSecondary} size="sm">
										When enabled, your name and profile can appear in attendee lists, nearby distances, and camera cards.
									</Text>
								</Column>
								<Switch
									accessibilityLabel="Visible to nearby attendees"
									accessibilityState={{ checked: isDiscoverable, disabled: isSubmitting || !profile }}
									disabled={isSubmitting || !profile}
									onValueChange={(value) => void updateDiscoverability(value)}
									thumbColor={isDiscoverable ? theme.colors.surface : theme.colors.textSecondary}
									trackColor={{ false: theme.colors.border, true: theme.colors.primaryMuted }}
									value={isDiscoverable}
								/>
							</Row>
						</Card>
					</Column>
				)}

				<Card padding="md">
					<Text color={theme.colors.textSecondary} size="sm">
						Turning this off hides you as a whole from other attendees in every event. It also removes your nearby distance and camera
						overlay. You can always see and edit your own profile, and event hosts cannot override this choice.
					</Text>
				</Card>
			</Column>
		</Screen>
	);
}
