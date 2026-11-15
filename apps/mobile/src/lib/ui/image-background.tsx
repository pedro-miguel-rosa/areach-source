import { ImageBackground as ExpoImageBackground } from "expo-image";
import type { ComponentProps, ReactNode } from "react";
import { createStyles } from "@/lib/theme/factories";

type ImageBackgroundProps = {
	children: ReactNode;
	source: ComponentProps<typeof ExpoImageBackground>["source"];
};

export function ImageBackground(props: ImageBackgroundProps) {
	const { children, source } = props;
	const { styles } = useStyles();

	return (
		<ExpoImageBackground source={source} style={styles.background}>
			{children}
		</ExpoImageBackground>
	);
}

const useStyles = createStyles(() => ({
	background: {
		flex: 1,
	},
}));
