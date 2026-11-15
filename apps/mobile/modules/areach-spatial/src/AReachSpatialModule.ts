import { NativeModule, requireNativeModule } from "expo";

import type {
	AReachSpatialModuleEvents,
	NearbyCredentialDiscovered,
	NearbyLocalIdentity,
	NearbyPeer,
	NearbyRangingMode,
	NearbySessionStatePayload,
} from "./AReachSpatial.types";

export declare class AReachSpatialModule extends NativeModule<AReachSpatialModuleEvents> {
	clearDebugReplay?(): void;
	debugReplayData?(): string | null;
	isBackgroundNearbyInteractionSupported(): boolean;
	isBackgroundResponderActive(): boolean;
	isNearbyInteractionSupported(): boolean;
	nearbyIdentity(): NearbyLocalIdentity;
	nearbyCredentialSnapshot?(): NearbyCredentialDiscovered[];
	nearbyPeerPresenceSnapshot?(): NearbyPeer[];
	nearbySessionStateSnapshot?(): NearbySessionStatePayload;
	resolveNearbyPeer(peerId: string, credential: string, publicKey: string, userId: string): Promise<void>;
	setBackgroundResponderActive(active: boolean): Promise<void>;
	setNearbyRangingMode(mode: NearbyRangingMode): Promise<void>;
	startNearbyDiscovery(eventScope: string, credential: string, transportKey: string, expiresAt: number): Promise<void>;
	stopNearbyDiscovery(): Promise<void>;
	updateNearbyDiscoveryCredential(eventScope: string, credential: string, expiresAt: number): Promise<void>;
}

// This call loads the native module object from the JSI.
const AReachSpatial = requireNativeModule<AReachSpatialModule>("AReachSpatial");

export default AReachSpatial;
