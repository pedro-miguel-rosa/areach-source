import { useCreateEventDraft } from "@/features/events/context";
import { router } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { Column } from "@/lib/ui/column";
import { DateTimeInput } from "@/lib/ui/date-time-input";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";
import { TextInput } from "@/lib/ui/text-input";

export default function CreateBasicScreen() {
	const theme = useTheme();

	const { title, setTitle, description, setDescription, eventDate, setEventDate, startTime, setStartTime, endTime, setEndTime } =
		useCreateEventDraft();

	const canContinue = title.trim().length > 0 && endTime.getTime() > startTime.getTime();

	const handleStartTimeChange = (nextStartTime: Date) => {
		setStartTime(nextStartTime);

		if (endTime.getTime() <= nextStartTime.getTime()) {
			setEndTime(new Date(nextStartTime.getTime() + 60 * 60 * 1000));
		}
	};

	const handleEndTimeChange = (nextEndTime: Date) => {
		if (nextEndTime.getTime() <= startTime.getTime()) {
			setEndTime(new Date(startTime.getTime() + 60 * 60 * 1000));
			return;
		}

		setEndTime(nextEndTime);
	};

	return (
		<Screen headerInset scrollable>
			<Column gap="xl" paddingHorizontal="lg" paddingTop="md">
				<Column gap="md">
					<Text size="sm" weight="bold">
						Basic Information
					</Text>
					<TextInput label="Event Name" value={title} onChange={setTitle} placeholder="e.g. AI & Coffee Networking" />
					<Column gap="xs">
						<TextInput
							label="Description"
							value={description}
							onChange={setDescription}
							placeholder="Tell people about your event..."
							maxLength={500}
							multiline
							numberOfLines={5}
							textAlignVertical="top"
						/>
						<Text align="right" color={theme.colors.textSecondary} size="xs">
							{description.length}/500
						</Text>
					</Column>
				</Column>

				<Column gap="md">
					<Text size="sm" weight="bold">
						Date & Time
					</Text>
					<DateTimeInput
						label="Date"
						value={eventDate}
						onChange={setEventDate}
						renderValue={(date) =>
							date.toLocaleDateString("en-US", {
								month: "short",
								day: "numeric",
								year: "numeric",
							})
						}
						title="Select date"
						minimumDate={new Date()}
						mode="date"
					/>
					<DateTimeInput
						label="Start Time"
						mode="time"
						value={startTime}
						onChange={handleStartTimeChange}
						renderValue={(date) =>
							date.toLocaleTimeString("en-US", {
								hour: "numeric",
								minute: "2-digit",
							})
						}
						title="Select start time"
					/>
					<DateTimeInput
						label="End Time"
						mode="time"
						value={endTime}
						onChange={handleEndTimeChange}
						renderValue={(date) =>
							date.toLocaleTimeString("en-US", {
								hour: "numeric",
								minute: "2-digit",
							})
						}
						title="Select end time"
					/>
				</Column>

				<Button disabled={!canContinue} onPress={() => router.push("/create/venue")}>
					Next
				</Button>
			</Column>
		</Screen>
	);
}
