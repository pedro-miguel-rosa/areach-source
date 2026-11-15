import { Stack } from "@/lib/navigation/stack";

export default function AuthLayout() {
	return (
		<Stack>
			<Stack.Screen name="index" />
			<Stack.Screen name="sign-in" />
			<Stack.Screen name="sign-up" />
			<Stack.Screen name="reset-password" />
			<Stack.Screen name="reset-link-sent" />
		</Stack>
	);
}
