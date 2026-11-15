import Constants from "expo-constants";
import { useTheme } from "@/lib/theme/hooks";
import { Card } from "@/lib/ui/card";
import { Column } from "@/lib/ui/column";
import { Image } from "@/lib/ui/image";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";
import { View } from "@/lib/ui/view";

const iconSource = require("@/assets/images/icon.png");

export default function AboutScreen() {
	const theme = useTheme();
	const appVersion = Constants.expoConfig?.version ?? "Unknown";

	return (
		<Screen headerInset scrollable>
			<Column gap="xl" paddingBottom="xl" paddingHorizontal="lg" paddingTop="lg">
				<Column align="center" gap="sm">
					<View style={{ borderRadius: theme.radius.xl, height: 96, overflow: "hidden", width: 96 }}>
						<Image contentFit="cover" source={iconSource} height={96} width={96} />
					</View>
					<Text size="xl" weight="bold">
						AReach
					</Text>
					<Text align="center" color={theme.colors.textSecondary} size="sm">
						Real connections. Real impact. Right where you are.
					</Text>
					<Text color={theme.colors.textMuted} size="xs">
						Version {appVersion}
					</Text>
				</Column>

				<Card padding="lg">
					<Column gap="sm">
						<Text size="lg" weight="bold">
							About AReach
						</Text>
						<Text color={theme.colors.textSecondary} size="md">
							AReach helps guests discover and connect with people at private events. Invite-based access, contextual profiles, and nearby
							interaction help turn digital discovery into real conversations.
						</Text>
					</Column>
				</Card>
			</Column>
		</Screen>
	);
}
