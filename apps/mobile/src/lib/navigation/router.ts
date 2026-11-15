import { router, useIsFocused, useLocalSearchParams, useNavigation } from "expo-router";

export { router, useIsFocused, useNavigation };

export function usePathParam(paramName: string, fallback = "") {
	const value = useLocalSearchParams()[paramName];

	if (Array.isArray(value)) {
		return value[0] ?? fallback;
	}

	return value ?? fallback;
}
