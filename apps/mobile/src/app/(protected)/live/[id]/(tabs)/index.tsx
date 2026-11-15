import { useState } from "react";
import { leaveRemoteLiveEvent } from "@/features/events/api";
import { useLiveEvent } from "@/features/events/context";
import { router } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Badge } from "@/lib/ui/badge";
import { Button } from "@/lib/ui/button";
import { Card } from "@/lib/ui/card";
import { Column } from "@/lib/ui/column";
import { Icon } from "@/lib/ui/icon";
import { Row } from "@/lib/ui/row";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";
import { showToast } from "@/lib/ui/toast";
import AReachSpatial from "@/modules/areach-spatial";

export default function EventOverviewScreen() {
	const theme = useTheme();
	const { event } = useLiveEvent();
	const [isExiting, setIsExiting] = useState(false);

	const exitEvent = async () => {
		if (isExiting) {
			return;
		}

		setIsExiting(true);

		try {
			await leaveRemoteLiveEvent(event.remoteId);
		} catch (error) {
			showToast({
				error,
				message: "You left the event, but your attendee status may take a moment to update.",
				tone: "error",
			});
		} finally {
			await AReachSpatial.stopNearbyDiscovery().catch(() => {});
			router.back();
		}
	};

	const eventDateLabel = event.startAt.toLocaleDateString(undefined, {
		weekday: "short",
		month: "short",
		day: "numeric",
		year: "numeric",
	});
	const startTimeLabel = event.startAt.toLocaleTimeString(undefined, {
		hour: "numeric",
		minute: "2-digit",
	});
	const endTimeLabel = event.endAt.toLocaleTimeString(undefined, {
		hour: "numeric",
		minute: "2-digit",
	});
	const attendeeCountLabel = event.capacity
		? `${event.registrationCount} / ${event.capacity} people`
		: `${event.registrationCount} ${event.registrationCount === 1 ? "person" : "people"}`;

	return (
		<Screen scrollable>
			<Column gap="lg" paddingHorizontal="lg" paddingVertical="md">
				<Column gap="sm">
					<Row align="center" gap="md" justify="space-between">
						<Column flex minWidth={0}>
							<Text size="xl" weight="bold">
								{event.title}
							</Text>
						</Column>
						<Badge icon="circleFilled" variant="success">
							Live now
						</Badge>
					</Row>
				</Column>

				<Text color={theme.colors.textSecondary}>{event.description.trim() || "No description has been added for this event yet."}</Text>

				<Card>
					<Column gap="lg">
						<Row align="flex-start" gap="md">
							<Icon color={theme.colors.textSecondary} name="calendar" size={20} />
							<Column flex gap="xxs" minWidth={0}>
								<Text color={theme.colors.textSecondary} numberOfLines={3}>
									{eventDateLabel}
								</Text>
							</Column>
						</Row>
						<Row align="flex-start" gap="md">
							<Icon color={theme.colors.textSecondary} name="clock" size={20} />
							<Column flex gap="xxs" minWidth={0}>
								<Text color={theme.colors.textSecondary} numberOfLines={3}>
									{startTimeLabel} - {endTimeLabel}
								</Text>
							</Column>
						</Row>
						<Row align="flex-start" gap="md">
							<Icon color={theme.colors.textSecondary} name="location" size={20} />
							<Column flex gap="xxs" minWidth={0}>
								<Text color={theme.colors.textSecondary} numberOfLines={3}>
									{event.venue}
								</Text>
							</Column>
						</Row>
						<Row align="flex-start" gap="md">
							<Icon color={theme.colors.textSecondary} name="users" size={20} />
							<Column flex gap="xxs" minWidth={0}>
								<Text color={theme.colors.textSecondary} numberOfLines={3}>
									{attendeeCountLabel}
								</Text>
							</Column>
						</Row>
					</Column>
				</Card>

				<Button loading={isExiting} onPress={() => void exitEvent()} variant="dangerOutline">
					Exit event
				</Button>
			</Column>
		</Screen>
	);
}
