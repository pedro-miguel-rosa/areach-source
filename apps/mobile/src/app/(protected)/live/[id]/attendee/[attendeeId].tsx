import { useState } from "react";
import { Alert } from "react-native";
import { useLiveEvent } from "@/features/events/context";
import { useEventAttendeeById } from "@/features/events/hooks";
import { syncEventAttendees } from "@/features/events/sync";
import { useNearbyPeers } from "@/features/presence/context";
import { blockEventAttendee } from "@/features/privacy/actions";
import { useSession } from "@/lib/auth/hooks";
import { router, usePathParam } from "@/lib/navigation/router";
import { Stack } from "@/lib/navigation/stack";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { Card } from "@/lib/ui/card";
import { Column } from "@/lib/ui/column";
import { Icon } from "@/lib/ui/icon";
import { Row } from "@/lib/ui/row";
import { Screen } from "@/lib/ui/screen";
import { Skeleton } from "@/lib/ui/skeleton";
import { Text } from "@/lib/ui/text";
import { showToast } from "@/lib/ui/toast";

export default function LiveAttendeeDetailScreen() {
	const theme = useTheme();
	const attendeeId = usePathParam("attendeeId");

	const { session } = useSession();
	const viewerId = session?.user.id ?? "";

	const { event } = useLiveEvent();
	const { data: attendee, error: attendeeError, isPending } = useEventAttendeeById(viewerId, event.remoteId, attendeeId);
	const [isBlocking, setIsBlocking] = useState(false);

	const { nearbyPeers } = useNearbyPeers();
	const nearbyPeer = attendee ? Object.values(nearbyPeers).find((peer) => peer.userId === attendee.userId) : undefined;
	const isNearby = Boolean(attendee?.isCurrentUser || nearbyPeer);

	const handleBlock = async () => {
		if (!attendee || attendee.isCurrentUser || !viewerId || isBlocking) {
			return;
		}

		setIsBlocking(true);

		try {
			await blockEventAttendee({ attendee, eventId: event.remoteId, viewerId });
			showToast({ message: "Attendee blocked.", tone: "success" });
			router.back();
		} catch (error) {
			showToast({
				error,
				message: error instanceof Error ? error.message : "Unable to block this attendee.",
				tone: "error",
				durationMs: 5000,
			});
		} finally {
			setIsBlocking(false);
		}
	};

	const openActions = () => {
		if (!attendee || attendee.isCurrentUser || isBlocking) {
			return;
		}

		Alert.alert("Attendee actions", undefined, [
			{
				text: "Report attendee",
				onPress: () => router.push(`/live/${event.id}/attendee/${attendee.userId}/report`),
			},
			{
				text: "Block attendee",
				style: "destructive",
				onPress: () => {
					Alert.alert(
						"Block this attendee?",
						"You will no longer see each other in attendee lists, nearby results, distances, or camera cards.",
						[
							{ text: "Cancel", style: "cancel" },
							{ text: "Block", style: "destructive", onPress: () => void handleBlock() },
						],
					);
				},
			},
			{ text: "Cancel", style: "cancel" },
		]);
	};

	if (isPending) {
		return (
			<Screen headerInset scrollable>
				<Column alignSelf="center" gap="lg" maxWidth={640} padding="lg" width="100%">
					<Column gap="sm">
						<Skeleton height={20} width={120} />
						<Skeleton height={38} width={190} />
						<Skeleton height={22} width={160} />
					</Column>
					<Skeleton height={82} radius={theme.radius.lg} width="100%" />
					<Column gap="sm">
						<Skeleton height={26} width={170} />
						<Skeleton height={58} radius={theme.radius.lg} width="100%" />
						<Skeleton height={58} radius={theme.radius.lg} width="100%" />
					</Column>
				</Column>
			</Screen>
		);
	}

	if (!attendee) {
		return (
			<Screen headerInset scrollable>
				<Column alignSelf="center" gap="lg" maxWidth={640} padding="lg" width="100%">
					<Card>
						<Column gap="md">
							<Text size="xl" weight="bold">
								Attendee not found
							</Text>
							<Text color={theme.colors.textSecondary}>
								{attendeeError?.message ?? "This attendee is not visible in your latest live event data. Refresh the event and try again."}
							</Text>
							<Button onPress={() => void syncEventAttendees(viewerId, event.id, event.remoteId)} variant="surface">
								Refresh
							</Button>
						</Column>
					</Card>
				</Column>
			</Screen>
		);
	}

	let distanceLabel: string | undefined;
	let proximityUpdatedLabel: string | undefined;

	if (nearbyPeer?.distance !== undefined) {
		const measuredDistance = nearbyPeer.distance < 1 ? "<1m away" : `${Math.round(nearbyPeer.distance)}m away`;
		if (nearbyPeer.distanceFreshness === "stale") {
			distanceLabel = `Last measured: ${measuredDistance}`;
			proximityUpdatedLabel = "Waiting for the next range";
		} else {
			distanceLabel = measuredDistance;
			const distanceUpdatedAt = nearbyPeer.distanceUpdatedAt ?? nearbyPeer.lastUpdatedAt;
			proximityUpdatedLabel =
				Date.now() - distanceUpdatedAt < 2000
					? "Updated now"
					: `Updated ${Math.max(1, Math.round((Date.now() - distanceUpdatedAt) / 1000))}s ago`;
		}
	}

	return (
		<>
			{!attendee.isCurrentUser ? (
				<Stack.Screen>
					<Stack.Toolbar placement="right">
						<Stack.Toolbar.Button accessibilityLabel="More attendee actions" icon="ellipsis" onPress={openActions} />
					</Stack.Toolbar>
				</Stack.Screen>
			) : null}
			<Screen headerInset scrollable>
				<Column alignSelf="center" gap="xl" maxWidth={640} paddingBottom="xl" paddingHorizontal="lg" paddingTop="lg" width="100%">
					<Column gap="md">
						<Column gap="xxs">
							<Row align="center" gap="md" justify="space-between">
								<Column flex minWidth={0}>
									<Text size="xl" weight="bold">
										{attendee.name}
									</Text>
								</Column>
								<Row align="center" gap="xs">
									<Icon color={isNearby ? theme.colors.success : theme.colors.textSecondary} name="circleFilled" size={9} />
									<Text color={isNearby ? theme.colors.success : theme.colors.textSecondary} size="sm" weight="semibold">
										{isNearby ? "Nearby now" : "Checked in"}
									</Text>
								</Row>
							</Row>
							{attendee.headline.trim() ? (
								<Text color={theme.colors.textSecondary} size="lg">
									{attendee.headline}
								</Text>
							) : null}
						</Column>
					</Column>

					{distanceLabel ? (
						<Card>
							<Row align="center" gap="md">
								<Row
									align="center"
									backgroundColor={theme.colors.successSurface}
									borderRadius={theme.radius.full}
									height={44}
									justify="center"
									width={44}
								>
									<Icon color={theme.colors.success} name="location" size={21} />
								</Row>
								<Column gap="xxs">
									<Text color={theme.colors.success} size="lg" weight="semibold">
										{distanceLabel}
									</Text>
									<Text color={theme.colors.textSecondary} size="sm">
										{proximityUpdatedLabel}
									</Text>
								</Column>
							</Row>
						</Card>
					) : null}

					<Column gap="sm">
						<Text size="lg" weight="bold">
							Ask me about…
						</Text>
						{attendee.askMeAbout.length > 0 ? (
							<Column gap="xs">
								{attendee.askMeAbout.map((topic) => (
									<Card key={topic} padding="md">
										<Text>{topic}</Text>
									</Card>
								))}
							</Column>
						) : (
							<Text color={theme.colors.textSecondary}>No conversation topics added yet.</Text>
						)}
					</Column>
				</Column>
			</Screen>
		</>
	);
}
