import type { ImageContentFit, ImageSource } from "expo-image";
import { Image as ExpoImage } from "expo-image";

export type ImageProps = {
	source: ImageSource | string | number;
	height?: number;
	width?: number;
	contentFit?: ImageContentFit;
};

export function Image(props: ImageProps) {
	const { source, height, width, contentFit } = props;
	const sizeStyle = width != null || height != null ? { height, width } : undefined;

	return <ExpoImage source={source} contentFit={contentFit} style={sizeStyle} />;
}
