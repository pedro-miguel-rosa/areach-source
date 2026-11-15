import { useCreateEventDraft } from "@/features/events/context";
import { useCreateEvent } from "@/features/events/hooks";
import { useSession } from "@/lib/auth/hooks";
import { router } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { Card } from "@/lib/ui/card";
import { Column } from "@/lib/ui/column";
import { Icon } from "@/lib/ui/icon";
import { Row } from "@/lib/ui/row";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";

export default function CreateReviewScreen() {
	const theme = useTheme();
	const { session } = useSession();

	const { isSubmitting, submitCreateEvent } = useCreateEvent();
	const { title, description, eventDate, startTime, endTime, venue, capacity, setCreatedEventId } = useCreateEventDraft();

	const viewerId = session?.user.id ?? "";

	const trimmedTitle = title.trim();
	const trimmedVenue = venue.trim();
	const trimmedDescription = description.trim();

	const capacityNumber = capacity.trim().length > 0 ? Number(capacity) : null;
	const isCapacityValid = capacityNumber === null || (Number.isFinite(capacityNumber) && capacityNumber > 0);

	const canContinueBasic = trimmedTitle.length > 0 && endTime.getTime() > startTime.getTime();
	const canContinueVenue = trimmedVenue.length > 0 && isCapacityValid;

	const eventDateLabel = eventDate.toLocaleDateString("en-US", {
		month: "short",
		day: "numeric",
		year: "numeric",
		weekday: "short",
	});

	const eventTimeRangeLabel = `${startTime.toLocaleTimeString("en-US", {
		hour: "numeric",
		minute: "2-digit",
	})} - ${endTime.toLocaleTimeString("en-US", {
		hour: "numeric",
		minute: "2-digit",
	})}`;

	const handleCreateEvent = async () => {
		if (!viewerId || !canContinueBasic || !canContinueVenue || isSubmitting) {
			return;
		}

		const startAt = new Date(eventDate);
		startAt.setHours(startTime.getHours(), startTime.getMinutes(), 0, 0);
		const endAt = new Date(startAt.getTime() + (endTime.getTime() - startTime.getTime()));

		const localEventId = await submitCreateEvent({
			viewerId,
			title: trimmedTitle,
			description: trimmedDescription,
			venue: trimmedVenue,
			capacity: capacityNumber,
			startAt: startAt.toISOString(),
			endAt: endAt.toISOString(),
		});

		if (localEventId) {
			setCreatedEventId(localEventId);
			router.replace("/create/success");
			return;
		}
	};

	return (
		<Screen headerInset scrollable>
			<Column gap="xl" paddingHorizontal="lg" paddingTop="md">
				<Column gap="md">
					<Text size="sm" weight="bold">
						Event Summary
					</Text>
					<Card>
						<Column gap="md">
							<Column gap="xxs">
								<Text color={theme.colors.textSecondary} size="sm">
									Event Name
								</Text>
								<Text size="sm">{trimmedTitle}</Text>
							</Column>
							<Column gap="xxs">
								<Text color={theme.colors.textSecondary} size="sm">
									Description
								</Text>
								<Text size="sm">{trimmedDescription || "No description"}</Text>
							</Column>
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
									{trimmedVenue}
								</Text>
							</Row>
							<Row align="center" gap="sm" style={{ minHeight: 22 }}>
								<Icon color={theme.colors.textSecondary} name="users" size={17} />
								<Text color={theme.colors.textSecondary} numberOfLines={2} size="sm">
									{capacityNumber ? `${capacityNumber} attendees` : "No capacity limit"}
								</Text>
							</Row>
						</Column>
					</Card>
				</Column>

				<Button disabled={isSubmitting} loading={isSubmitting} onPress={handleCreateEvent}>
					Create Event
				</Button>
			</Column>
		</Screen>
	);
}
