import { NativeTabs } from "expo-router/unstable-native-tabs";
import type { ReactNode } from "react";
import { useTheme } from "@/lib/theme/hooks";

type TabsProps = {
	children: ReactNode;
};

function TabsRoot(props: TabsProps) {
	const { children } = props;
	const theme = useTheme();

	return (
		<NativeTabs
			backgroundColor={theme.colors.surface}
			badgeBackgroundColor={theme.colors.textLink}
			iconColor={{
				default: theme.colors.text,
				selected: theme.colors.textLink,
			}}
			indicatorColor={theme.colors.textLink}
			labelStyle={{
				default: {
					color: theme.colors.text,
					fontSize: 12,
					fontWeight: theme.typography.weight.semibold,
				},
				selected: {
					color: theme.colors.textLink,
					fontSize: 12,
					fontWeight: theme.typography.weight.semibold,
				},
			}}
			tintColor={theme.colors.textLink}
		>
			{children}
		</NativeTabs>
	);
}

export const Tabs = Object.assign(TabsRoot, {
	BottomAccessory: NativeTabs.BottomAccessory,
	Trigger: NativeTabs.Trigger,
});
