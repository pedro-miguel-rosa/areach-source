import * as Clipboard from "expo-clipboard";
import { ActivityIndicator } from "react-native";
import { useCreateEventDraft } from "@/features/events/context";
import { useEventById } from "@/features/events/hooks";
import { useSession } from "@/lib/auth/hooks";
import { router } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { Card } from "@/lib/ui/card";
import { Column } from "@/lib/ui/column";
import { ConfettiCannon } from "@/lib/ui/confetti-cannon";
import { IconButton } from "@/lib/ui/icon-button";
import { IconIllustration } from "@/lib/ui/icon-illustration";
import { Row } from "@/lib/ui/row";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";
import { showToast } from "@/lib/ui/toast";

export default function CreateSuccessScreen() {
	const theme = useTheme();
	const { session } = useSession();

	const { createdEventId, reset } = useCreateEventDraft();
	const viewerId = session?.user.id ?? "";
	const { data: createdEvent } = useEventById(viewerId, createdEventId);

	const displayCode = createdEvent?.inviteCode?.trim().toUpperCase() ?? "";
	const isEventReady = createdEvent?.syncStatus === "synced" && displayCode.length > 0;

	if (!isEventReady) {
		return (
			<Screen fill>
				<Column align="center" flex gap="lg" justify="center" paddingHorizontal="xl">
					<IconIllustration icon="calendar" size={104} />

					<Column align="center" gap="xs">
						<Text align="center" size="lg" weight="bold">
							Creating your event
						</Text>
						<Text align="center" color={theme.colors.textSecondary} size="sm">
							Saving your event and preparing your invite code.
						</Text>
					</Column>

					<ActivityIndicator color={theme.colors.primary} size="large" />
				</Column>
			</Screen>
		);
	}

	const handleCopyCode = async () => {
		if (!displayCode) {
			showToast({ message: "The event code is still syncing.", tone: "info" });
			return;
		}

		await Clipboard.setStringAsync(displayCode);
		showToast({ message: "Event code copied.", tone: "success" });
	};

	const handleDone = () => {
		reset();
		router.replace("/events" as never);
	};

	return (
		<Screen fill scrollable>
			<Column flex gap="xl" justify="center" paddingHorizontal="xl">
				<IconIllustration icon="check" size={104} />

				<Column align="center" gap="xs">
					<Text align="center" size="lg" weight="bold">
						Event created!
					</Text>
					<Text align="center" color={theme.colors.textSecondary} size="sm">
						Share the code with your invited guests.
					</Text>
				</Column>

				<Card padding="md">
					<Column align="center" gap="xs">
						<Text align="center" color={theme.colors.textSecondary} size="sm">
							Event Code
						</Text>
						<Row align="center" gap="md" justify="center">
							<Text align="center" color={theme.colors.success} size="lg" weight="bold">
								{displayCode}
							</Text>
							<IconButton accessibilityLabel="Copy event code" icon="copy" onPress={handleCopyCode} />
						</Row>
					</Column>
				</Card>

				<Button onPress={handleDone}>Done</Button>
			</Column>

			<ConfettiCannon trigger={isEventReady ? createdEvent?.id : undefined} />
		</Screen>
	);
}
