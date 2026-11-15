import { createContext, type ReactNode, useContext, useEffect, useState } from "react";
import AReachSpatial, { type NearbySessionStatePayload } from "@/modules/areach-spatial";
import { PEER_DISTANCE_DISPLAY_RETENTION_MS, PEER_DISTANCE_FRESH_MS } from "./constants";
import type { NearbyPeerState } from "./types";

const NearbyPeersContext = createContext<Record<string, NearbyPeerState> | null>(null);
const NearbySessionStateContext = createContext<NearbySessionStatePayload | null>(null);

export function NearbyPeersProvider({ children }: { children: ReactNode }) {
	const [nearbyPeers, setNearbyPeers] = useState<Record<string, NearbyPeerState>>({});
	const [sessionState, setSessionState] = useState<NearbySessionStatePayload>(() => {
		const nativeState = AReachSpatial.nearbySessionStateSnapshot?.();
		return (
			nativeState ?? {
				state: AReachSpatial.isNearbyInteractionSupported() ? "stopped" : "unsupported",
			}
		);
	});

	useEffect(() => {
		const updateSubscription = AReachSpatial.addListener("onNearbyPeerUpdate", (peer) => {
			setNearbyPeers((currentPeers) => {
				const now = Date.now();
				const currentPeer = currentPeers[peer.peerId];
				return {
					...currentPeers,
					[peer.peerId]: {
						...currentPeer,
						...peer,
						lastUpdatedAt: now,
						distanceUpdatedAt: peer.distance !== undefined ? now : currentPeer?.distanceUpdatedAt,
						distanceFreshness: peer.distance !== undefined ? "fresh" : currentPeer?.distanceFreshness,
					},
				};
			});
		});

		const lostSubscription = AReachSpatial.addListener("onNearbyPeerLost", (peer) => {
			setNearbyPeers((currentPeers) => {
				const currentPeer = currentPeers[peer.peerId];

				if (peer.stillNearby && currentPeer) {
					return {
						...currentPeers,
						[peer.peerId]: {
							...currentPeer,
							lastUpdatedAt: Date.now(),
						},
					};
				}

				const nextPeers = { ...currentPeers };
				delete nextPeers[peer.peerId];
				return nextPeers;
			});
		});

		const stateSubscription = AReachSpatial.addListener("onNearbySessionState", setSessionState);
		const nativeState = AReachSpatial.nearbySessionStateSnapshot?.();
		if (nativeState) {
			setSessionState(nativeState);
		}
		const nativeSnapshot = AReachSpatial.nearbyPeerPresenceSnapshot?.() ?? [];
		if (nativeSnapshot.length > 0) {
			const now = Date.now();
			setNearbyPeers((currentPeers) => {
				let didChange = false;
				const nextPeers = { ...currentPeers };

				for (const peer of nativeSnapshot) {
					const currentPeer = currentPeers[peer.peerId];
					if (currentPeer) {
						if (currentPeer.distance === undefined && peer.distance !== undefined) {
							nextPeers[peer.peerId] = {
								...currentPeer,
								distance: peer.distance,
								distanceUpdatedAt: now,
								distanceFreshness: "fresh",
							};
							didChange = true;
						}
						continue;
					}

					nextPeers[peer.peerId] = {
						...peer,
						lastUpdatedAt: now,
						distanceUpdatedAt: peer.distance !== undefined ? now : undefined,
						distanceFreshness: peer.distance !== undefined ? "fresh" : undefined,
					};
					didChange = true;
				}

				return didChange ? nextPeers : currentPeers;
			});
		}

		return () => {
			updateSubscription.remove();
			lostSubscription.remove();
			stateSubscription.remove();
		};
	}, []);

	useEffect(() => {
		const pruneInterval = setInterval(() => {
			const now = Date.now();

			setNearbyPeers((currentPeers) => updateDistanceFreshness(currentPeers, now));
		}, 500);

		return () => {
			clearInterval(pruneInterval);
		};
	}, []);

	return (
		<NearbySessionStateContext.Provider value={sessionState}>
			<NearbyPeersContext.Provider value={nearbyPeers}>{children}</NearbyPeersContext.Provider>
		</NearbySessionStateContext.Provider>
	);
}

export function useNearbyPeers() {
	const context = useContext(NearbyPeersContext);

	if (!context) {
		throw new Error("useNearbyPeers must be used within NearbyPeersProvider");
	}

	return { nearbyPeers: context };
}

export function useNearbySessionState() {
	const context = useContext(NearbySessionStateContext);

	if (!context) {
		throw new Error("useNearbySessionState must be used within NearbyPeersProvider");
	}

	return context;
}

function updateDistanceFreshness(currentPeers: Record<string, NearbyPeerState>, now: number) {
	let didChange = false;
	const nextPeers: Record<string, NearbyPeerState> = {};

	for (const [peerId, peer] of Object.entries(currentPeers)) {
		const distanceUpdatedAt = peer.distanceUpdatedAt ?? peer.lastUpdatedAt;
		const distanceAge = now - distanceUpdatedAt;
		if (peer.distance !== undefined && distanceAge > PEER_DISTANCE_DISPLAY_RETENTION_MS) {
			didChange = true;
			const { distance: _distance, distanceUpdatedAt: _distanceUpdatedAt, distanceFreshness: _distanceFreshness, ...nearbyPeer } = peer;
			nextPeers[peerId] = nearbyPeer;
			continue;
		}

		if (peer.distance !== undefined && distanceAge > PEER_DISTANCE_FRESH_MS && peer.distanceFreshness !== "stale") {
			didChange = true;
			nextPeers[peerId] = { ...peer, distanceFreshness: "stale" };
			continue;
		}

		nextPeers[peerId] = peer;
	}

	return didChange ? nextPeers : currentPeers;
}
