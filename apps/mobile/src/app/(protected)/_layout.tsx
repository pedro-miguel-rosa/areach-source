import { Stack } from "@/lib/navigation/stack";
import { useTheme } from "@/lib/theme/hooks";

export default function ProtectedLayout() {
	const theme = useTheme();

	return (
		<Stack>
			<Stack.Screen name="(tabs)">
				<Stack.Header hidden />
			</Stack.Screen>
			<Stack.Screen name="profile/edit">
				<Stack.Header transparent />
				<Stack.Title style={{ color: theme.colors.text }}>Edit Profile</Stack.Title>
			</Stack.Screen>
			<Stack.Screen name="profile/change-password">
				<Stack.Header transparent />
				<Stack.Title style={{ color: theme.colors.text }}>Change Password</Stack.Title>
			</Stack.Screen>
			<Stack.Screen name="profile/change-email">
				<Stack.Header transparent />
				<Stack.Title style={{ color: theme.colors.text }}>Change Email</Stack.Title>
			</Stack.Screen>
			<Stack.Screen name="profile/appearance">
				<Stack.Header transparent />
				<Stack.Title style={{ color: theme.colors.text }}>Appearance</Stack.Title>
			</Stack.Screen>
			<Stack.Screen name="profile/help-support">
				<Stack.Header transparent />
				<Stack.Title style={{ color: theme.colors.text }}>Help & Support</Stack.Title>
			</Stack.Screen>
			<Stack.Screen name="profile/about">
				<Stack.Header transparent />
				<Stack.Title style={{ color: theme.colors.text }}>About AReach</Stack.Title>
			</Stack.Screen>
			<Stack.Screen name="profile/privacy">
				<Stack.Header transparent />
				<Stack.Title style={{ color: theme.colors.text }}>Privacy</Stack.Title>
			</Stack.Screen>
			<Stack.Screen name="profile/blocked">
				<Stack.Header transparent />
				<Stack.Title style={{ color: theme.colors.text }}>Blocked Users</Stack.Title>
			</Stack.Screen>
			<Stack.Screen name="profile/delete-account">
				<Stack.Header transparent />
				<Stack.Title style={{ color: theme.colors.text }}>Delete Account</Stack.Title>
			</Stack.Screen>
			<Stack.Screen name="create" options={{ gestureEnabled: false }}>
				<Stack.Header hidden />
			</Stack.Screen>
			<Stack.Screen name="join">
				<Stack.Title style={{ color: theme.colors.text }}>Join with Code</Stack.Title>
			</Stack.Screen>
			<Stack.Screen name="preview/[id]">
				<Stack.Header hidden />
			</Stack.Screen>
			<Stack.Screen name="live/[id]" options={{ gestureEnabled: false }}>
				<Stack.Header hidden />
			</Stack.Screen>
		</Stack>
	);
}
