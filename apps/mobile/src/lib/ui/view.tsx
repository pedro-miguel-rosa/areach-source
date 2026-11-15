import { View as RNView, type ViewProps as RNViewProps } from "react-native";

export type ViewProps = RNViewProps;

export function View(props: ViewProps) {
	return <RNView {...props} />;
}
