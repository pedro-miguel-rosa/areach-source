import { Pressable } from "react-native";
import { type ThemePreference, useTheme, useThemePreference } from "@/lib/theme/hooks";
import { Card } from "@/lib/ui/card";
import { Column } from "@/lib/ui/column";
import { Icon } from "@/lib/ui/icon";
import { Row } from "@/lib/ui/row";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";

const APPEARANCE_OPTIONS: Array<{ description: string; label: string; value: ThemePreference }> = [
	{
		description: "Use the appearance selected on your device.",
		label: "System",
		value: "system",
	},
	{
		description: "Use a bright appearance throughout AReach.",
		label: "Light",
		value: "light",
	},
	{
		description: "Use a darker appearance throughout AReach.",
		label: "Dark",
		value: "dark",
	},
];

export default function AppearanceScreen() {
	const theme = useTheme();
	const { preference, setPreference } = useThemePreference();

	return (
		<Screen headerInset scrollable>
			<Column gap="lg" paddingBottom="xl" paddingHorizontal="lg" paddingTop="lg">
				<Column gap="xs">
					<Text size="lg" weight="bold">
						Choose your appearance
					</Text>
					<Text color={theme.colors.textSecondary} size="sm">
						Select whether AReach follows your device or uses a fixed theme.
					</Text>
				</Column>

				<Card padding="sm">
					{APPEARANCE_OPTIONS.map((option, index) => {
						const isSelected = option.value === preference;

						return (
							<Pressable
								accessibilityRole="radio"
								accessibilityState={{ selected: isSelected }}
								key={option.value}
								onPress={() => setPreference(option.value)}
								style={{
									borderBottomColor: theme.colors.border,
									borderBottomWidth: index < APPEARANCE_OPTIONS.length - 1 ? 1 : 0,
									paddingHorizontal: theme.spacing.md,
									paddingVertical: theme.spacing.sm,
								}}
							>
								<Row align="center" gap="md" justify="space-between">
									<Column flex gap="xxs">
										<Text size="sm" weight="semibold">
											{option.label}
										</Text>
										<Text color={theme.colors.textSecondary} size="xs">
											{option.description}
										</Text>
									</Column>
									<Icon color={theme.colors.textLink} name="checkCircle" size={22} style={{ opacity: isSelected ? 1 : 0 }} />
								</Row>
							</Pressable>
						);
					})}
				</Card>
			</Column>
		</Screen>
	);
}
