import { useUpcomingEvents } from "@/features/events/hooks";
import { useSession } from "@/lib/auth/hooks";
import { router } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Badge } from "@/lib/ui/badge";
import { Button } from "@/lib/ui/button";
import { Card } from "@/lib/ui/card";
import { Center } from "@/lib/ui/center";
import { Column } from "@/lib/ui/column";
import { Icon } from "@/lib/ui/icon";
import { IconIllustration } from "@/lib/ui/icon-illustration";
import { Row } from "@/lib/ui/row";
import { Screen } from "@/lib/ui/screen";
import { Skeleton } from "@/lib/ui/skeleton";
import { Text } from "@/lib/ui/text";

export default function HomeScreen() {
	const theme = useTheme();
	const { colors } = theme;
	const { session } = useSession();

	const userId = session?.user.id ?? "";
	const displayName = session?.user.name?.trim() || "there";

	const now = new Date();
	const dayPeriod = now.getHours() < 12 ? "morning" : now.getHours() < 18 ? "afternoon" : "evening";

	const { data: upcomingEvents, isPending } = useUpcomingEvents(userId, now);

	const nextEvent = upcomingEvents[0];

	if (isPending) {
		return (
			<Screen scrollable>
				<Column flex gap="xl" paddingVertical="md" paddingHorizontal="lg" width="100%">
					<Column gap="xs">
						<Text color={colors.text} size="md">
							Good {dayPeriod},
						</Text>
						<Text color={colors.text} size="lg" weight="bold">
							{displayName} 👋
						</Text>
					</Column>
					<Column gap="xl">
						<Card shadow="lg">
							<Column gap="lg">
								<Skeleton height={24} width={112} />

								<Column gap="xs">
									<Skeleton height={28} width="72%" />
									<Skeleton height={20} width="88%" />
								</Column>

								<Column gap="sm">
									<Skeleton height={20} width="56%" />
									<Skeleton height={20} width="64%" />
									<Skeleton height={20} width="44%" />
									<Skeleton height={20} width="52%" />
								</Column>

								<Skeleton height={44} radius={theme.radius.lg} width="100%" />
							</Column>
						</Card>

						<Card shadow="sm">
							<Column gap="md">
								<Column gap="xs">
									<Skeleton height={22} width="46%" />
									<Skeleton height={18} width="78%" />
								</Column>

								<Skeleton height={44} radius={theme.radius.lg} width="100%" />
							</Column>
						</Card>
					</Column>
				</Column>
			</Screen>
		);
	}

	if (upcomingEvents.length === 0) {
		return (
			<Screen scrollable>
				<Column flex gap="xl" paddingVertical="md" paddingHorizontal="lg" width="100%">
					<Column gap="xs">
						<Text color={colors.text} size="md">
							Good {dayPeriod},
						</Text>
						<Text color={colors.text} size="lg" weight="bold">
							{displayName} 👋
						</Text>
					</Column>
					<Column gap="xl">
						<Column align="center" gap="sm">
							<IconIllustration icon="ticket" />
							<Text align="center" color={colors.text} size="lg" weight="bold">
								You have no upcoming events
							</Text>
							<Text align="center" color={colors.textSecondary} lineHeight={24} size="md">
								{"Join an event with a code\nto get started."}
							</Text>
						</Column>

						<Column gap="md">
							<Button onPress={() => router.push("/join")}>Join with Code</Button>
							<Button onPress={() => router.push("/create")} variant="outline">
								Create Event
							</Button>
						</Column>

						<Card shadow="lg">
							<Column gap="lg">
								<Text color={colors.text} size="lg" weight="bold">
									How it works
								</Text>

								<Column gap="lg">
									<Row align="center" gap="lg">
										<Center height={32} width={32}>
											<Icon color={colors.textLink} name="ticket" size={27} />
										</Center>
										<Column flex gap="xxs">
											<Text color={colors.text} size="sm" weight="bold">
												Get an invite code
											</Text>
											<Text color={colors.textSecondary} size="sm">
												Receive a code from the host.
											</Text>
										</Column>
									</Row>

									<Row align="center" gap="lg">
										<Center height={32} width={32}>
											<Icon color={colors.textLink} name="plusCircle" size={27} />
										</Center>
										<Column flex gap="xxs">
											<Text color={colors.text} size="sm" weight="bold">
												Join the event
											</Text>
											<Text color={colors.textSecondary} size="sm">
												Enter the code and join instantly.
											</Text>
										</Column>
									</Row>

									<Row align="center" gap="lg">
										<Center height={32} width={32}>
											<Icon color={colors.textLink} name="calendarCheck" size={27} />
										</Center>
										<Column flex gap="xxs">
											<Text color={colors.text} size="sm" weight="bold">
												Access your event
											</Text>
											<Text color={colors.textSecondary} size="sm">
												View details and enter the event.
											</Text>
										</Column>
									</Row>
								</Column>
							</Column>
						</Card>
					</Column>
				</Column>
			</Screen>
		);
	}

	const nextEventStatus = nextEvent.startAt <= now ? "live" : "upcoming";
	const nextEventDescription = nextEvent.description.trim();
	const nextEventDate = nextEvent.startAt.toLocaleDateString("en-GB", {
		month: "short",
		day: "numeric",
		year: "numeric",
		weekday: "short",
	});
	const nextEventTimeRange = `${nextEvent.startAt.toLocaleTimeString("en-GB", { hour: "numeric", minute: "2-digit" })} - ${nextEvent.endAt.toLocaleTimeString("en-GB", { hour: "numeric", minute: "2-digit" })}`;
	const nextEventCapacityLabel = nextEvent.capacity
		? `${nextEvent.registrationCount} / ${nextEvent.capacity} going`
		: `${nextEvent.registrationCount} going`;

	return (
		<Screen scrollable>
			<Column flex gap="xl" paddingVertical="md" paddingHorizontal="lg" width="100%">
				<Column gap="xs">
					<Text color={colors.text} size="md">
						Good {dayPeriod},
					</Text>
					<Text color={colors.text} size="lg" weight="bold">
						{displayName} 👋
					</Text>
				</Column>

				<Column gap="xl">
					<Column gap="sm">
						<Row align="center" justify="space-between">
							<Text color={colors.text} size="md" weight="bold">
								My Next Event
							</Text>
							<Button onPress={() => router.push("/events")} size="sm" variant="link">
								See all
							</Button>
						</Row>
						<Card padding="md" shadow="lg">
							<Column gap="lg">
								<Column alignSelf="flex-start">
									<Badge icon="circleFilled" variant={nextEventStatus === "live" ? "success" : "accent"}>
										{nextEventStatus === "live" ? "Live now" : "Upcoming"}
									</Badge>
								</Column>

								<Column gap="xs">
									<Text color={colors.text} size="lg" weight="bold">
										{nextEvent.title}
									</Text>
									<Text color={colors.textSecondary} lineHeight={24} numberOfLines={2} size="md">
										{nextEventDescription}
									</Text>
								</Column>

								<Column gap="sm">
									<Row align="center" gap="md">
										<Icon color={colors.text} name="calendar" size={20} />
										<Text color={colors.textSecondary} size="md">
											{nextEventDate}
										</Text>
									</Row>
									<Row align="center" gap="md">
										<Icon color={colors.text} name="clock" size={20} />
										<Text color={colors.textSecondary} size="md">
											{nextEventTimeRange}
										</Text>
									</Row>
									<Row align="center" gap="md">
										<Icon color={colors.text} name="location" size={20} />
										<Text color={colors.textSecondary} size="md">
											{nextEvent.venue}
										</Text>
									</Row>
									<Row align="center" gap="md">
										<Icon color={colors.text} name="users" size={20} />
										<Text color={colors.textSecondary} size="md">
											{nextEventCapacityLabel}
										</Text>
									</Row>
								</Column>

								<Button onPress={() => router.push(`/preview/${nextEvent.id}`)}>View details</Button>
							</Column>
						</Card>
					</Column>

					<Card padding="md" shadow="sm">
						<Column gap="md">
							<Column gap="xs">
								<Text color={colors.text} size="md" weight="bold">
									Want to join an event?
								</Text>
								<Text color={colors.textSecondary} size="sm">
									Enter an invite code to join a private event.
								</Text>
							</Column>

							<Button onPress={() => router.push("/join")} variant="primary">
								Join with Code
							</Button>
						</Column>
					</Card>
				</Column>
			</Column>
		</Screen>
	);
}
