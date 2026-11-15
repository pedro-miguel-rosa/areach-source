import { type StyleProp, Text, View, type ViewStyle } from "react-native";
import { createStyles } from "@/lib/theme/factories";
import { Image } from "@/lib/ui/image";

export type AvatarSize = "sm" | "md" | "lg" | "xl" | number;

type AvatarProps = {
	imageUrl?: string | null;
	label?: string;
	size?: AvatarSize;
	style?: StyleProp<ViewStyle>;
};

export function Avatar(props: AvatarProps) {
	const { imageUrl, label = "AReach", size = 72, style } = props;
	const { styles, theme } = useStyles();
	const resolvedSize = getAvatarSize(size);
	const initials = getInitials(label);
	const avatarStyle: StyleProp<ViewStyle> = [
		styles.avatar,
		{
			width: resolvedSize,
			height: resolvedSize,
			borderRadius: resolvedSize / 2,
		},
		style,
	];

	return (
		<View accessibilityLabel={label} accessibilityRole="image" style={avatarStyle}>
			{imageUrl ? (
				<Image contentFit="cover" height={resolvedSize} source={{ uri: imageUrl }} width={resolvedSize} />
			) : (
				<Text style={[styles.initials, { color: theme.colors.textInverse, fontSize: resolvedSize >= 72 ? 22 : 16 }]}>{initials}</Text>
			)}
		</View>
	);
}

function getAvatarSize(size: AvatarSize) {
	if (typeof size === "number") {
		return size;
	}

	const sizes = {
		sm: 32,
		md: 48,
		lg: 72,
		xl: 88,
	} as const;

	return sizes[size];
}

function getInitials(label: string) {
	const initials = label
		.trim()
		.split(" ")
		.filter(Boolean)
		.slice(0, 2)
		.map((part) => part[0]?.toUpperCase() ?? "")
		.join("");

	return initials || "A";
}

const useStyles = createStyles((theme) => ({
	avatar: {
		alignItems: "center",
		backgroundColor: theme.colors.primary,
		justifyContent: "center",
		overflow: "hidden",
	},
	initials: {
		fontWeight: theme.typography.weight.bold,
	},
}));
