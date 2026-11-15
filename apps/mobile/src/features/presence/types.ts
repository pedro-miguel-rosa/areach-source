import type { NearbyPeer } from "@/modules/areach-spatial";

export type NearbyPeerState = NearbyPeer & {
	distanceUpdatedAt?: number;
	distanceFreshness?: "fresh" | "stale";
	lastUpdatedAt: number;
};
