import { useCallback, useEffect, useMemo, useState } from "react";
import { ActivityIndicator, AppState, Linking, StyleSheet } from "react-native";
import { useLiveEvent } from "@/features/events/context";
import { useEventAttendees } from "@/features/events/hooks";
import { useNearbySessionState } from "@/features/presence/context";
import { useSession } from "@/lib/auth/hooks";
import { router, useIsFocused } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { Column } from "@/lib/ui/column";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";
import { View } from "@/lib/ui/view";
import { AReachSpatialView, type CameraStatePayload, type SpatialOverlayPressPayload } from "@/modules/areach-spatial";

export default function EventCameraScreen() {
	const theme = useTheme();
	const isFocused = useIsFocused();

	const { session } = useSession();
	const { event } = useLiveEvent();

	const userId = session?.user.id ?? "";

	const { data: attendees } = useEventAttendees(userId, event.id);
	const sessionState = useNearbySessionState();

	const [cameraState, setCameraState] = useState<CameraStatePayload>();
	const [cameraAttempt, setCameraAttempt] = useState(0);

	const attendeeProfiles = useMemo(
		() => attendees.map(({ askMeAbout, headline, name, userId }) => ({ askMeAbout, headline, name, userId })),
		[attendees],
	);

	const handleOverlayPress = useCallback(
		(payload: SpatialOverlayPressPayload) => {
			if (payload.action === "open_topics") {
				return;
			}

			router.push(`/live/${event.id}/attendee/${payload.userId}`);
		},
		[event.id],
	);

	useEffect(() => {
		if (isFocused) {
			setCameraState(undefined);
		}
	}, [isFocused]);

	useEffect(() => {
		if (cameraState?.reason !== "permission_denied") {
			return;
		}

		let didLeaveApp = false;
		const subscription = AppState.addEventListener("change", (state) => {
			if (state !== "active") {
				didLeaveApp = true;
				return;
			}

			if (didLeaveApp) {
				setCameraState(undefined);
				setCameraAttempt((currentAttempt) => currentAttempt + 1);
			}
		});

		return () => {
			subscription.remove();
		};
	}, [cameraState?.reason]);

	let statusTitle: string | undefined;
	let statusMessage: string | undefined;
	let isStatusLoading = false;

	if (!cameraState || cameraState.state === "initializing") {
		statusTitle = "Preparing camera";
		statusMessage = "Starting the camera and AR tracking.";
		isStatusLoading = true;
	} else if (cameraState.state === "limited") {
		statusTitle = "Improving camera tracking";
		statusMessage = cameraState.message ?? "Move your iPhone slowly while AR tracking recovers.";
		isStatusLoading = true;
	} else if (cameraState.state === "interrupted") {
		statusTitle = "Camera paused";
		statusMessage = "Waiting for the camera to resume.";
		isStatusLoading = true;
	} else if (cameraState.state === "failed" || cameraState.state === "unsupported") {
		statusTitle = "Camera unavailable";
		statusMessage = cameraState.message ?? "AR camera tracking is unavailable.";
	} else if (sessionState.state === "stopped") {
		statusTitle = "Preparing nearby detection";
		statusMessage = "Connecting to attendees in this event.";
		isStatusLoading = true;
	} else if (sessionState.state === "waiting") {
		statusTitle = "Reconnecting nearby detection";
		statusMessage = sessionState.message ?? "Waiting for the local network to become available.";
		isStatusLoading = true;
	} else if (sessionState.state === "failed") {
		statusTitle = "Nearby detection unavailable";
		statusMessage = sessionState.message ?? "Nearby attendee detection is unavailable.";
	} else if (sessionState.state === "unsupported") {
		statusTitle = "Nearby detection unavailable";
		statusMessage = sessionState.message ?? "Nearby attendee detection is not supported on this iPhone.";
	}

	if (!isFocused) {
		return <Screen>{null}</Screen>;
	}

	return (
		<Screen>
			<AReachSpatialView
				attendeeProfiles={attendeeProfiles}
				key={cameraAttempt}
				onCameraStateChange={setCameraState}
				onOverlayPress={handleOverlayPress}
				style={{ flex: 1 }}
			/>
			{statusTitle && statusMessage ? (
				<View
					accessibilityLiveRegion="polite"
					accessibilityRole={isStatusLoading ? "progressbar" : "alert"}
					style={[StyleSheet.absoluteFill, { backgroundColor: theme.colors.background, elevation: 100, zIndex: 100 }]}
				>
					<Column align="center" flex gap="lg" justify="center" paddingHorizontal="xl">
						{isStatusLoading ? <ActivityIndicator color={theme.colors.primary} size="large" /> : null}
						<Column align="center" gap="xs">
							<Text align="center" size="lg" weight="semibold">
								{statusTitle}
							</Text>
							<Text align="center" color={theme.colors.textSecondary} size="sm">
								{statusMessage}
							</Text>
						</Column>
						{cameraState?.reason === "permission_denied" ? (
							<Button onPress={() => void Linking.openSettings()} size="sm" variant="surface">
								Open Settings
							</Button>
						) : null}
					</Column>
				</View>
			) : null}
		</Screen>
	);
}
