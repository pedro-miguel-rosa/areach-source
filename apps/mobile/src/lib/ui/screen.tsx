import { HeaderHeightContext } from "expo-router/react-navigation";
import type { ReactElement, ReactNode } from "react";
import { useContext } from "react";
import { type RefreshControlProps, ScrollView, View } from "react-native";
import { createStyles } from "@/lib/theme/factories";

type ScreenProps = {
	children: ReactNode;
	fill?: boolean;
	headerInset?: boolean;
	refreshControl?: ReactElement<RefreshControlProps>;
	scrollable?: boolean;
};

export function Screen(props: ScreenProps) {
	const { children, fill = false, headerInset = false, refreshControl, scrollable = false } = props;
	const { styles } = useStyles();

	const headerHeight = useContext(HeaderHeightContext);
	const headerInsetStyle = headerInset && headerHeight !== undefined ? { paddingTop: headerHeight } : undefined;

	return scrollable ? (
		<ScrollView
			automaticallyAdjustKeyboardInsets
			contentContainerStyle={[fill && styles.fillContent, headerInsetStyle]}
			keyboardShouldPersistTaps="handled"
			refreshControl={refreshControl}
			showsVerticalScrollIndicator={false}
			style={styles.container}
		>
			{children}
		</ScrollView>
	) : (
		<View style={[styles.container, headerInsetStyle]}>{children}</View>
	);
}

const useStyles = createStyles((theme) => ({
	container: {
		backgroundColor: theme.colors.background,
		flex: 1,
	},
	fillContent: {
		flexGrow: 1,
	},
}));
