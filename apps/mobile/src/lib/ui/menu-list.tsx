import { Pressable } from "react-native";
import { createStyles } from "@/lib/theme/factories";
import { Card } from "@/lib/ui/card";
import { Icon, type IconName } from "@/lib/ui/icon";
import { Row } from "@/lib/ui/row";
import { Text } from "@/lib/ui/text";

export type MenuListItem = {
	destructive?: boolean;
	icon: IconName;
	label: string;
	onPress: () => void;
};

export function MenuList({ items }: { items: MenuListItem[] }) {
	const { styles, theme } = useStyles();

	return (
		<Card padding="sm">
			{items.map((item, index) => (
				<Pressable
					accessibilityRole="button"
					key={item.label}
					onPress={item.onPress}
					style={[styles.item, index < items.length - 1 && styles.itemBorder]}
				>
					<Row align="center" gap="sm" justify="space-between">
						<Row align="center" gap="sm">
							<Icon color={item.destructive ? theme.colors.error : theme.colors.textSecondary} name={item.icon} size={18} />
							<Text color={item.destructive ? theme.colors.error : theme.colors.text} size="sm">
								{item.label}
							</Text>
						</Row>
						<Icon color={theme.colors.text} name="chevronRight" size={18} />
					</Row>
				</Pressable>
			))}
		</Card>
	);
}

const useStyles = createStyles((theme) => ({
	item: {
		minHeight: 48,
		paddingHorizontal: theme.spacing.md,
		paddingVertical: theme.spacing.sm,
	},
	itemBorder: {
		borderBottomColor: theme.colors.border,
		borderBottomWidth: 1,
	},
}));
