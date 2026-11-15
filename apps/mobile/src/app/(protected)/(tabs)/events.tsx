import { useMemo, useState } from "react";
import { useEvents } from "@/features/events/hooks";
import { useSession } from "@/lib/auth/hooks";
import { router } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Card } from "@/lib/ui/card";
import { Column } from "@/lib/ui/column";
import { Icon } from "@/lib/ui/icon";
import { IconButton } from "@/lib/ui/icon-button";
import { Row } from "@/lib/ui/row";
import { Screen } from "@/lib/ui/screen";
import { SegmentedControl } from "@/lib/ui/segmented-control";
import { Skeleton } from "@/lib/ui/skeleton";
import { Text } from "@/lib/ui/text";

type EventsSegment = "past" | "upcoming";

const SEGMENTS: Array<{ label: string; value: EventsSegment }> = [
	{ label: "Upcoming", value: "upcoming" },
	{ label: "Past", value: "past" },
];

export default function EventsScreen() {
	const theme = useTheme();
	const { session } = useSession();

	const viewerId = session?.user.id ?? "";
	const { data: events, isPending } = useEvents(viewerId);

	const [segment, setSegment] = useState<EventsSegment>("upcoming");
	const now = useMemo(() => new Date(), []);

	const upcomingEvents = events.filter((event) => event.endAt > now);
	const pastEvents = events.filter((event) => event.endAt <= now).reverse();
	const visibleEvents = segment === "upcoming" ? upcomingEvents : pastEvents;

	if (isPending) {
		return (
			<Screen scrollable>
				<Column flex gap="xl" paddingHorizontal="lg" paddingVertical="md" width="100%">
					<Row align="center" justify="space-between">
						<Skeleton height={28} width={124} />
						<Skeleton height={44} radius={theme.radius.full} width={44} />
					</Row>

					<Column gap="xl">
						<Row gap="sm">
							<Skeleton height={36} radius={theme.radius.full} width={104} />
							<Skeleton height={36} radius={theme.radius.full} width={72} />
						</Row>

						<Column gap="sm">
							{[0, 1, 2].map((index) => (
								<Card key={index} padding="md">
									<Row align="center" gap="md">
										<Column flex gap="xs">
											<Row align="center" gap="sm">
												<Skeleton height={18} radius={theme.radius.full} width={18} />
												<Skeleton height={18} width="58%" />
											</Row>

											<Skeleton height={16} width="36%" />

											<Row align="center" gap="sm" style={{ minHeight: 22 }}>
												<Skeleton height={17} radius={theme.radius.full} width={17} />
												<Skeleton height={16} width="80%" />
											</Row>
											<Row align="center" gap="sm" style={{ minHeight: 22 }}>
												<Skeleton height={17} radius={theme.radius.full} width={17} />
												<Skeleton height={16} width="66%" />
											</Row>
											<Row align="center" gap="sm" style={{ minHeight: 22 }}>
												<Skeleton height={17} radius={theme.radius.full} width={17} />
												<Skeleton height={16} width="48%" />
											</Row>
										</Column>

										<Skeleton height={18} radius={theme.radius.full} width={18} />
									</Row>
								</Card>
							))}
						</Column>
					</Column>
				</Column>
			</Screen>
		);
	}

	return (
		<Screen scrollable>
			<Column gap="xl" paddingHorizontal="lg" paddingVertical="md" width="100%">
				<Row align="center" justify="space-between">
					<Text color={theme.colors.text} size="lg" weight="bold">
						My Events
					</Text>
					<IconButton accessibilityLabel="Create event" icon="plus" onPress={() => router.push("/create")} />
				</Row>

				<Column gap="xl">
					<SegmentedControl onChange={(next) => setSegment(next as EventsSegment)} options={SEGMENTS} value={segment} />

					<Column gap="md">
						{visibleEvents.length > 0 ? (
							<Column gap="sm">
								{visibleEvents.map((event) => {
									const eventDateLabel = event.startAt.toLocaleDateString("en-US", {
										month: "short",
										day: "numeric",
										year: "numeric",
										weekday: "short",
									});
									const eventTimeRangeLabel = `${event.startAt.toLocaleTimeString("en-US", {
										hour: "numeric",
										minute: "2-digit",
									})} - ${event.endAt.toLocaleTimeString("en-US", {
										hour: "numeric",
										minute: "2-digit",
									})}`;
									const capacityLabel = event.capacity
										? `${event.registrationCount} / ${event.capacity} ${segment === "past" ? "went" : "going"}`
										: `${event.registrationCount} ${segment === "past" ? "went" : "going"}`;

									return (
										<Card key={event.id} onPress={() => router.push(`/preview/${event.id}`)} padding="md">
											<Row align="center" gap="md">
												<Column flex gap="xs">
													<Row align="center" gap="sm">
														<Icon color={theme.colors.textSecondary} name="calendar" size={18} />
														<Text numberOfLines={1} size="sm" weight="bold">
															{event.title}
														</Text>
													</Row>

													{event.startAt <= now && event.endAt > now ? (
														<Text color={theme.colors.success} size="sm" weight="semibold">
															Live now
														</Text>
													) : null}

													<Row align="center" gap="sm" style={{ minHeight: 22 }}>
														<Icon color={theme.colors.textSecondary} name="clock" size={17} />
														<Text color={theme.colors.textSecondary} numberOfLines={2} size="sm">
															{eventDateLabel} · {eventTimeRangeLabel}
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

												<Icon color={theme.colors.text} name="chevronRight" size={18} />
											</Row>
										</Card>
									);
								})}
							</Column>
						) : (
							<Card>
								<Text align="center" color={theme.colors.textSecondary} size="sm">
									{segment === "upcoming" ? "No upcoming events yet." : "No past events yet."}
								</Text>
							</Card>
						)}
					</Column>
				</Column>
			</Column>
		</Screen>
	);
}
