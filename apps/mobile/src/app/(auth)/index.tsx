import { AnimatedWelcomeBackground } from "@/features/auth/components";
import { router } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { Column } from "@/lib/ui/column";
import { Image } from "@/lib/ui/image";
import { Text } from "@/lib/ui/text";

const backgroundSource = require("@/assets/images/auth-welcome-background.png");
const markSource = require("@/assets/images/splash-icon.png");

export default function WelcomeScreen() {
	const theme = useTheme();

	return (
		<AnimatedWelcomeBackground source={backgroundSource}>
			<Column flex paddingVertical="xxxl" paddingHorizontal="xl" width="100%">
				<Column flex justify="center" gap="lg">
					<Column align="center" gap="md">
						<Image source={markSource} height={128} width={128} />
						<Text appearance="dark" size="xxl" weight="bold">
							AReach
						</Text>
					</Column>
					<Text align="center" appearance="dark" lineHeight={theme.typography.lineHeight.md} opacity={0.88} size="md">
						{"Real connections.\nReal impact.\nRight where you are."}
					</Text>
				</Column>
				<Column gap="md">
					<Button appearance="light" onPress={() => router.push("/sign-in")} variant="white">
						Sign in
					</Button>
					<Button appearance="light" onPress={() => router.push("/sign-up")} variant="outline">
						Create account
					</Button>
				</Column>
			</Column>
		</AnimatedWelcomeBackground>
	);
}
