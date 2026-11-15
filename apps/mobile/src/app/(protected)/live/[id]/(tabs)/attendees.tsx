import { useState } from "react";
import { RefreshControl } from "react-native";
import { useLiveEvent } from "@/features/events/context";
import { useEventAttendees } from "@/features/events/hooks";
import { syncEventAttendees } from "@/features/events/sync";
import { useNearbyPeers } from "@/features/presence/context";
import { useSession } from "@/lib/auth/hooks";
import { router } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { Card } from "@/lib/ui/card";
import { Column } from "@/lib/ui/column";
import { Icon } from "@/lib/ui/icon";
import { Row } from "@/lib/ui/row";
import { Screen } from "@/lib/ui/screen";
import { Skeleton } from "@/lib/ui/skeleton";
import { Text } from "@/lib/ui/text";

export default function EventAttendeesScreen() {
	const theme = useTheme();
	const { session } = useSession();

	const userId = session?.user.id ?? "";
	const { event } = useLiveEvent();

	const { data: attendees, error: attendeesError, isPending: areAttendeesPending } = useEventAttendees(userId, event.id);
	const { nearbyPeers } = useNearbyPeers();

	const [isRefreshing, setIsRefreshing] = useState(false);
	const [refreshError, setRefreshError] = useState<string>();
	const refresh = async () => {
		if (!userId || isRefreshing) {
			return;
		}

		setIsRefreshing(true);
		setRefreshError(undefined);

		try {
			await syncEventAttendees(userId, event.id, event.remoteId);
		} catch (error) {
			setRefreshError(error instanceof Error ? error.message : "Unable to refresh attendees.");
		} finally {
			setIsRefreshing(false);
		}
	};

	const refreshControl = (
		<RefreshControl
			colors={[theme.colors.textLink]}
			onRefresh={() => void refresh()}
			progressBackgroundColor={theme.colors.surfaceRaised}
			refreshing={isRefreshing}
			tintColor={theme.colors.textLink}
		/>
	);

	const peerByUserId = new Map<string, (typeof nearbyPeers)[string]>();
	const nearbyUserIds = new Set<string>();

	for (const peer of Object.values(nearbyPeers)) {
		if (peer.userId) {
			nearbyUserIds.add(peer.userId);
			peerByUserId.set(peer.userId, peer);
		}
	}

	const nearbyAttendeeCount = attendees.filter((attendee) => attendee.isCurrentUser || nearbyUserIds.has(attendee.userId)).length;

	const handleAttendeePress = (attendee: (typeof attendees)[number]) => {
		router.push(`/live/${event.id}/attendee/${attendee.userId}`);
	};
	const errorMessage = attendeesError?.message ?? refreshError;

	return (
		<Screen refreshControl={refreshControl} scrollable>
			<Column gap="lg" paddingHorizontal="lg" paddingVertical="md" width="100%">
				<Column gap="xs">
					<Text size="xl" weight="bold">
						Attendees
					</Text>
					<Row align="center" gap="sm">
						<Icon color={theme.colors.success} name="usersFilled" size={20} style={{ transform: [{ translateY: 3 }] }} />
						<Text size="lg" weight="semibold">
							{nearbyAttendeeCount} {nearbyAttendeeCount === 1 ? "person" : "people"} nearby now
						</Text>
					</Row>
					<Text color={theme.colors.textSecondary} size="sm">
						{attendees.length} checked in
					</Text>
				</Column>

				{errorMessage ? (
					<Card>
						<Column gap="sm">
							<Text size="lg" weight="bold">
								Unable to load attendees
							</Text>
							<Text color={theme.colors.textSecondary}>{errorMessage}</Text>
							<Button onPress={() => void refresh()} size="sm" variant="text">
								Refresh
							</Button>
						</Column>
					</Card>
				) : areAttendeesPending ? (
					<Column gap="xs">
						{["first", "second", "third"].map((key) => (
							<Card key={key} padding="md">
								<Row align="center" gap="md">
									<Skeleton height={10} radius={theme.radius.full} width={10} />
									<Column flex gap="xxs" minWidth={0}>
										<Skeleton height={20} width="48%" />
										<Skeleton height={18} width="64%" />
									</Column>
									<Skeleton height={18} width={48} />
									<Skeleton height={18} width={18} />
								</Row>
							</Card>
						))}
					</Column>
				) : attendees.length === 0 ? (
					<Card>
						<Column gap="sm">
							<Text size="lg" weight="bold">
								No attendees yet
							</Text>
							<Text color={theme.colors.textSecondary}>Pull to refresh when people join the event.</Text>
						</Column>
					</Card>
				) : (
					<Column gap="xs">
						{attendees.map((attendee) => {
							const subtitle = attendee.headline.trim() || (attendee.role === "host" ? "Host" : "Attendee");
							const isNearby = attendee.isCurrentUser || nearbyUserIds.has(attendee.userId);
							const nearbyPeer = peerByUserId.get(attendee.userId);
							const distance = nearbyPeer?.distance;
							let distanceLabel: string | undefined;
							let distanceIsFresh = false;

							if (distance !== undefined) {
								const measuredDistance = distance < 1 ? "<1m away" : `${Math.round(distance)}m away`;
								distanceIsFresh = nearbyPeer?.distanceFreshness !== "stale";
								distanceLabel = distanceIsFresh ? measuredDistance : `Last measured: ${measuredDistance}`;
							} else if (isNearby && !attendee.isCurrentUser) {
								distanceLabel = "Updating distance";
							}

							return (
								<Card
									accessibilityLabel={`Open ${attendee.name}, ${isNearby ? "nearby now" : "checked in"}`}
									key={attendee.userId}
									onPress={() => handleAttendeePress(attendee)}
									padding="md"
								>
									<Row align="center" gap="md">
										<Icon color={isNearby ? theme.colors.success : theme.colors.textSecondary} name="circleFilled" size={10} />
										<Column flex gap="xxs" minWidth={0}>
											<Text numberOfLines={1} weight="semibold">
												{attendee.name}
											</Text>
											<Text color={theme.colors.textSecondary} numberOfLines={1} size="sm">
												{subtitle}
											</Text>
										</Column>
										{distanceLabel ? (
											<Text color={distanceIsFresh ? theme.colors.success : theme.colors.textSecondary} size="sm" weight="semibold">
												{distanceLabel}
											</Text>
										) : null}
										<Icon color={theme.colors.text} name="chevronRight" size={18} />
									</Row>
								</Card>
							);
						})}
					</Column>
				)}

				{attendees.length > 0 ? (
					<Text align="center" color={theme.colors.textSecondary} size="sm">
						Pull to refresh
					</Text>
				) : null}
			</Column>
		</Screen>
	);
}
