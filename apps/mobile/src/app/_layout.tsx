import { SplashScreen, useSegments } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { useEffect } from "react";
import { useColorScheme } from "react-native";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { syncEvents } from "@/features/events/sync";
import { useSession } from "@/lib/auth/hooks";
import { useDatabaseMigrations } from "@/lib/db/hooks";
import { Stack } from "@/lib/navigation/stack";
import { ThemeProvider } from "@/lib/theme/hooks";
import { showToast, Toast } from "@/lib/ui/toast";

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
	const { session, isPending: isSessionPending } = useSession();
	const { isPending: isDatabasePending, error: databaseError } = useDatabaseMigrations();
	const segments = useSegments();
	const isDark = useColorScheme() === "dark";

	const userId = session?.user.id ?? "";

	useEffect(() => {
		if (!isSessionPending && !isDatabasePending) {
			SplashScreen.hideAsync();
		}
	}, [isDatabasePending, isSessionPending]);

	useEffect(() => {
		if (!userId || isDatabasePending) {
			return;
		}

		void syncEvents(userId).catch((error) => {
			const message = error instanceof Error && error.message ? error.message : "Some updates may take a little longer to appear.";

			showToast({ error, message, tone: "error", durationMs: 5000 });
		});
	}, [isDatabasePending, userId]);

	if (isSessionPending || isDatabasePending) {
		return null; // SplashScreen
	}

	if (databaseError) {
		throw databaseError;
	}

	const isAuthenticated = Boolean(session);
	const isAuthRoute = segments.length === 1 && segments[0] === "(auth)";
	const statusBarStyle = isAuthRoute ? "light" : isDark ? "light" : "dark";

	return (
		<ThemeProvider>
			<SafeAreaProvider>
				<StatusBar style={statusBarStyle} animated />

				<Toast />

				<Stack>
					<Stack.Protected guard={!isAuthenticated}>
						<Stack.Screen name="(auth)">
							<Stack.Header hidden />
						</Stack.Screen>
					</Stack.Protected>

					<Stack.Protected guard={isAuthenticated}>
						<Stack.Screen name="(protected)">
							<Stack.Header hidden />
						</Stack.Screen>
					</Stack.Protected>
				</Stack>
			</SafeAreaProvider>
		</ThemeProvider>
	);
}
