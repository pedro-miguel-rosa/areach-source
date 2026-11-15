import { requireNativeView } from "expo";
import type * as React from "react";
import { useCallback } from "react";
import type { NativeSyntheticEvent } from "react-native";

import type { AReachSpatialViewProps, CameraStatePayload, SpatialOverlayPressPayload } from "./AReachSpatial.types";

type NativeAReachSpatialViewProps = {
	attendeeProfiles?: AReachSpatialViewProps["attendeeProfiles"];
	onCameraStateChange?: (event: NativeSyntheticEvent<CameraStatePayload>) => void;
	onOverlayPress?: (event: NativeSyntheticEvent<SpatialOverlayPressPayload>) => void;
	style?: AReachSpatialViewProps["style"];
};

const NativeView: React.ComponentType<NativeAReachSpatialViewProps> = requireNativeView("AReachSpatial");

export default function AReachSpatialView(props: AReachSpatialViewProps) {
	const { onCameraStateChange, onOverlayPress, ...viewProps } = props;

	const handleCameraStateChange = useCallback(
		(event: NativeSyntheticEvent<CameraStatePayload>) => onCameraStateChange?.(event.nativeEvent),
		[onCameraStateChange],
	);

	const handleOverlayPress = useCallback(
		(event: NativeSyntheticEvent<SpatialOverlayPressPayload>) => onOverlayPress?.(event.nativeEvent),
		[onOverlayPress],
	);

	return <NativeView {...viewProps} onCameraStateChange={handleCameraStateChange} onOverlayPress={handleOverlayPress} />;
}
