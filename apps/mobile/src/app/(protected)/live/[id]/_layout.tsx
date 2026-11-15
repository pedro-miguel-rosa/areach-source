import { useEffect, useRef } from "react";
import { ActivityIndicator, AppState } from "react-native";
import { refreshRemoteLiveAttendance, resolveRemoteNearbyCredentials } from "@/features/events/api";
import { type LiveEvent, LiveEventProvider } from "@/features/events/context";
import { useEventById } from "@/features/events/hooks";
import { upsertLocalEventAttendees } from "@/features/events/repository";
import { syncEventAttendees } from "@/features/events/sync";
import type { LiveEventAttendance } from "@/features/events/types";
import {
	startAReachLiveEventActivity,
	stopAReachLiveEventActivities,
	syncAReachLiveEventActivityState,
} from "@/features/presence/activity";
import { NearbyPeersProvider } from "@/features/presence/context";
import { useSession } from "@/lib/auth/hooks";
import { Redirect } from "@/lib/navigation/redirect";
import { router, usePathParam } from "@/lib/navigation/router";
import { Stack } from "@/lib/navigation/stack";
import { useTheme } from "@/lib/theme/hooks";
import { Column } from "@/lib/ui/column";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";
import { showToast } from "@/lib/ui/toast";
import AReachSpatial from "@/modules/areach-spatial";

const ATTENDEE_REFRESH_MS = 20_000;
const NEARBY_CREDENTIAL_RETRY_MS = 2_000;
const NEARBY_CREDENTIAL_RETRY_WINDOW_MS = 30_000;

export default function LiveEventLayout() {
	const theme = useTheme();
	const eventId = usePathParam("id");
	const { session, isPending: isSessionPending } = useSession();
	const userId = session?.user.id ?? "";
	const { data: event, isPending: isEventPending } = useEventById(userId, eventId);

	if (isSessionPending || isEventPending) {
		return (
			<Screen>
				<Column align="center" flex gap="md" justify="center" paddingHorizontal="xl">
					<ActivityIndicator color={theme.colors.primary} size="large" />
					<Column align="center" gap="xs">
						<Text size="lg" weight="semibold">
							Preparing live event
						</Text>
						<Text align="center" color={theme.colors.textSecondary} size="sm">
							Checking the event and starting nearby detection.
						</Text>
					</Column>
				</Column>
			</Screen>
		);
	}

	if (!session || !event) {
		return <Redirect href="/" />;
	}

	const isLive = event.startAt <= new Date() && event.endAt > new Date();

	if (!isLive || !event.remoteId) {
		return <Redirect href={`/preview/${eventId}`} />;
	}

	const liveEvent: LiveEvent = {
		...event,
		remoteId: event.remoteId,
	};

	return <LiveEventExperience event={liveEvent} userId={session.user.id} />;
}

function LiveEventExperience({ event, userId }: { event: LiveEvent; userId: string }) {
	const nearbyCredentialRef = useRef<{ credential: string; eventScope: string; expiresAt: number } | undefined>(undefined);
	const isNearbyDiscoveryRunningRef = useRef(false);
	const isLiveActivityStartedRef = useRef(false);
	const credentialResolutionQueueRef = useRef(new Map<string, Set<string>>());
	const credentialRetryAfterRef = useRef(new Map<string, number>());
	const credentialRetryStartedAtRef = useRef(new Map<string, number>());
	const eventEndsAt = event.endAt.getTime();
	const liveActivityTitle = event.title.trim() || "Live event";

	// Keep attendance, attendee profiles, credentials, and native discovery current.
	useEffect(() => {
		let isMounted = true;
		let isAttendanceRequestRunning = false;
		let isAttendeeRequestRunning = false;
		let didShowAttendanceWarning = false;
		let didShowAttendeeWarning = false;
		let didShowNearbyWarning = false;
		let credentialResolutionTimer: ReturnType<typeof setTimeout> | undefined;
		let isCredentialResolutionRunning = false;
		let isLiveActivityRequestRunning = false;

		const applyNearbyCredential = async (attendance: LiveEventAttendance) => {
			if (!AReachSpatial.isNearbyInteractionSupported()) {
				return;
			}

			const expiresAt = new Date(attendance.nearbyCredentialExpiresAt).getTime();
			const currentCredential = nearbyCredentialRef.current;

			if (
				currentCredential?.eventScope === attendance.nearbyEventScope &&
				currentCredential.credential === attendance.nearbyCredential &&
				currentCredential.expiresAt > Date.now()
			) {
				return;
			}

			try {
				if (isNearbyDiscoveryRunningRef.current) {
					await AReachSpatial.updateNearbyDiscoveryCredential(attendance.nearbyEventScope, attendance.nearbyCredential, expiresAt);
				} else {
					await AReachSpatial.startNearbyDiscovery(
						attendance.nearbyEventScope,
						attendance.nearbyCredential,
						attendance.nearbyTransportKey,
						expiresAt,
					);

					if (!isMounted) {
						await AReachSpatial.stopNearbyDiscovery();
						return;
					}

					isNearbyDiscoveryRunningRef.current = true;
				}

				nearbyCredentialRef.current = {
					credential: attendance.nearbyCredential,
					eventScope: attendance.nearbyEventScope,
					expiresAt,
				};
			} catch (error) {
				if (!didShowNearbyWarning) {
					didShowNearbyWarning = true;
					const message = error instanceof Error && error.message ? error.message : "Unable to start nearby attendee detection.";

					showToast({ error, message, tone: "error", durationMs: 5000 });
				}
			}
		};

		const ensureLiveActivity = async () => {
			if (!isMounted || !isNearbyDiscoveryRunningRef.current || isLiveActivityStartedRef.current || isLiveActivityRequestRunning) {
				return;
			}
			if (!AReachSpatial.isBackgroundNearbyInteractionSupported()) {
				await AReachSpatial.setBackgroundResponderActive(false).catch(() => {});
				return;
			}

			isLiveActivityRequestRunning = true;
			try {
				const activity = await startAReachLiveEventActivity(
					{
						endsAt: eventEndsAt,
						eventId: event.remoteId,
						status: "Nearby detection active",
						title: liveActivityTitle,
					},
					`areach://live/${event.id}`,
				);
				if (!isMounted) {
					// A start can finish after navigation cleanup. Reconcile the
					// system-owned activity before the native responder is left on.
					await stopAReachLiveEventActivities({
						endsAt: eventEndsAt,
						eventId: event.remoteId,
						status: "Nearby detection ended",
						title: liveActivityTitle,
					}).catch(() => {});
					return;
				}
				if (isMounted) {
					isLiveActivityStartedRef.current = activity !== undefined;
				}
			} catch (error) {
				if (!didShowNearbyWarning) {
					didShowNearbyWarning = true;
					const message =
						error instanceof Error && error.message ? error.message : "Background attendee detection needs Live Activities enabled.";
					showToast({ error, message, tone: "error", durationMs: 5000 });
				}
			} finally {
				isLiveActivityRequestRunning = false;
			}
		};

		const refreshAttendance = async () => {
			if (isAttendanceRequestRunning || Date.now() >= eventEndsAt) {
				return;
			}

			isAttendanceRequestRunning = true;

			try {
				const attendance = await refreshRemoteLiveAttendance(event.remoteId, AReachSpatial.nearbyIdentity());

				if (isMounted) {
					await applyNearbyCredential(attendance);
					await ensureLiveActivity();
				}
			} catch (error) {
				if (!didShowAttendanceWarning) {
					didShowAttendanceWarning = true;
					const message = error instanceof Error && error.message ? error.message : "Unable to update live attendance.";

					showToast({ error, message, tone: "error", durationMs: 5000 });
				}
			} finally {
				isAttendanceRequestRunning = false;
			}
		};

		const refreshAttendees = async () => {
			if (isAttendeeRequestRunning || Date.now() >= eventEndsAt) {
				return;
			}

			isAttendeeRequestRunning = true;

			try {
				await syncEventAttendees(userId, event.id, event.remoteId);
				if (isMounted) {
					requeueNativeCredentialSnapshot();
				}
			} catch (error) {
				if (!didShowAttendeeWarning) {
					didShowAttendeeWarning = true;
					const message = error instanceof Error && error.message ? error.message : "Unable to update live attendees.";

					showToast({ error, message, tone: "error", durationMs: 5000 });
				}
			} finally {
				isAttendeeRequestRunning = false;
			}
		};

		function scheduleCredentialResolution(delayMs = 200) {
			if (credentialResolutionTimer || !isMounted) {
				return;
			}

			credentialResolutionTimer = setTimeout(() => {
				credentialResolutionTimer = undefined;
				void flushCredentialResolutions();
			}, delayMs);
		}

		function queueCredentialResolution(credential: string, peerId: string, force = false) {
			const now = Date.now();

			if (!force && (credentialRetryAfterRef.current.get(credential) ?? 0) > now) {
				return;
			}
			if (!credentialRetryStartedAtRef.current.has(credential)) {
				credentialRetryStartedAtRef.current.set(credential, now);
			}

			const peerIds = credentialResolutionQueueRef.current.get(credential) ?? new Set<string>();
			peerIds.add(peerId);
			credentialResolutionQueueRef.current.set(credential, peerIds);
			scheduleCredentialResolution();
		}

		function requeueNativeCredentialSnapshot() {
			const now = Date.now();

			for (const { credential, peerId } of AReachSpatial.nearbyCredentialSnapshot?.() ?? []) {
				credentialRetryAfterRef.current.delete(credential);
				credentialRetryStartedAtRef.current.set(credential, now);
				queueCredentialResolution(credential, peerId, true);
			}
		}

		async function flushCredentialResolutions() {
			if (isCredentialResolutionRunning || !isMounted) {
				return;
			}

			const now = Date.now();
			const entries = [...credentialResolutionQueueRef.current.entries()]
				.filter(([credential]) => (credentialRetryAfterRef.current.get(credential) ?? 0) <= now)
				.slice(0, 100);

			if (entries.length === 0) {
				const nextRetryAt = Math.min(
					...[...credentialResolutionQueueRef.current.keys()].map((credential) => credentialRetryAfterRef.current.get(credential) ?? now),
				);

				if (Number.isFinite(nextRetryAt)) {
					scheduleCredentialResolution(Math.max(200, nextRetryAt - now));
				}

				return;
			}

			for (const [credential] of entries) {
				credentialResolutionQueueRef.current.delete(credential);
			}
			isCredentialResolutionRunning = true;

			try {
				const resolvedIdentities = await resolveRemoteNearbyCredentials(
					event.remoteId,
					entries.map(([credential]) => credential),
				);

				if (!isMounted) {
					return;
				}

				const identitiesByCredential = new Map(resolvedIdentities.map((identity) => [identity.credential, identity]));
				await upsertLocalEventAttendees(
					userId,
					event.id,
					resolvedIdentities.map(({ attendee }) => attendee),
				);

				await Promise.all(
					entries.flatMap(([credential, peerIds]) => {
						const identity = identitiesByCredential.get(credential);

						if (!identity) {
							const retryStartedAt = credentialRetryStartedAtRef.current.get(credential) ?? Date.now();
							if (Date.now() - retryStartedAt < NEARBY_CREDENTIAL_RETRY_WINDOW_MS) {
								credentialResolutionQueueRef.current.set(credential, peerIds);
								credentialRetryAfterRef.current.set(credential, Date.now() + NEARBY_CREDENTIAL_RETRY_MS);
							} else {
								credentialRetryAfterRef.current.delete(credential);
								credentialRetryStartedAtRef.current.delete(credential);
							}
							return [];
						}

						credentialRetryAfterRef.current.delete(credential);
						credentialRetryStartedAtRef.current.delete(credential);
						return [...peerIds]
							.filter((peerId) => peerId === identity.peerId)
							.map((peerId) => AReachSpatial.resolveNearbyPeer(peerId, credential, identity.publicKey, identity.attendee.userId));
					}),
				);
			} catch {
				for (const [credential, peerIds] of entries) {
					credentialResolutionQueueRef.current.set(credential, peerIds);
					credentialRetryAfterRef.current.set(credential, Date.now() + 5000);
				}
			} finally {
				isCredentialResolutionRunning = false;

				if (isMounted && credentialResolutionQueueRef.current.size > 0) {
					const now = Date.now();
					const nextRetryAt = Math.min(
						...[...credentialResolutionQueueRef.current.keys()].map((credential) => credentialRetryAfterRef.current.get(credential) ?? now),
					);
					scheduleCredentialResolution(Math.max(200, nextRetryAt - now));
				}
			}
		}

		const credentialSubscription = AReachSpatial.addListener("onNearbyCredentialDiscovered", ({ credential, peerId }) => {
			queueCredentialResolution(credential, peerId);
		});
		requeueNativeCredentialSnapshot();

		const exitEvent = () => {
			router.back();
		};
		const eventEndTimeout = setTimeout(exitEvent, Math.max(0, eventEndsAt - Date.now()));
		const liveEventRefreshInterval = setInterval(() => {
			void refreshAttendance();
			void refreshAttendees();
		}, ATTENDEE_REFRESH_MS);
		const liveActivityInterval = setInterval(() => {
			if (!isMounted) {
				return;
			}

			void syncAReachLiveEventActivityState().then((isActive) => {
				if (!isMounted) {
					return;
				}

				isLiveActivityStartedRef.current = isActive;
				if (!isActive) {
					void ensureLiveActivity();
				}
			});
		}, 10_000);
		const appStateSubscription = AppState.addEventListener("change", (state) => {
			if (state !== "active") {
				return;
			}

			if (Date.now() >= eventEndsAt) {
				exitEvent();
				return;
			}

			void refreshAttendance();
			void refreshAttendees();
			requeueNativeCredentialSnapshot();
			void syncAReachLiveEventActivityState().then((isActive) => {
				if (isMounted) {
					isLiveActivityStartedRef.current = isActive;
					if (!isActive) {
						void ensureLiveActivity();
					}
				}
			});
		});

		void refreshAttendance();
		void refreshAttendees();

		return () => {
			isMounted = false;
			credentialSubscription.remove();
			appStateSubscription.remove();
			clearTimeout(eventEndTimeout);
			clearInterval(liveEventRefreshInterval);
			clearInterval(liveActivityInterval);
			if (credentialResolutionTimer) {
				clearTimeout(credentialResolutionTimer);
			}
			credentialResolutionQueueRef.current.clear();
			credentialRetryAfterRef.current.clear();
			credentialRetryStartedAtRef.current.clear();
			nearbyCredentialRef.current = undefined;
			isLiveActivityStartedRef.current = false;

			if (isNearbyDiscoveryRunningRef.current) {
				isNearbyDiscoveryRunningRef.current = false;
				void AReachSpatial.stopNearbyDiscovery().catch(() => {});
			}
			void stopAReachLiveEventActivities({
				endsAt: eventEndsAt,
				eventId: event.remoteId,
				status: "Nearby detection ended",
				title: liveActivityTitle,
			}).catch(() => {});
		};
	}, [event.id, event.remoteId, eventEndsAt, liveActivityTitle, userId]);

	return (
		<NearbyPeersProvider>
			<LiveEventProvider value={{ event }}>
				<Stack>
					<Stack.Screen name="(tabs)">
						<Stack.Header hidden />
					</Stack.Screen>
					<Stack.Screen name="attendee/[attendeeId]">
						<Stack.Header />
					</Stack.Screen>
					<Stack.Screen name="attendee/[attendeeId]/report">
						<Stack.Header />
						<Stack.Title>Report Attendee</Stack.Title>
					</Stack.Screen>
				</Stack>
			</LiveEventProvider>
		</NearbyPeersProvider>
	);
}
