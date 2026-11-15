import * as Clipboard from "expo-clipboard";
import { useState } from "react";
import { Share } from "react-native";
import { refreshRemoteLiveAttendance } from "@/features/events/api";
import { useEventById } from "@/features/events/hooks";
import { startAReachLiveEventActivity } from "@/features/presence/activity";
import { useSession } from "@/lib/auth/hooks";
import { Redirect } from "@/lib/navigation/redirect";
import { router, usePathParam } from "@/lib/navigation/router";
import { Stack } from "@/lib/navigation/stack";
import { useTheme } from "@/lib/theme/hooks";
import { Badge } from "@/lib/ui/badge";
import { Button } from "@/lib/ui/button";
import { Card } from "@/lib/ui/card";
import { Column } from "@/lib/ui/column";
import { Icon } from "@/lib/ui/icon";
import { IconButton } from "@/lib/ui/icon-button";
import { Row } from "@/lib/ui/row";
import { Screen } from "@/lib/ui/screen";
import { Skeleton } from "@/lib/ui/skeleton";
import { Text } from "@/lib/ui/text";
import { showToast } from "@/lib/ui/toast";
import AReachSpatial from "@/modules/areach-spatial";

export default function EventPreviewScreen() {
	const theme = useTheme();
	const now = new Date();
	const eventId = usePathParam("id");

	const { session } = useSession();

	const viewerId = session?.user.id ?? "";
	const { data: event, isPending } = useEventById(viewerId, eventId);

	const [isEnteringEvent, setIsEnteringEvent] = useState(false);

	const eventDateLabel = event
		? event.startAt.toLocaleDateString("en-US", {
				month: "short",
				day: "numeric",
				year: "numeric",
				weekday: "short",
			})
		: "";

	const eventTimeRangeLabel = event
		? `${event.startAt.toLocaleTimeString("en-US", {
				hour: "numeric",
				minute: "2-digit",
			})} - ${event.endAt.toLocaleTimeString("en-US", {
				hour: "numeric",
				minute: "2-digit",
			})}`
		: "";

	const displayInviteCode = event?.inviteCode?.trim().toUpperCase() ?? "";

	const handleShare = () => {
		if (!event) {
			return;
		}

		void Share.share({
			title: event.title,
			message: `${event.title}\n${eventDateLabel} · ${eventTimeRangeLabel}\n${event.venue}${displayInviteCode && event.endAt > now ? `\nEvent code: ${displayInviteCode}` : ""}`,
		});
	};

	const screenHeader = (
		<Stack.Screen>
			<Stack.Header transparent />
			<Stack.Toolbar placement="left">
				<Stack.Toolbar.Button accessibilityLabel="Back" icon="chevron.left" onPress={() => router.back()} />
			</Stack.Toolbar>
			<Stack.Title style={{ color: theme.colors.text }}>{event?.title ?? "Event"}</Stack.Title>
			{!event || event.endAt > now ? (
				<Stack.Toolbar placement="right">
					<Stack.Toolbar.Button accessibilityLabel="Share event" disabled={!event} onPress={handleShare}>
						Share
					</Stack.Toolbar.Button>
				</Stack.Toolbar>
			) : null}
		</Stack.Screen>
	);

	if (isPending) {
		return (
			<>
				{screenHeader}
				<Screen headerInset scrollable>
					<Column alignSelf="center" maxWidth={520} paddingHorizontal="lg" width="100%">
						<Column gap="lg">
							<Skeleton height={24} radius={theme.radius.full} width={88} />
							<Column gap="sm">
								<Skeleton height={28} width="72%" />
								<Skeleton height={20} width="86%" />
								<Skeleton height={20} width="58%" />
							</Column>
							<Skeleton height={144} radius={theme.radius.xl} width="100%" />
							<Skeleton height={96} radius={theme.radius.xl} width="100%" />
							<Skeleton height={56} radius={theme.radius.lg} width="100%" />
						</Column>
					</Column>
				</Screen>
			</>
		);
	}

	if (!event) {
		return <Redirect href="/" />;
	}

	const status = event.endAt <= now ? "past" : event.startAt <= now ? "live" : "upcoming";
	const remoteEventId = event.remoteId;
	const isEventSynced = remoteEventId !== null;
	const canEnterEvent = status === "live" && isEventSynced;
	const description = event.description.trim() || "No description has been added for this event yet.";
	const capacityLabel = event.capacity
		? `${event.registrationCount} / ${event.capacity} ${status === "past" ? "went" : "going"}`
		: `${event.registrationCount} ${status === "past" ? "went" : "going"}`;

	const handleCopyCode = async () => {
		if (!displayInviteCode) {
			showToast({ message: "The event code is not available yet.", tone: "info" });
			return;
		}

		await Clipboard.setStringAsync(displayInviteCode);
		showToast({ message: "Event code copied.", tone: "success" });
	};

	const handleEnterEvent = async () => {
		if (!isEventSynced || isEnteringEvent) {
			return;
		}

		setIsEnteringEvent(true);

		try {
			const attendance = await refreshRemoteLiveAttendance(remoteEventId, AReachSpatial.nearbyIdentity());

			if (AReachSpatial.isNearbyInteractionSupported()) {
				await AReachSpatial.startNearbyDiscovery(
					attendance.nearbyEventScope,
					attendance.nearbyCredential,
					attendance.nearbyTransportKey,
					new Date(attendance.nearbyCredentialExpiresAt).getTime(),
				);

				if (AReachSpatial.isBackgroundNearbyInteractionSupported()) {
					try {
						await startAReachLiveEventActivity(
							{
								endsAt: event.endAt.getTime(),
								eventId: remoteEventId,
								status: "Nearby detection active",
								title: event.title.trim() || "Live event",
							},
							`areach://live/${event.id}`,
						);
					} catch {
						// Foreground presence remains useful when ActivityKit rejects a
						// start request; the live flow should not become unusable.
					}
				}
			}

			router.push(`/live/${event.id}`);
		} catch (error) {
			const message = error instanceof Error && error.message ? error.message : "Unable to enter the live event.";

			showToast({ error, message, tone: "error", durationMs: 5000 });
		} finally {
			setIsEnteringEvent(false);
		}
	};

	return (
		<>
			{screenHeader}
			<Screen headerInset scrollable>
				<Column paddingHorizontal="lg" paddingVertical="md">
					<Column gap="lg">
						<Column gap="md">
							<Column gap="xs">
								<Row align="center" gap="sm" justify="space-between">
									<Column flex>
										<Text size="lg" weight="bold">
											{event.title}
										</Text>
									</Column>
									{status === "past" ? null : (
										<Badge icon={status === "live" ? "circleFilled" : undefined} variant={status === "live" ? "success" : "accent"}>
											{status === "live" ? "Live now" : "Upcoming"}
										</Badge>
									)}
								</Row>
								<Text color={theme.colors.textSecondary} size="sm">
									{description}
								</Text>
							</Column>
						</Column>

						<Card>
							<Column gap="md">
								<Row align="center" gap="sm" style={{ minHeight: 22 }}>
									<Icon color={theme.colors.textSecondary} name="calendar" size={17} />
									<Text color={theme.colors.textSecondary} numberOfLines={2} size="sm">
										{eventDateLabel}
									</Text>
								</Row>
								<Row align="center" gap="sm" style={{ minHeight: 22 }}>
									<Icon color={theme.colors.textSecondary} name="clock" size={17} />
									<Text color={theme.colors.textSecondary} numberOfLines={2} size="sm">
										{eventTimeRangeLabel}
									</Text>
								</Row>
								<Row align="center" gap="sm" style={{ minHeight: 22 }}>
									<Icon color={theme.colors.textSecondary} name="location" size={17} />
									<Text color={theme.colors.textSecondary} numberOfLines={2} size="sm">
										{event.venue}
									</Text>
								</Row>
								<Row align="center" gap="sm" style={{ minHeight: 22 }}>
									<Icon color={theme.colors.textSecondary} name="users" size={17} />
									<Text color={theme.colors.textSecondary} numberOfLines={2} size="sm">
										{capacityLabel}
									</Text>
								</Row>
							</Column>
						</Card>

						{event.createdByUser && status !== "past" ? (
							<Card padding="md">
								<Row align="center" justify="space-between">
									<Column gap="xxs">
										<Text color={theme.colors.textSecondary} size="sm">
											Event Code
										</Text>
										{displayInviteCode ? (
											<Text color={theme.colors.success} size="lg" weight="bold">
												{displayInviteCode}
											</Text>
										) : (
											<Text color={theme.colors.textSecondary} size="sm">
												Not available yet
											</Text>
										)}
									</Column>
									{displayInviteCode ? <IconButton accessibilityLabel="Copy event code" icon="copy" onPress={handleCopyCode} /> : null}
								</Row>
							</Card>
						) : null}

						{canEnterEvent ? (
							<Button loading={isEnteringEvent} onPress={() => void handleEnterEvent()}>
								Enter Event
							</Button>
						) : null}
					</Column>
				</Column>
			</Screen>
		</>
	);
}
