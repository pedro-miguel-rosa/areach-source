import { useCreateEventDraft } from "@/features/events/context";
import { router } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { Column } from "@/lib/ui/column";
import { NumberInput } from "@/lib/ui/number-input";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";
import { TextInput } from "@/lib/ui/text-input";

export default function CreateVenueScreen() {
	const theme = useTheme();
	const { setVenue, venue, capacity, setCapacity } = useCreateEventDraft();

	const capacityNumber = capacity.trim().length > 0 ? Number(capacity) : null;
	const isCapacityValid = capacityNumber === null || (Number.isFinite(capacityNumber) && capacityNumber > 0);
	const canContinue = venue.trim().length > 0 && isCapacityValid;

	return (
		<Screen headerInset scrollable>
			<Column gap="xl" paddingHorizontal="lg" paddingTop="md">
				<Column gap="md">
					<Text size="sm" weight="bold">
						Venue
					</Text>
					<TextInput label="Venue" onChange={setVenue} placeholder="Enter venue" value={venue} />
				</Column>

				<Column gap="xs">
					<Text size="sm" weight="bold">
						Capacity
					</Text>
					<NumberInput label="Capacity" onChange={setCapacity} placeholder="Enter capacity" value={capacity} />
					<Text color={isCapacityValid ? theme.colors.textSecondary : theme.colors.error} size="xs">
						Max number of attendees
					</Text>
				</Column>

				<Button disabled={!canContinue} onPress={() => router.push("/create/review" as never)}>
					Next
				</Button>
			</Column>
		</Screen>
	);
}
