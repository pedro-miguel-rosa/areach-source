import { createContext, type ReactNode, useContext, useEffect, useMemo, useState } from "react";
import { Appearance, useColorScheme } from "react-native";
import { darkTheme, lightTheme } from "./themes";
import type { Theme } from "./types";

export type ThemePreference = "dark" | "light" | "system";

type ThemePreferenceContextValue = {
	preference: ThemePreference;
	setPreference: (preference: ThemePreference) => void;
};

const ThemePreferenceContext = createContext<ThemePreferenceContextValue | null>(null);

export function ThemeProvider({ children }: { children: ReactNode }) {
	const [preference, setPreference] = useState<ThemePreference>("system");

	useEffect(() => {
		Appearance.setColorScheme(preference === "system" ? "unspecified" : preference);
	}, [preference]);

	const value = useMemo(() => ({ preference, setPreference }), [preference]);

	return <ThemePreferenceContext.Provider value={value}>{children}</ThemePreferenceContext.Provider>;
}

export function useTheme(): Theme {
	const { preference } = useThemePreference();
	const systemColorScheme = useColorScheme();
	const isDark = preference === "dark" || (preference === "system" && systemColorScheme === "dark");

	return useMemo(() => (isDark ? darkTheme : lightTheme), [isDark]);
}

export function useThemePreference() {
	const context = useContext(ThemePreferenceContext);

	if (!context) {
		throw new Error("useThemePreference must be used within ThemeProvider");
	}

	return context;
}
