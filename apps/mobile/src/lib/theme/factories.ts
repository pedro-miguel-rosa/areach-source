import { useMemo } from "react";
import { type ImageStyle, StyleSheet, type TextStyle, type ViewStyle } from "react-native";
import { useTheme } from "./hooks";
import type { Theme } from "./types";

type ReactNativeStyles = Record<string, ViewStyle | TextStyle | ImageStyle>;

export function createStyles<const T extends ReactNativeStyles>(input: T | ((theme: Theme) => T)) {
	return function useStyles() {
		const theme = useTheme();
		const styles = useMemo(() => {
			const resolvedStyles = typeof input === "function" ? input(theme) : input;
			return StyleSheet.create(resolvedStyles);
		}, [theme]);

		return { theme, styles };
	};
}
