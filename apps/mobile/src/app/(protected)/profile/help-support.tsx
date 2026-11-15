import { useState } from "react";
import { Pressable } from "react-native";
import { useTheme } from "@/lib/theme/hooks";
import { Card } from "@/lib/ui/card";
import { Column } from "@/lib/ui/column";
import { Icon } from "@/lib/ui/icon";
import { Row } from "@/lib/ui/row";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";

const SUPPORT_TOPICS = [
	{
		answer: "From Home, select Join with Code and enter the invite code shared by the event host.",
		question: "How do I join an event?",
	},
	{
		answer: "From Home, select Create and complete the event details. Once the event is created, share its invite code with your guests.",
		question: "How do I create an event?",
	},
	{
		answer:
			"Inside a live event, AReach uses the camera and Nearby Interaction to help show participants around you. Grant the requested permissions when prompted.",
		question: "How does nearby discovery work?",
	},
	{
		answer: "Open Profile, select Appearance, and choose System, Light, or Dark.",
		question: "How do I change the app appearance?",
	},
] as const;

export default function HelpSupportScreen() {
	const theme = useTheme();
	const [expandedTopic, setExpandedTopic] = useState<number | null>(null);

	return (
		<Screen headerInset scrollable>
			<Column gap="lg" paddingBottom="xl" paddingHorizontal="lg" paddingTop="lg">
				<Column gap="xs">
					<Text size="lg" weight="bold">
						How can we help?
					</Text>
					<Text color={theme.colors.textSecondary} size="sm">
						Find quick answers about using AReach at your event.
					</Text>
				</Column>

				<Column gap="xs">
					<Text size="sm" weight="bold">
						Common questions
					</Text>
					<Card padding="sm">
						{SUPPORT_TOPICS.map((topic, index) => {
							const isExpanded = expandedTopic === index;

							return (
								<Column key={topic.question}>
									<Pressable
										accessibilityRole="button"
										accessibilityState={{ expanded: isExpanded }}
										onPress={() => setExpandedTopic(isExpanded ? null : index)}
										style={{
											borderBottomColor: theme.colors.border,
											borderBottomWidth: index < SUPPORT_TOPICS.length - 1 ? 1 : 0,
											paddingHorizontal: theme.spacing.md,
											paddingVertical: theme.spacing.md,
										}}
									>
										<Row align="center" gap="md" justify="space-between">
											<Column flex>
												<Text size="sm" weight="semibold">
													{topic.question}
												</Text>
											</Column>
											<Icon
												color={theme.colors.textSecondary}
												name="chevronRight"
												size={18}
												style={{ transform: [{ rotate: isExpanded ? "90deg" : "0deg" }] }}
											/>
										</Row>
									</Pressable>

									{isExpanded ? (
										<Column paddingBottom="md" paddingHorizontal="md" paddingTop="sm">
											<Text color={theme.colors.textSecondary} size="sm">
												{topic.answer}
											</Text>
										</Column>
									) : null}
								</Column>
							);
						})}
					</Card>
				</Column>

				<Card padding="lg">
					<Column gap="sm">
						<Row align="center" gap="sm">
							<Icon color={theme.colors.textLink} name="help" size={22} />
							<Text size="md" weight="bold">
								Need more help?
							</Text>
						</Row>
						<Text color={theme.colors.textSecondary} size="sm">
							For event-specific questions, contact the event host or organizer who shared your invite code.
						</Text>
					</Column>
				</Card>
			</Column>
		</Screen>
	);
}
