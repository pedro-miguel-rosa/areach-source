import { CreateEventProvider } from "@/features/events/context";
import { router } from "@/lib/navigation/router";
import { Stack } from "@/lib/navigation/stack";
import { useTheme } from "@/lib/theme/hooks";

export default function CreateLayout() {
	const theme = useTheme();

	const handleCancel = () => {
		router.back();
	};

	return (
		<CreateEventProvider>
			<Stack>
				<Stack.Screen name="index">
					<Stack.Header transparent />
					<Stack.Title style={{ color: theme.colors.text }}>Create Event</Stack.Title>
					<Stack.Toolbar placement="left">
						<Stack.Toolbar.Button onPress={handleCancel}>Cancel</Stack.Toolbar.Button>
					</Stack.Toolbar>
				</Stack.Screen>
				<Stack.Screen name="venue">
					<Stack.Header transparent />
					<Stack.Title style={{ color: theme.colors.text }}>Create Event</Stack.Title>
					<Stack.Screen.BackButton>Back</Stack.Screen.BackButton>
				</Stack.Screen>
				<Stack.Screen name="review">
					<Stack.Header transparent />
					<Stack.Title style={{ color: theme.colors.text }}>Review</Stack.Title>
					<Stack.Screen.BackButton>Back</Stack.Screen.BackButton>
				</Stack.Screen>
				<Stack.Screen name="success" options={{ gestureEnabled: false }}>
					<Stack.Header hidden />
				</Stack.Screen>
			</Stack>
		</CreateEventProvider>
	);
}
