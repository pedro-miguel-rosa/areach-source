import type { StyleProp, ViewStyle } from "react-native";

export type AReachSpatialModuleEvents = {
	onNearbyCredentialDiscovered: (params: NearbyCredentialDiscovered) => void;
	onNearbyPeerLost: (params: NearbyPeerLost) => void;
	onNearbyPeerUpdate: (params: NearbyPeer) => void;
	onNearbySessionState: (params: NearbySessionStatePayload) => void;
};

export type NearbyCredentialDiscovered = {
	credential: string;
	peerId: string;
};

export type NearbyPeerIdentity = {
	peerId: string;
	userId?: string;
};

export type NearbyPeer = NearbyPeerIdentity & {
	distance?: number;
};

export type NearbyPeerLost = NearbyPeerIdentity & {
	reason: string;
	stillNearby: boolean;
};

export type NearbyLocalIdentity = {
	peerId: string;
	publicKey: string;
};

export type NearbyRangingMode = "camera" | "presence" | "proximity";

export type NearbySessionState = "failed" | "ready" | "searching" | "stopped" | "unsupported" | "waiting";

export type NearbySessionStatePayload = {
	message?: string;
	state: NearbySessionState;
};

export type CameraState = "failed" | "initializing" | "interrupted" | "limited" | "running" | "unsupported";

export type CameraStatePayload = {
	message?: string;
	reason?: "permission_denied";
	state: CameraState;
};

export type SpatialAttendeeProfile = {
	askMeAbout: string[];
	headline: string;
	name: string;
	userId: string;
};

export type AReachSpatialViewProps = {
	attendeeProfiles?: SpatialAttendeeProfile[];
	onCameraStateChange?: (payload: CameraStatePayload) => void;
	onOverlayPress?: (payload: SpatialOverlayPressPayload) => void;
	style?: StyleProp<ViewStyle>;
};

export type SpatialOverlayPressPayload = {
	action: "open_details" | "open_topics";
	peerId: string;
	userId: string;
};
